"""A Kbuild wrap header: an `<arch>/include/generated` twin of an
asm-generic header.

Kbuild's `wrap` step (arch/`$(SRCARCH)`/Makefile's `generated-y +=` against
`scripts/Makefile.asm-generic`) writes one line into the generated tree:

    #include <asm-generic/mcs_spinlock.h>

so the arch sees the generic header under its own name. The generated
header is what `#include <asm/mcs_spinlock.h>` resolves to; the generic one
is included by name at compile time.

    wrap_header(
        name = "mcs_spinlock_h",
        outs = ["include/generated/asm/mcs_spinlock.h"],
        include = "asm-generic/mcs_spinlock.h",
    )

The rule carries no inputs, as Kbuild's wrap step does not either: the
`#include` is resolved when the header is compiled, by the consumer.
"""

def _wrap_header_impl(ctx):
    out = ctx.outputs.outs[0]
    ctx.actions.run_shell(
        outputs = ctx.outputs.outs,
        command = 'echo "#include <%s>" > %s' % (ctx.attr.include, out.path),
        mnemonic = "Genrule",
        progress_message = "Wrap %s" % out.short_path,
    )
    return [DefaultInfo(files = depset(ctx.outputs.outs))]

wrap_header = rule(
    implementation = _wrap_header_impl,
    attrs = {
        "outs": attr.output_list(mandatory = True,
                                 doc = "the generated header, as a path under the package"),
        "include": attr.string(mandatory = True,
                               doc = "the header the wrap includes, by its include name"),
    },
    doc = "A Kbuild wrap header (see the module docstring).",
)
