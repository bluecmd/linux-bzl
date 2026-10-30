"""The test image's initrd: the layer's packer script over its declared
inputs.

`make-initrd.sh` unpacks the pinned package files into a root, lays out
`/init`, the test SSH key and the BusyBox symlinks, and packs the tree as a
gzip'd newc cpio (`--reproducible`, so the bytes are stable). A rule, not a
genrule: the script is the rule's tool and everything it reads is a declared
input of the action that runs it.

    initrd_cpio(
        name = "initrd",
        init = "init",
        keys = "test_authorized_keys",
        apks = APKS,
        out = "initrd.cpio.gz",
    )
"""

def _initrd_cpio_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.out)
    args = ctx.actions.args()
    # $@ of the genrule this replaces was the FULL declared path; the script
    # writes exactly there
    args.add(out.path)
    args.add(ctx.file.init.path)
    args.add(ctx.file.keys.path)
    for apk in ctx.files.apks:
        args.add(apk.path)
    ctx.actions.run(
        executable = ctx.executable.script,
        arguments = [args],
        inputs = [ctx.file.init, ctx.file.keys] + list(ctx.files.apks),
        outputs = [out],
        tools = [ctx.executable.script],
        mnemonic = "Genrule",
        progress_message = "Packing initrd %s" % out.short_path,
    )
    return [DefaultInfo(files = depset([out]))]

initrd_cpio = rule(
    implementation = _initrd_cpio_impl,
    attrs = {
        "init": attr.label(mandatory = True, allow_single_file = True,
                           doc = "the /init the image boots with"),
        "keys": attr.label(mandatory = True, allow_single_file = True,
                           doc = "the test SSH key's public half, authorized in the root"),
        "apks": attr.label_list(mandatory = True, allow_files = True,
                                doc = "the package files unpacked into the root"),
        "out": attr.string(default = "initrd.cpio.gz",
                           doc = "the packed cpio's name in the package"),
        "script": attr.label(mandatory = True, allow_single_file = True,
                              executable = True, cfg = "exec",
                              doc = "the packer script (runs on the exec platform)"),
    },
    doc = "The test initrd: the packer script over its inputs (see the module docstring).",
)
