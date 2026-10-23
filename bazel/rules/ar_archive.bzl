"""An archive the reference built with its own ar recipe: the kernel's
`llvm-ar cDPrST built-in.a a.o b.o ...`, whose member order is the link
order -- a `cc_static_library` merges its deps' objects in Bazel's order,
not the reference's, and thin archives (the `T` modifier: members kept by
name, not copied) have no cc rule of their own. This rule runs the cc
toolchain's archiver with the reference's line, members in order:

    ar_archive(
        name = "arch_x86_boot_startup_built_in_a",
        out = "arch/x86/boot/startup/built-in.a",
        op = "cDPrST",
        members = ["arch/x86/boot/startup/gdt_idt.pi.o",
                   "arch/x86/boot/startup/map_kernel.pi.o"],
        srcs = [":...object_files", "arch/x86/boot/startup/bioscall.o"],
        ar = "@kernel_llvm//:bin/llvm-ar",
    )

`members` are the archive's operands, by label, in the order the
reference spelled them (paths under the package); every member file (and
everything else ar opens -- a nested thin archive's leaf objects) is
declared in `srcs`. The action's mnemonic is CppArchive, so any2bazel's
differ compares its line with the reference's. The rule also provides
CcInfo (the archive as a static library), so cc targets may take it in
deps the way the reference's aggregates took its archives.
"""

load("@rules_cc//cc/private:cc_info.bzl", "CcInfo", "create_linking_context")
load("@rules_cc//cc/private/link:create_library_to_link.bzl", "make_library_to_link")
load("@rules_cc//cc/private/link:create_linker_input.bzl", "create_linker_input")

def _impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.out)
    args = [ctx.attr.op, out.path] + [f.path for f in ctx.files.members]
    ctx.actions.run(
        executable = ctx.executable.ar,
        arguments = args,
        inputs = depset(ctx.files.srcs),
        outputs = [out],
        mnemonic = "CppArchive",
        progress_message = "Archiving %s" % out.short_path,
    )
    lib = make_library_to_link(static_library = out,
                               _library_identifier = out.short_path)
    link = create_linking_context(linker_inputs = depset([
        create_linker_input(owner = ctx.label, libraries = depset([lib])),
    ]))
    return [CcInfo(linking_context = link), DefaultInfo(files = depset([out]))]

ar_archive = rule(
    implementation = _impl,
    attrs = {
        "out": attr.string(mandatory = True,
                           doc = "the archive file, as a path under the package"),
        "op": attr.string(mandatory = True,
                          doc = "the ar operation word (GNU ar's cDPrST, mPi -- case-sensitive)"),
        "members": attr.label_list(allow_files = True,
                                   doc = "the archive's members, by label, in the reference's order"),
        "srcs": attr.label_list(allow_files = True,
                                doc = "the member files, by label, and everything else ar opens"),
        "ar": attr.label(mandatory = True, allow_single_file = True, executable = True,
                         cfg = "exec", doc = "the archiver (the toolchain's llvm-ar)"),
    },
    doc = "An archive built with the reference's own ar recipe, members in the " +
          "reference's order (see the module docstring).",
)
