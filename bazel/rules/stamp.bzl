"""Kbuild's filechk stamp (`cmd_compile.h`, `cmd_timeconst.h` &c.): the
generator's stdout into `.tmp_<out>` beside the output, `cmp -s` + `mv -f`
stamping the output when it changed, the tmp removed on exit. The glue is
the rule's own work, written once; the call carries the generator line and
whatever else a tree_recipe carries:

    stamp(
        name = "timeconst_h",
        outs = ["include/generated/timeconst.h"],
        cmd = "echo 250 | bc -q kernel/time/timeconst.bc",
        srcs = ["//kernel/time:timeconst.bc"],
        stage = ["//kernel/time:timeconst.bc"],
        stage_dests = ["kernel/time/timeconst.bc"],
        tools = ["@bc//:bc"],
        tool_words = ["bc"],
        env_map = dict(COMMON_ENV, KERNELRELEASE = "7.2.0"),
    )

The line the rule runs is the reference's recipe, byte for byte
(tree_recipe's), so the differ compares it as before. The recipe spells the
output the way the reference's cwd did -- the tree path, the package
included (`init/utsversion-tmp.h`, `arch/x86/include/generated/asm/…`) --
while the call's `outs` are the package's own label paths; the package
bridges the two, exactly as `tree_recipe`'s bin-root mirror does."""

load(":tree_recipe.bzl", "tree_recipe")

def stamp(name, outs, cmd, **kwargs):
    out = outs[0]
    tree_out = native.package_name() + "/" + out if native.package_name() else out
    dir_ = tree_out.rpartition("/")[0]
    tmp = dir_ + "/.tmp_" + tree_out.rpartition("/")[2]
    glue = ("set -e; mkdir -p " + dir_ + '/; trap "rm -f ' + tmp + '" EXIT; { '
            + cmd + "; } > " + tmp
            + "; if [ ! -r " + tree_out + " ] || ! cmp -s " + tree_out + " " + tmp
            + '; then echo \'  UPD     ' + tree_out + "'; mv -f " + tmp + " " + tree_out + "; fi")
    tree_recipe(
        name = name,
        outs = [out],
        recipe = ["/bin/sh -c '" + glue.replace("$", "$$").replace("'", "'\\''") + "'"],
        **kwargs
    )
