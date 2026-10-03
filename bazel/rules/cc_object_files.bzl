"""The object files of a cc target, as files a genrule can name.

A reference recipe sometimes reads objects, not libraries: the kernel's
`mk_elfconfig < empty.o` (an ELF of the target to read its class and
endianness from) and `nm header.o reboot.o ... | sed > pasyms.h`
(realmode symbols), autotools' `nm` over objects for an export list.
Bazel's cc rules keep objects inside CcInfo; this rule hands the ones a
recipe names out as declared files, at the paths the recipe uses, so the
emitter's genrule lists them in `srcs` like any generated input:

    cc_library(name = "scripts_mod_empty", srcs = ["scripts/mod/empty.c"], ...)
    cc_object_files(
        name = "scripts_mod_empty_objects",
        lib = ":scripts_mod_empty",
        objects = ["scripts/mod/empty.o"],       # matched to the lib's objects by stem
    )
    genrule(srcs = ["scripts/mod/empty.o", ...], cmd = "... < $(location scripts/mod/empty.o)")

Each entry of `objects` is matched to one of the library's own objects
(not its deps') by source stem: `scripts/mod/empty.o` is the object
compiled from `empty.c` (PIC or not, whichever the library built). Two
sources of one stem in one library are an error here -- name them apart.
"""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _own_objects(lib):
    """The object files `lib` itself compiled (its linker inputs, not its deps')."""
    out = []
    for li in lib[CcInfo].linking_context.linker_inputs.to_list():
        if li.owner != lib.label:
            continue
        for l in li.libraries:
            out.extend(l.objects or [])
            out.extend(l.pic_objects or [])
    return out

def _stem(name):
    base = name.split("/")[-1]
    for ext in (".pic.o", ".o", ".obj"):
        if base.endswith(ext):
            return base[:-len(ext)]
    return base.rsplit(".", 1)[0] if "." in base else base

def _impl(ctx):
    objs = _own_objects(ctx.attr.lib)
    by_stem = {}
    for o in objs:
        by_stem.setdefault(_stem(o.basename), []).append(o)
    outs = []
    for out in ctx.outputs.objects:
        cands = by_stem.get(_stem(out.basename), [])
        if not cands:
            fail("%s: %s has no object for %s (its sources: %s)" % (
                ctx.label, ctx.attr.lib.label, out.short_path, sorted(by_stem)))
        non_pic = [c for c in cands if not c.basename.endswith(".pic.o")]
        pick = (non_pic or cands)
        if len(pick) > 1:
            fail("%s: %s compiles several sources named %s: %s" % (
                ctx.label, ctx.attr.lib.label, _stem(out.basename), [c.short_path for c in pick]))
        ctx.actions.symlink(output = out, target_file = pick[0])
        outs.append(out)
    return [DefaultInfo(files = depset(outs))]

cc_object_files = rule(
    implementation = _impl,
    attrs = {
        "lib": attr.label(mandatory = True, providers = [CcInfo], doc = "the target whose objects these are"),
        "objects": attr.output_list(mandatory = True, doc = "the object paths a recipe names, matched by source stem"),
    },
    doc = "Declared files for the objects of a cc target, at the paths a recipe reads them from.",
)
