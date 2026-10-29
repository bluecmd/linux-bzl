"""A lexer flex generates from a `.l` (Kbuild's host-programs recipe,
`$(LEX) -o$@ -L $<` in scripts/Makefile.host): `-L` keeps the `#line`
references out. The generated file's content does not depend on the paths
the action spells, so the rule names the declared file directly:

    flex(
        name = "lexer",
        src = "lexer.l",
        outs = ["lexer.lex.c"],
    )
"""

def _impl(ctx):
    out = ctx.outputs.outs[0]
    ctx.actions.run_shell(
        command = "flex -o \"$1\" -L \"$2\"",
        arguments = [out.path, ctx.file.src.path],
        inputs = [ctx.file.src],
        outputs = [out],
        mnemonic = "Flex",
        progress_message = "Flex %s" % out.short_path,
    )
    return [DefaultInfo(files = depset(ctx.outputs.outs))]

flex = rule(
    implementation = _impl,
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True,
                          doc = "the lexer description the tool reads"),
        "outs": attr.output_list(mandatory = True,
                                 doc = "the generated lexer, as a path under the package"),
    },
)
