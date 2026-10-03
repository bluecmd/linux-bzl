# journal — manual-2026-10-03

Run brief: main = v7.2 + one Bazel-layer commit at parity; tool changes go in
any2bazel worktree `wt-kernel` (branch kbuild-intree), merge only with suites
green. PARITY at start: build=RED diff=NOT converged errors=13 warnings=8.

## Findings so far

Root-caused the three red genrules (`vmlinux_symvers`, `vdso64_image_c`,
`tmp_vmlinux_nm_sort`) to a chain of modeling gaps in the extractor, all
one theme: *the vmlinux link chain's intermediates are invisible to the
model*.

1. **objtool is entirely absent from the model** (root cause found this
   session, deeper than the smoke-dry journal's account). Kbuild's tools
   subtree builds with cwd in the *source* tree
   (`make O=<ref> -C objtool` runs at `<src>/tools/objtool`), and
   `_extract`'s main loop drops every exec whose cwd is not under the
   build root (`if not in_build(e.cwd): continue`). So the objtool compiles,
   the `ld -r -o objtool-in.o` partial link, `libsubcmd.a`, and the
   `objtool` executable never reach the model — yet kernel recipe lines
   run `./tools/objtool/objtool` constantly. Same for `tools/build/fixdep`
   and `tools/lib/subcmd` (~212 build execs total under `<src>/tools`).
   Fix: for VPATH builds, map the exec cwd through the source→build
   overlay before the `in_build` test. The compiles are otherwise
   well-formed (source in the workspace, object in the build dir).
2. `vmlinux.o` IS parsed by `link_action` (`ld.lld -r -o vmlinux.o
   --whole-archive vmlinux.a`, exec 3302871) but lands in the `partial`
   dict and is dropped at emission — no target, so modpost's genrule gets
   no srcs and never writes `.vmlinux.export.c` (the declared-output
   error). objtool rewrites `vmlinux.o` in place *inside the same recipe
   line* (FileTrace chain: [objtool]) — so the faithful unit is the whole
   recipe line (ld + objtool), i.e. a `recipe_line_action` genrule, with
   the `--whole-archive vmlinux.a` operand recovered from the ld argv
   (linker file I/O is unrecorded by design).
3. `vmlinux.a` = `cat built-in-fixup.a > vmlinux.a` (recipe line,
   exec 3302867/68). Its consumer (the LD line's argv) names it, but
   `FileTrace.useful()` hard-gates on `_is_mechanics()` (`.a`), so the cat
   line is never modeled. Fix: let a mechanics-shaped chain file through
   when a modeled or modelable action consumes it (modpost reads
   `vmlinux.o`; the LD line's argv names `vmlinux.a`).
4. `.vmlinux.export.o` (compile of modpost's `.vmlinux.export.c`) and
   `init/version-timestamp.o` are compiles that link-vmlinux.sh's
   `ld.lld ... -o vmlinux.unstripped` consumes by argv. They sit in the
   extractor's `<unlinked>` pile and are not emitted. Their producer
   evidence is fine (argv + trace); what is missing is (a) the extract-side
   promotion of "compiles consumed as files" and (b) emitter wiring.
5. `link-vmlinux.sh`'s modeled genrule has only 9 inputs: the traced reads
   of the script subtree exclude every file the *linker* under it consumes
   (`vmlinux.o`, `.vmlinux.export.o`, `version-timestamp.o`,
   `vmlinux.lds`). Generic fix: a generator's inputs must also include the
   file-naming argv tokens of the programs it runs (linkers/binutils: I/O
   in argv, not in the trace).
6. Stripped `vdso64.so` = `llvm-objcopy -S --remove-section __ex_table
   vdso64.so.dbg vdso64.so` in its own recipe line (exec 10076), unmodeled
   for the same mechanics-gate reason; vdso2c reads both `.so.dbg` and
   `.so` — need to confirm vdso2c's modeled inputs already carry both.
7. Emitter-side wiring (all three genrules): genrule inputs naming files
   produced by (a) another genrule — already works via `gen_outs_all`;
   (b) a cc target's artifact (`built-in-fixup.a`, `libsubcmd.a`,
   `vdso64.so.dbg`) — dropped by the leak filter today. For (b): a
   `cc_static_library` realization gives a *file*-producing archive
   (probe `//a2bprobe:combo` on the layer tree answered this: aquery
   shows mnemonic `CppTransitiveArchive`, `llvm-ar rcsD
   libcombo.a <objs>`); for raw-link outputs register output-file → label
   + stage-to-logical-path, the same way `output_labels` does for
   executable links. Probe files `a2bprobe/` must be deleted before
   publish.

## Iteration log

- Re-extraction baseline (`/tmp/model.base.json`, current wt-kernel
  fd79d5e): 569 targets, 104 codegen; matches stored model modulo the
  dropped VPATH `source` layout link (current tool behavior, intended).
- Emitter re-emit byte-identical to layer BUILD.bazel except 2 stale TODO
  lines — iteration loop (edit wt-kernel → extract → emit → parity with
  `A2B_SCRIPTS=wt-kernel/scripts`) is reproducible, ~40 s + emit + build.
- Link-action census (patched run): 18 links — 12 host tools, realmode.elf,
  vdso64.so.dbg (shared), vmlinux.o (object, dropped), vmlinux.unstripped,
  compressed vmlinux, setup.elf. `tools/objtool`'s link never reaches
  `link_action` (cwd filter).

## Toolchain resolution semantics (probed with a2bprobe2/)

- Target-config cc targets get the *kernel* cc toolchain
  (`bazel/rules/kernel_llvm_toolchain.bzl`), whose every compile bakes the
  probe's KERNEL_COPTS (`-nostdinc -include include/linux/kconfig.h ...`).
- Exec-config targets (host tools placed under a genrule's `tools` attr) get
  `toolchains_llvm` — clean host flags, no kernel includes.
- Therefore any host-side library built for a host tool must carry
  `tags = ["manual"]`: untagged, `//...` also builds its *target-config*
  copy with the kernel toolchain and every TU dies on
  `'generated/autoconf.h' file not found` (the subcmd failure).
- v9 build: 11 ERROR lines, 4 root causes, all fixed in emit_build.py:
  1. `vmlinux_a` genrule had no srcs (`cat built-in-fixup.a` unstaged) —
     CppArchive outputs of model targets now register in `output_labels`
     (label + stage-to-logical-path), the same mechanism executable
     raw-links use.
  2. `vdso64_so` cycle: pkg_generated's textual_hdrs carried generated TU
     sources (vdso64-image.c), dragging every headers consumer into the
     generators' chain. Fixed by `wired_gen`: generated TU sources that are
     a cc target's srcs (or a compile output) are wired by those srcs and
     excluded from gen libs.
  3. subcmd/7 compiles failing on kernel forced includes: host-linked
     libraries now get `tags = ["manual"]` (`host_linked_labels`, via
     `_host_tool_archive_deps` — 21 rules tagged in v10).
  4. objtool `'inat-tables.c' file not found`: `_included_names`'s
     transitive walk followed headers only. Extended its `by_base` with the
     package's own TU sources (os.walk, `_pkg_tu_cache`), so the walk
     follows decode.c → `#include "../../../arch/x86/lib/inat.c"` →
     inat-tables.c; objtool_textual now lists it.
- v10→v11: 2 remaining cycles (realmode_relocs, vmlinux_gen) + the -m16
  families. `_reachable_generated` now intersects root-reach with an
  include-name walk (`-Iarch/x86/boot` sits on realmode.elf's line but only
  header.S reads zoffset.h — pulling the whole root tied the boot image's
  vmlinux into the realmode chain, a cycle), and the toolchain's forced
  includes seed the walk (`-include kconfig.h` → generated/autoconf.h fixes
  usr/scripts_mod_empty's undeclared inclusion).
- v12: 38402 ERROR lines — `disabled_features` does not exist on the
  rules_cc+ bzl cc rules (Bazel 9.2 has removed the native cc rules that
  used to accept it). Established the feature-inversion regime instead:
  the toolchain's `kernel_compile_flags` feature is `enabled = False`
  (bazel/rules/kernel_cc_toolchain_config.bzl) and non-deviating targets
  request it via the `features` attr (Bazel core injects `features` into
  every rule; rules_cc+ accepts it); deviating targets (-m16 realmode /
  boot / vDSO families, whose argv lacks part of the baked line) omit it
  and spell their full reference line in copts. New conventions field
  `toolchain_features: ["kernel_compile_flags"]`; emitter helpers
  `_deviates` (argv lacks a supply token) and `_copts(keep_supply=)`.
- v13: 5 ERROR lines, 3 groups — (a) groups cc_library rules lacked
  `additional_compiler_inputs` for `.incbin`ed files (rmpiggy.S →
  realmode.bin/relocs); (b) `vmlinux_a`'s genrule consumed the sourceless
  `built_in_fixup` cc_library — `gen_archived` now emits it as
  `cc_static_library` (rules_cc+, CppTransitiveArchive, llvm-ar rcsD — a
  real .a file for `$(location)`); (c) `vdso64_so`'s raw link mangled:
  root cause in the EXTRACTOR, not the emitter —
  1. `_resolve_argv`'s `_JOINED_PATH_FLAGS` contains `-B`, so the linker
     flag `-Bsymbolic` had its value path-ified into
     `-B<ref>/symbolic` (gcc's `-B dir` is a path; ld's `-Bsymbolic` is
     not). Fixed: `-B` joined values are resolved only when
     `_looks_like_path(val)`; otherwise the token stays verbatim.
  2. `link_action` did not pair `-soname` with its operand, so
     `linux-vdso.so.1` was classed a library input (split_library_name
     matches `.so.1`) and the option orphaned; the emitter's soname
     parser then ate the next flag (`-z`) and `max-page-size=4096` was
     left a bare ld operand. Fixed: `-soname` joins the paired-flags set,
     the value stays a flag token.
  After both: the model's vdso64 CppLink argv matches the capture token
  for token (`-Bsymbolic`, `-soname linux-vdso.so.1`, `-z
  max-page-size=4096` all intact).
- Extraction invocation gotcha (cost one bad emit): the loop's command is
  `extract_capture.py CAP WS out.json --build-dir $ROOT/ref
  --source-dir $ROOT/src-ref --project-root . --report`. Running it with
  `--source-dir $ROOT/ref` silently produces a mangled model (mixed
  src-ref/ref paths, codegen 114→111, all cc groups dropped). Always copy
  the invocation from loop.sh.
- v14: emitted from the fixed extractor's model with (a) and (b) applied;
  build in flight.
