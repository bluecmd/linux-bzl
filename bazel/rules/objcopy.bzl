"""A Kbuild `objcopy` step: a link output converted or stripped by the
toolchain's objcopy.

Kbuild's `cmd_objcopy` (scripts/Makefile.lib) and the boot code's own
post-processing run `$(OBJCOPY)` -- `llvm-objcopy` -- over a link output:
the realmode blob, the boot sectors, the raw kernel image, a `pi.o` with
its symbols prefixed, the debug-info-stripped vdso:

    objcopy(
        name = "realmode_bin",
        src = ":realmode.elf",
        out = "realmode.bin",
        args = ["-O", "binary"],
    )

The tool is the kernel's LLVM toolchain, not a toolchain of its own: the
rule runs `$(OBJCOPY)` exactly as the reference spelled it.
"""

def _objcopy_impl(ctx):
    ctx.actions.run(
        executable = ctx.executable._objcopy,
        arguments = list(ctx.attr.args) + [ctx.file.src.path, ctx.outputs.out.path],
        inputs = [ctx.file.src],
        outputs = [ctx.outputs.out],
        mnemonic = "Genrule",
        progress_message = "Objcopy %s" % ctx.outputs.out.short_path,
    )
    return [DefaultInfo(files = depset([ctx.outputs.out]))]

objcopy = rule(
    implementation = _objcopy_impl,
    attrs = {
        "args": attr.string_list(
            doc = "the options between the tool and the input/output files",
        ),
        "src": attr.label(mandatory = True, allow_single_file = True,
                          doc = "the input converted"),
        "out": attr.output(mandatory = True,
                           doc = "the converted file, as a path under the package"),
        "_objcopy": attr.label(
            default = "@kernel_llvm//:bin/llvm-objcopy",
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "`$(OBJCOPY)`",
        ),
    },
    doc = "A Kbuild objcopy step (see the module docstring).",
)
