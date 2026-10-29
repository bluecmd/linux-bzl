"""Kbuild's savedcmd (`cmd_…` + if_changed, `cmd_vmlinux.o`, `cmd_bzImage`
&c.): the step's echo tag, the cleanup traps (HUP, INT, QUIT, TERM, PIPE, the
output removed), the command itself, and the `.cmd` file the
`savedcmd_<out> := <cmd>` line lands in. The glue is the rule's own work,
written once; the call carries the tag word and the command, and whatever
else a tree_recipe carries:

    savedcmd(
        name = "bzImage",
        outs = ["bzImage"],
        tag = "BUILD",
        cmd = "(dd if=arch/x86/boot/setup.bin bs=4k conv=sync status=none; "
              "cat arch/x86/boot/vmlinux.bin) >arch/x86/boot/bzImage",
        srcs = ["//arch/x86/boot:setup.bin", "//arch/x86/boot:vmlinux_bin"],
        env_map = dict(COMMON_ENV, ...),
    )

The line the rule runs is the reference's recipe, byte for byte
(tree_recipe's), so the differ compares it as before. The recipe spells the
output the way the reference's cwd did -- the tree path, the package
included -- while the call's `outs` are the package's own label paths; the
package bridges the two, exactly as `tree_recipe`'s bin-root mirror does."""

load(":tree_recipe.bzl", "tree_recipe")

_SAVEDCMD_SIGS = ("HUP", "INT", "QUIT", "TERM", "PIPE")

def savedcmd(name, outs, cmd, tag, **kwargs):
    out = outs[0]
    pkg = native.package_name()
    tree_out = pkg + "/" + out if pkg else out
    dir_ = tree_out.rpartition("/")[0] or "."
    echo = "  " + tag + " " * (8 - len(tag)) + tree_out
    traps = ""
    for i, sig in enumerate(_SAVEDCMD_SIGS):
        traps += ("   " if i == 0 else "  ") + "trap 'rm -f %s; trap - %s; kill -s %s $$' %s;" % (tree_out, sig, sig, sig)
    saved = "'" + (("savedcmd_%s := %s" % (tree_out, cmd))
        .replace("'", "'\\''").replace("$", "$$")) + "'"
    glue = ("set -e;  echo '" + echo + "';" + traps + " " + cmd
            + "; printf '%s\\n' " + saved + " > " + dir_ + "/." + tree_out.rpartition("/")[2] + ".cmd")
    tree_recipe(
        name = name,
        outs = [out],
        recipe = ["/bin/sh -c '" + glue.replace("$", "$$").replace("'", "'\\''") + "'"],
        **kwargs
    )
