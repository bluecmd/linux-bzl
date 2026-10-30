"""One library of the kernel and the mechanics around it.

The reference built each kernel directory's built-in.a with its own ar
recipe -- `llvm-ar cDPrST built-in.a <objects in link order>` -- and
another recipe reads the objects back by path where it names them. The
library, that archive and the object reads are one call:

    kernel_library(
        name = "kernel_unwind_built_in",
        srcs = ["unwind/deferred.c", "unwind/user.c"],
        out = "unwind/built-in.a",
        op = "cDPrST",
        members = ["unwind/user.o", "unwind/deferred.o"],
        objects = ["unwind/deferred.o", "unwind/user.o"],
    )

The macro keeps the labels the rest of the build spells: the library is
`name`, the archive `name_a` (out at the reference's path, members in the
reference's order -- the link order), the objects a recipe reads
`name_objects`. A library whose sources carry flags or defines of their
own (KBUILD_*) compiles through the per-source library.
"""

load("@rules_cc//cc:defs.bzl", "cc_library")
load(":ar_archive.bzl", "ar_archive")
load(":cc_object_files.bzl", "cc_object_files")
load(":cc_per_source_library.bzl", "cc_per_source_library")

def kernel_library(
        name,
        srcs = [],
        copts = [],
        deps = [],
        features = [],
        kbuild = None,
        kbuild_modules = None,
        per_source_copts = None,
        additional_compiler_inputs = [],
        out = None,
        op = None,
        members = [],
        ar = None,
        objects = None):
    kw = {"name": name, "srcs": srcs, "copts": copts, "deps": deps,
          "features": features}
    per_source = False
    for k, v in (("kbuild", kbuild), ("kbuild_modules", kbuild_modules),
                 ("per_source_copts", per_source_copts),
                 ("additional_compiler_inputs", additional_compiler_inputs)):
        if v:
            kw[k] = v
            per_source = True
    if per_source:
        cc_per_source_library(**kw)
    else:
        cc_library(**kw)
    ar_archive(name = name + "_a", out = out, op = op, members = members,
               srcs = members, ar = ar)
    if objects != None:
        cc_object_files(name = name + "_objects", lib = ":" + name,
                        objects = objects)
