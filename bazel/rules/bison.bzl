"""The parser bison generates from a `.y` (Kbuild's host-programs recipe,
`$(YACC) -o $(basename $@).c --defines=$(basename $@).h -t -l $<` in
scripts/Makefile.host): `-t` keeps the debug traces in, `-l` the `#line`
directives out, and `--defines` writes the token header beside the parser.

The include guard bison puts in the header comes from the path the `-o`
argument spells -- `scripts/kconfig/parser.tab.c` names
`YY_YY_SCRIPTS_KCONFIG_PARSER_TAB_H_INCLUDED`. So the recipe runs in a
tree-shaped staging directory under the output, every path on its line as
the reference spelled it, and the two files then move to their declared
places:

    bison(
        name = "parser",
        src = "parser.y",
        outs = ["parser.tab.c", "parser.tab.h"],
    )
"""

def _impl(ctx):
    c = [o for o in ctx.outputs.outs if o.basename.endswith(".c")][0]
    h = [o for o in ctx.outputs.outs if o.basename.endswith(".h")][0]
    src = ctx.file.src
    ydir, _, yname = src.short_path.rpartition("/")
    stage = c.path + ".stage"           # a sibling directory, tree-shaped
    up = "../" * len(c.path.split("/")) # from the stage back to the execroot
    ctx.actions.run_shell(
        command = ("set -e; mkdir -p \"$1/$5\"; cp -p \"$2\" \"$1/$5/$6\"; " +
                   "cd \"$1\"; bison -o \"$5/$7\" --defines=\"$5/$8\" -t -l \"$5/$6\"; " +
                   "mv \"$5/$7\" \"$9$3\"; mv \"$5/$8\" \"$9$4\""),
        arguments = [stage, src.path, c.path, h.path, ydir, yname,
                     c.basename, h.basename, up],
        inputs = [src],
        outputs = [c, h],
        mnemonic = "Bison",
        progress_message = "Bison %s" % c.short_path,
    )
    return [DefaultInfo(files = depset(ctx.outputs.outs))]

bison = rule(
    implementation = _impl,
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True,
                          doc = "the grammar the tool reads"),
        "outs": attr.output_list(mandatory = True,
                                 doc = "the parser and its token header, as paths under the package"),
    },
)
