"""A recipe the reference ran in its own working directory.

A make-style recipe (Kbuild's `filechk`, a generator script the tree runs,
an archive edit line) reads and writes paths relative to the directory it
runs in; Bazel's execroot is not that directory -- its relative paths name
the pristine source tree. This rule mirrors the reference's working
directory under the output tree: every declared input is copied to its
logical path, the recipe's environment is exported, and the recipe runs
verbatim from that directory -- an output it writes relative to it lands on
the declared location.

    tree_recipe(
        name = "errno_h",
        outs = ["arch/x86/include/generated/uapi/asm/errno.h"],
        recipe = ["/bin/sh -c 'echo \"#include <asm-generic/errno.h>\" > ...'"],
        env = _RECIPE_ENV + " VPATH=. obj=arch/... srctree=. ",
        exports = ["CC", "AR", "LD", "NM", "OBJCOPY", "STRIP"],
        cc_wrappers = ["clang", "clang++"],
        bin_wrappers = {"ld.lld": "LD", "llvm-nm": "NM"},
        beside_wrappers = ["llvm-objdump", "llvm-readelf"],
    )

The glue a replaying genrule pasted per target is the rule's own work,
written once:

- `stage` copies the inputs that are not already at their logical paths
  there (`stage_dests`, aligned with it and with `stage_tools` -- the tools
  that run at a tree path, built for the exec platform -- names each
  destination under the output tree; `cp -p`: the copies keep their original
  mtimes, so a make the recipe runs sees its tree as the reference left it
  instead of finding every copy freshly written and rebuilding).
- `refresh` lists the generated inputs that already sit at their logical
  paths (`refresh_dests`, aligned with it, names each one) -- as read-only
  links whose mtimes say nothing about the order the reference built them
  in. The rule refreshes each with a fresh writable copy and gives them one
  mtime, leaving a make nothing to rebuild while still letting it overwrite
  what the build already produced.
- `exports` anchors the toolchain's make variables (`A2B_CC=$(CC)`, made
  absolute) that the recipe's environment and wrappers refer to.
- the wrappers (`cc_wrappers`, `bin_wrappers`, `beside_wrappers`,
  `path_tools`, `tools`) put on the recipe's PATH, by the name the
  reference's environment or recipe spells, a program that is one of the
  toolchain's make variables, one installed beside its compiler, a host
  tool by absolute path, or a target built by the workspace (a pinned
  external generator).

The recipe's environment (`env`) and lines (`recipe`) are spelled as the
reference recorded them -- paths relative to `cwd`, make-variable
references and `$` escapes included -- so the action's command is the
reference's, byte for byte, and any2bazel's differ compares it (the action
keeps the Genrule mnemonic it compares by).
"""

def _tree_recipe_impl(ctx):
    tc_files = ctx.attr._cc_toolchain[DefaultInfo].files
    pkg = ctx.label.package
    gendir = ctx.bin_dir.path + (("/" + pkg) if pkg else "")
    mirror = gendir if ctx.attr.cwd == "." else gendir + "/" + ctx.attr.cwd
    name = ctx.label.name
    bindir = gendir + "/.a2b-bin/" + name
    tmp = gendir + "/.a2b-refresh"
    outs = list(ctx.outputs.outs)

    dirs = {mirror: None}
    for d in ctx.attr.stage_dests:
        dirs[(gendir + "/" + d).rpartition("/")[0]] = None
    # the parents of the declared outputs: the recipe writes them from the
    # mirror, where no other action has made the directories (a genrule's
    # tree-wide staging made them; the rule makes its own)
    for o in outs:
        dirs[(gendir + "/" + o.short_path).rpartition("/")[0]] = None
    # the directories the recipe's spellings of the outputs traverse: a
    # `$(obj)/../<out>` spelling hops through the obj dir the reference's
    # build had made, which the mirror must have too
    for d in ctx.attr.out_dirs:
        dirs[mirror + "/" + d] = None
    cmd = ["mkdir -p " + " ".join(sorted(dirs))]
    for f, d in zip(list(ctx.files.stage) + list(ctx.files.stage_tools),
                    ctx.attr.stage_dests):
        # -p: the copies keep their original mtimes, so a make the line
        # runs sees its tree as the reference left it
        cmd.append("cp -p " + f.path + " " + gendir + "/" + d)
    refresh = list(zip(ctx.files.refresh, ctx.attr.refresh_dests))
    if refresh:
        cmd.append("mkdir -p " + tmp)
        for i, (f, d) in enumerate(refresh):
            dest = gendir + "/" + d
            # cp keeps the artifact's read-only mode; the line may well
            # have to overwrite it (a make that rebuilds it)
            cmd.append("cp %s %s/f%d && mv -f %s/f%d %s && chmod u+w %s"
                       % (f.path, tmp, i, tmp, i, dest, dest))
        # one mtime for all of them (the first copy's): a make sees no
        # prereq strictly newer than any target
        if len(refresh) > 1:
            cmd.append("touch -r " + " ".join([gendir + "/" + d for _f, d in refresh]))
    # the toolchain's make variables are execroot-relative (or absolute):
    # anchored to the execroot before the cd
    for mv in ctx.attr.exports:
        v = "A2B_" + mv
        cmd.append('export %s=$(%s) && { [ "$${%s#/}" != "$${%s}" ] || %s="$$PWD/$${%s}"; }'
                   % (v, mv, v, v, v, v))
    bin_wrapped = (ctx.attr.cc_wrappers or ctx.attr.bin_wrappers or
                   ctx.attr.beside_wrappers or ctx.attr.path_tools or
                   any(ctx.attr.tool_words))
    if bin_wrapped:
        cmd.append("mkdir -p " + bindir)
        for w in ctx.attr.cc_wrappers:
            cmd.append(("echo '#!/bin/sh' > %s/%s && " +
                        "echo 'exec \"$$A2B_CC\" \"$$@\"' >> %s/%s && chmod +x %s/%s")
                       % (bindir, w, bindir, w, bindir, w))
        for w, mv in ctx.attr.bin_wrappers.items():
            cmd.append(("echo '#!/bin/sh' > %s/%s && " +
                        "echo 'exec \"$$A2B_%s\" \"$$@\"' >> %s/%s && chmod +x %s/%s")
                       % (bindir, w, mv, bindir, w, bindir, w))
        for w in ctx.attr.beside_wrappers:
            cmd.append(("echo '#!/bin/sh' > %s/%s && " +
                        "echo 'exec \"$$(dirname \"$$A2B_CC\")/%s\" \"$$@\"' >> %s/%s && chmod +x %s/%s")
                       % (bindir, w, w, bindir, w, bindir, w))
        for w, p in ctx.attr.path_tools.items():
            cmd.append("ln -sf %s %s/%s" % (p, bindir, w))
        for t, w in zip(ctx.attr.tools, ctx.attr.tool_words):
            if not w:
                continue
            exe = t[DefaultInfo].files_to_run.executable
            # the workspace's own build of the generator (a pinned
            # external), copied into the bin dir the recipe's PATH has
            cmd.append("cp -f %s %s/%s && chmod +x %s/%s"
                       % (exe.path, bindir, w, bindir, w))
        cmd.append("export PATH=$$PWD/%s:$$PATH" % bindir)
        for k in sorted(ctx.attr.export_env):
            cmd.append("export %s=%s" % (k, ctx.attr.export_env[k]))
    cmd.append("cd " + mirror)
    for line in ctx.attr.recipe:
        # the environment the reference's make exported to the recipe
        # (Kbuild's srctree, CC, ARCH), riding the line as the reference's
        # make spelled it
        cmd.append(ctx.attr.env + line)
    ctx.actions.run_shell(
        # the toolchain's files ride along: the recipe's wrappers exec the
        # compiler by its anchored variable, and $(CC) expands to a file the
        # sandbox must hold (a genrule gets the same from its toolchains)
        inputs = depset(ctx.files.srcs, transitive = [tc_files]),
        tools = [t[DefaultInfo].files_to_run for t in ctx.attr.tools],
        outputs = outs,
        command = ctx.expand_make_variables("recipe", " && ".join(cmd), {}),
        use_default_shell_env = True,
        mnemonic = "Genrule",
        progress_message = "Recipe %s" % name,
    )
    return [DefaultInfo(files = depset(outs))]

tree_recipe = rule(
    implementation = _tree_recipe_impl,
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    attrs = {
        "outs": attr.output_list(mandatory = True,
                                 doc = "the files the recipe writes, as paths under the package "
                                 + "(declared: a rule that reads one by its path gets it)"),
        "_cc_toolchain": attr.label(
            default = "@bazel_tools//tools/cpp:current_cc_toolchain",
            doc = "the toolchain's files (compiler, binutils) the wrappers exec"),
        "srcs": attr.label_list(allow_files = True,
                                doc = "everything the recipe reads, by label"),
        "stage": attr.label_list(allow_files = True,
                                 doc = "inputs copied into the mirror tree"),
        "stage_tools": attr.label_list(cfg = "exec", allow_files = True,
                                       doc = "tools (built for the exec platform) copied into the mirror tree, after `stage`"),
        "stage_dests": attr.string_list(
            doc = "each `stage` and `stage_tools` input's destination under the output tree, aligned with both"),
        "out_dirs": attr.string_list(
            doc = "directories under the mirror the recipe's spellings of the outputs traverse (a `$(obj)/../<out>` hop the reference's build had made the obj dir for)"),
        "refresh": attr.label_list(allow_files = True,
                                   doc = "generated inputs already at their logical paths: refreshed writable, one mtime for all"),
        "refresh_dests": attr.string_list(
            doc = "each `refresh` input's path under the package, aligned with it"),
        "tools": attr.label_list(cfg = "exec",
                                 doc = "targets built for the exec platform whose programs the recipe's PATH has"),
        "tool_words": attr.string_list(
            doc = "the recipe's word for each `tools` target, in the same order"),
        "path_tools": attr.string_dict(
            doc = "host tools by absolute path, linked into the recipe's PATH by the name the recipe spells"),
        "cc_wrappers": attr.string_list(
            doc = "compiler names on the recipe's PATH, wrappers around the toolchain's CC"),
        "bin_wrappers": attr.string_dict(
            doc = "binutils names on the recipe's PATH -> the make variable the wrapper execs"),
        "beside_wrappers": attr.string_list(
            doc = "programs installed beside the toolchain's compiler, wrapped"),
        "exports": attr.string_list(
            doc = "toolchain make variables exported as A2B_<VAR> (anchored); the recipe's wrappers refer to them"),
        "export_env": attr.string_dict(
            doc = "static environment exported before the cd"),
        "env": attr.string(default = "",
                           doc = "the recipe's exported environment, as the reference's make spelled it"),
        "recipe": attr.string_list(mandatory = True,
                                   doc = "the recipe's command lines, verbatim, paths relative to cwd"),
        "cwd": attr.string(default = ".",
                           doc = "the reference's working directory, as a path under the package"),
    },
    doc = "A recipe the reference ran in its own working directory (see the " +
          "module docstring).",
)
