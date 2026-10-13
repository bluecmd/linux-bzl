"""A Kbuild `CHKSHA1` check: a generated header's SHA1 stamp verified
against the file itself.

Kbuild stamps such headers with the SHA1 of their content in the comment
that `scripts/Kbuild.include`'s `CHKSHA1` checks: the last line carries the
stamp, the check re-computes the SHA1 of the file minus its stamp line and
marks the check run:

    chksha1(
        name = "checked_atomic_long_h",
        src = "include/linux/atomic/atomic-long.h",
        out = ".checked-atomic-long.h",
    )

The out is the marker the build re-checks the header against; the header
itself is the input.
"""

def _chksha1_impl(ctx):
    src = ctx.file.src
    out = ctx.outputs.out
    ctx.actions.run_shell(
        inputs = [src],
        outputs = [out],
        command = (
            "if ! command -v sha1sum >/dev/null; then " +
            "echo \"warning: cannot check the header due to sha1sum missing\"; exit 0; fi; " +
            "if [ \"$(sed -n '$s:// ::p' %s)\" != " +
            "\"$(sed '$d' %s | sha1sum | sed 's/ .*//')\" ]; then " +
            "echo \"error: %s has been modified.\" >&2; exit 1; fi; touch %s"
        ) % (src.path, src.path, src.path, out.path),
        mnemonic = "Genrule",
        progress_message = "Chksha1 %s" % out.short_path,
    )
    return [DefaultInfo(files = depset([out]))]

chksha1 = rule(
    implementation = _chksha1_impl,
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True,
                          doc = "the header the stamp is checked against"),
        "out": attr.output(mandatory = True,
                           doc = "the marker the check run stamps"),
    },
    doc = "A Kbuild CHKSHA1 check (see the module docstring).",
)
