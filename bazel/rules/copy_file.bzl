"""A Kbuild `COPY` step: one file's bytes over another's name.

Kbuild's `cmd_copy` (scripts/Makefile.lib) copies a shipped file over the
file the build compiles, or a build product over the name the next step
reads it by:

    copy_file(
        name = "defkeymap_c",
        src = "defkeymap.c_shipped",
        out = "defkeymap.c",
    )

The copy is byte for byte -- the reference runs `cat src > out` -- and the
build re-stamps the out only when the bytes change.
"""

def _copy_file_impl(ctx):
    ctx.actions.run_shell(
        inputs = [ctx.file.src],
        outputs = [ctx.outputs.out],
        command = "cat %s > %s" % (ctx.file.src.path, ctx.outputs.out.path),
        mnemonic = "Genrule",
        progress_message = "Copy %s" % ctx.outputs.out.short_path,
    )
    return [DefaultInfo(files = depset([ctx.outputs.out]))]

copy_file = rule(
    implementation = _copy_file_impl,
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True,
                          doc = "the file copied"),
        "out": attr.output(mandatory = True,
                           doc = "the copy, as a path under the package"),
    },
    doc = "A Kbuild COPY step (see the module docstring).",
)
