"""A one-off generator step Kbuild runs as a single line (`cmd_conmakehash`,
`cmd_gen_crc32table`, mk_elfconfig, mkpiggy, vdso2c, relocs, the awk table
generators, the syscall table generators): a program over the files it
names on that line, its stdout over the output it declares -- or the output
spelled as the tool's last argument (the syscallhdr/syscalltbl lines). The
rule carries the line the reference ran, spelled the way a genrule spells
it:

    tool_stdout(
        name = "consolemap_deftbl_c",
        tool = ":conmakehash",
        srcs = ["cp437.uni"],
        out = "consolemap_deftbl.c",
        cmd = "$(location :conmakehash) $(location cp437.uni) > $@",
    )

`tool` names a generator the workspace builds; a generator the build runs
from the PATH (`awk -f script data > $@`, `sh scripts/syscallhdr.sh ... $@`)
rides the line itself. Ten one-off steps of the same shape are one rule
class, not ten genrules."""

def _impl(ctx):
    out = ctx.outputs.out
    deps = list(ctx.attr.srcs)
    files = list(ctx.files.srcs)
    if ctx.attr.tool:
        deps.append(ctx.attr.tool)
        files.append(ctx.file.tool)
    ctx.actions.run_shell(
        command = ctx.expand_location(ctx.attr.cmd.replace("$@", out.path), deps),
        inputs = files,
        outputs = [out],
        mnemonic = "Genrule",
        progress_message = "ToolStdout %s" % out.short_path,
    )
    return [DefaultInfo(files = depset([out]))]

tool_stdout = rule(
    implementation = _impl,
    attrs = {
        "tool": attr.label(allow_single_file = True,
                           doc = "the generator the workspace builds; the cmd spells it back"),
        "srcs": attr.label_list(allow_files = True,
                                doc = "the files the cmd's $(location)s name"),
        "out": attr.output(mandatory = True,
                           doc = "the generated file"),
        "cmd": attr.string(mandatory = True,
                           doc = "the generator line, with $@ the output and $(location) the files"),
    },
)
