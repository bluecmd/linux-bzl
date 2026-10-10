# journal — 2026-10-08

## 00:00 wave 1 (tool: b376101)
- build_lint: a target that spells its own regime (`features` does not
  request the toolchain's `kernel_compile_flags`) is not counted as a
  toolchain-flag repeat; linkopts count on any cc rule (they land on the
  consumer's link action). idiom: a host tool that is a Bazel label is
  hermetic (bc → @bc//:bc).
- INVARIANTS OK, corpus 37/37, committed b376101.
- Baseline re-proven on the wave-1 tool (runs/2026-10-08/parity-wave1.txt):
  PARITY build=GREEN diff=NOT converged errors=6 warnings=16,
  artifacts converged, IDIOM 20.2 (was 23.0). 35 s per parity round.

## 00:40– recon for the packages wave (owner item 1)
- Probed Bazel 9.2 make-variable semantics: `$(GENDIR)`/`$(BINDIR)` expand
  in any rule context to the bin root (package-free); custom-rule
  declare_file outs are package-scoped, so a routed rule keeps its execroot
  path if the out is re-spelled package-relative.
- Established the routing rule: a rule goes to package P only when all its
  path spellings are within P; everything else stays in the root package.
  The differ reads aquery only, so BUILD layout is parity-invisible as long
  as (a) rule names survive, (b) declared outputs land at the same execroot
  paths, (c) executed argv is unchanged.

## 01:00– probe: can the toolchain feature carry the include line?
Finding (owner item 2, "the global include path moves to the toolchain
feature"): today 222 targets spell the same 13 `-I` copts (7 source-tree
roots + 5 `$(GENDIR)` twins) — 2,664 copt entries.
- Bazel 9.2 toolchain feature flags do NOT expand `$(GENDIR)` (probe: the
  literal landed in aquery argv).
- `%{user_include_paths}`/`%{include_paths}`-style build variables do not
  exist for CppCompile in this toolchain (probe: iterate_over on an unknown
  variable crashes the aquery aspect evaluation; `%{source_file}` works).
- BUT the kernel_cc_toolchain_config rule CAN build the flag strings in
  Starlark: `ctx.bin_dir.path` of the toolchain config rule is the target
  configuration's bin root (`bazel-out/k8-fastbuild/bin`). Probe: feature
  flag `-I` + ctx.bin_dir.path + `/arch/x86/include/generated` lands
  expanded in aquery argv.
- The differ compares include ROOTS (presence, order-insensitive), and
  `-I` tokens are excluded from the flags set — so roots spelled from the
  toolchain instead of copts are parity-invisible.
Plan: probe_kernel.py learns the src-tree vs build-tree distinction from
the reference argv (build-relative spellings whose content is generated),
kernel_flags.bzl gains KERNEL_GENFILE_ROOTS, kernel_cc_toolchain_config
gains `include_dirs`/`genfile_dirs`, the feature spells both forms, and the
emitter stops spelling those roots in copts for targets that request the
feature (conventions: include_roots kind "toolchain_feature"). Deviating
targets (own regime, no feature) keep spelling their whole line.

## in progress
- Re-emit command reconstructed and being verified byte-identical against
  the committed BUILD.bazel.

## 02:10– W2a: the include line moves into the toolchain feature
Design settled on the evidence above, one simplification: no src/gen
classification is needed. `kernel_cc_toolchain_config` gains `include_dirs`
(the 7 workspace-relative roots from `KERNEL_INCLUDE_ROOTS`) and the
`kernel_compile_flags` feature spells `-I<d>` and `-I<bin_dir>/<d>` for each
(ctx.bin_dir.path — proven to land expanded in argv). Interleaved order keeps
every existing dir's relative search order; the two extra bin twins
(`bin/arch/x86/include/uapi`, `bin/include/uapi`) name dirs nothing
generates (the reference spells no outs under them) — the compiler skips a
nonexistent -I dir, and the differ tolerates extra bazel include roots.
Consequence: the capture's `codegen` list DOES record generated outputs
(`include/generated/autoconf.h`, `arch/x86/include/generated/...`) —
probe_kernel.py never needed a src/gen heuristic; KERNEL_INCLUDE_ROOTS was
already the right symbol.
- probe_toolchain.py: `--cc-feature NAME` (repeatable) requests features on
  the three probe targets (a feature off by default is on the argv only when
  a target asks — which is how the emitter spells it), and `_compile_view`
  records every -I root (previously relative ones were dropped — the probe
  targets carry no copts, so every -I is the toolchain's).
- Re-probe: compile.flags still 93; include_roots now the 14 kernel spellings
  plus Bazel's own per-compile roots (`.` and the bin root, the repo roots —
  all relative, previously invisible). No reference -I collides with them
  (checked all 3,900 -I tokens of the capture).
- emit_build.py: the supply include-root drop is gated on `not keep_supply`
  (a deviating target spells its whole line) AND `not keep_includes`;
  `_render_host_tools` passes keep_includes=True — host tools compile on the
  exec platform with a toolchain the probed supply does not describe, and
  they DO spell supply roots (`relocs`, `vdso2c` spell -Iinclude/uapi).
- Layer: MODULE.bazel gains include_roots_symbol = "KERNEL_INCLUDE_ROOTS";
  bazel/rules/{kernel_cc_toolchain_config,kernel_llvm_toolchain}.bzl synced
  from the tool (the tool's stale copy — enabled=True, no comment — is
  reconciled with the layer's).
- Starlark gotcha: implicit string concatenation across lines is forbidden.

## 03:15– W2a landed and committed (tool d392e8b)
- New emit_build test `test_feature_spelled_include_roots_are_supply`: a
  requesting target drops the feature's roots from copts and carries
  `features`; a deviating target keeps them spelled and carries no
  `features`; a root the feature does not spell stays the package's.
  Suites 87/87 + 7/7, INVARIANTS OK, corpus 37/37 (before the test was
  added; the test does not touch emitter logic — check-invariants suites
  re-run green after).
- parity-w2a.txt: build=GREEN, diff=NOT converged, 6 errors/16 warnings
  (identical to the wave-1 baseline), artifacts converged, IDIOM 19.9.
- Committed d392e8b (probe_toolchain --cc-feature + full -I recording,
  emit_build supply include-root drop, kernel_cc_toolchain_config
  include_dirs, kernel_llvm_toolchain include_roots_symbol, tests).
- Detritus: the worktree has an untracked toolchain/ dir from a probe run
  (not committed, left alone).

## 03:30– W2b recon: per-directory packages (owner item 1)
Why the differ tolerates the move (aquery-only, keyed by on-disk basename):
- outs spelled `arch/x86/realmode/rm/realmode.bin` from the root package land
  at the same execroot path as `realmode.bin` spelled from package
  `arch/x86/realmode/rm` — the path survives the move un-normalized.
- tree_recipe runs the recipe verbatim from its mirrored cwd with cwd-relative
  paths — routing does not touch recipe text or env_map.
- cc_library srcs are execroot-relative in aquery argv regardless of package.
- The literal routing rule (owner's): a rule goes to package P only when all
  its path spellings are within P — so a moved rule never re-spells a file in
  another package; only dep labels rewrite (`:name` -> `//:name` / `//Q:name`).
Trial subtrees (scan of the emitted BUILD): arch/x86/realmode 9 rules movable,
arch/x86/boot 16 (cc_binary mkpiggy, ar_archive, tree_recipes bzImage/
cpustr_h/piggy_S/gdt_idt_pi_o/map_kernel_pi_o, cc_per_source_library
setup.elf_objs + compressed_vmlinux_objs, cc_libraries startup_*, lib,
cc_raw_link setup.elf / compressed_vmlinux).
Design (generic, conventions-gated `package_dirs`): Rule.pkg set in a
post-plan routing pass; spellings normalized to execroot paths (strip the
bazel-out bin prefix) then to package-relative; dep labels rewritten through a
name->package map; per-package hdrs libraries; a cc target deps its own
package's hdr lib plus the hdr lib of every package dir its `-I` roots name;
per-package loads/assigns/recipe-env/package stmt; sub-BUILD files written
next to the root BUILD. Header/generation libraries whose spellings span dirs
stay in the root package.

## 04:20– W2b implementation: the routing pass
- The routing rule, refined against what Bazel refuses (a rule in package P
  cannot spell a file of a subpackage of P's parent, and cannot declare an
  out outside P): a rule routes to P when every file it DECLARES (its
  outs) lies in P and every SOURCE file it reads lies in P (or in no
  designated package); GENERATED reads may come from anywhere -- they are
  re-spelled to the label of the rule that produces them (`//Q:<rule>`),
  and from P a file outside P that nothing produces is spelled as its
  absolute file label `//:<path>` (legal while the path is in no package in
  between). Out-anchored routing also untangles the cwd="." recipes: a
  tree_recipe whose outs lie in P routes to P, and its MIRROR stays under
  the bin root (tree_recipe.bzl now takes `ctx.bin_dir.path` with the
  package suffix taken back off -- the recipe's workspace-relative paths,
  the stage/refresh dests and the `.a2b-bin` tool dir keep their execroot
  paths whatever package the rule lives in; the old `+ pkg` append was a
  latent subpackage bug anyway).
- The generated universe (every declared out, pre-routing) decides what
  may leave a package; a generated read under ANOTHER designated dir after
  routing would be unspellable, so the rule is refused (stays root) --
  surfaced, as the emitter always does.
- `stage_dests`/`refresh_dests`/`out_dirs` are execroot-relative and leave
  the respell set; `stage`/`refresh`/`hdrs`/`textual_hdrs`/`objects` join
  it. `out` (string attr: ar_archive's 553 `out = "arch/.../built-in.a"`)
  respells too.
- The differ's `target_map`/`dep_map` label values follow the rule that
  moved (`:name` -> `pkg:name`, the `_pkg_label` spelling).
- Tests: a routed genrule (srcs/outs/cmd re-based, written to sub/BUILD.bazel
  by the emitter next to the root BUILD), a consumer reaching the generated
  header through `//sub:names_h` (the root `pkg_generated` carrier re-spells,
  cross-package labels are legal), a read from another designated dir
  refuses, a routed executable and its `target_map` value, determinism.
  90/90; the other suites green.
- Regression gate: re-emit with the committed conventions (no
  package_dirs) must be byte-identical to the layer BUILD.bazel + config --
  IDENTICAL + CONFIG-IDENTICAL (re-proven with the final routing code).

## 05:20– W2b: two respell bugs the trial sub-BUILDs exposed
- `_respell_rule` respelled EVERY string-list attr, so the recipe-rule
  attrs that name WRAPPERS not files (`exports` = make-variable names,
  `cc_wrappers`, `bin_wrappers`, `beside_wrappers`, `path_tools`,
  `stage_dests`/`refresh_dests`/`tool_words`/`export_env`) were mangled
  into `//:` labels (`"CC"` -> `"//:CC"`). The respell now runs only on
  the file-naming attrs (`_LABEL_ATTRS`) plus `out`, `per_source_copts`
  keys and the `$(location ...)` occurrences in `cmd`/`recipe`/`args`.
- The per-package headers libraries the routing pass creates carry
  already-package-relative values (their `textual_hdrs` was stripped at
  creation); the respell loop re-read them as workspace-relative and
  re-spelled the stripped entries to `//:` file labels. Created libs are
  now marked final and skipped by the respell.
- Suites 90/90 + all others green after the fixes.



## 06:20– W2b fixes A/B/C (the three parity blockers)
- A: `deps` joined `_LABEL_ATTRS` -- a routed rule's `:pkg_generated_*` dep
  of a producer that moved respells to `//pkg:pkg_generated_*` (the
  `//arch/x86/boot:pkg_... does not exist` analysis errors).
- B: cross-package SOURCE-file reads are collected during `_respell` (the
  `//:` fallback and the innermost-designated branch) into
  `_cross_files[owning_pkg]`, and every BUILD text -- root and sub --
  carries `exports_files([...])` of them (sorted; text omitted entirely
  when empty, so the no-routing emit is unchanged). The layer's `xz_wrap.sh`
  and root-header file labels resolve again.
- C: `tree_recipe.bzl` pairs `stage`/`stage_tools`/`refresh` with their
  dests BY DESTINATION, not by position (`_pair_by_dest`): a cross-package
  label may name a rule with several outputs (auto_conf: auto.conf +
  autoconf.h), widening ctx.files; position then pairs the wrong file and
  auto.conf overwrites autoconf.h (CONFIG_X86_64 undefined ->
  page_32_types.h not found). A plain file list still pairs by path in
  order, identical to the old zip; command stays byte-identical.
- Suites green after A+B+C (emit 91/91; stderr-only usage/warning prints
  of the other suites are expected, all rc=0 and passed-lines green).
- Regression emit (no package_dirs) + routed trial emit re-running; the
  clean one must stay IDENTICAL + CONFIG-IDENTICAL against the layer
  commit 407c87720.
- Parity GREEN with the final W2b code: errors=6 warnings=16, classes
  identical to the w2a release baseline; artifacts converged 0 errors;
  IDIOM 19.6 (rules 1132, tus 1243, dirs 119). Clean regression emit
  (no package_dirs) IDENTICAL + CONFIG-IDENTICAL. INVARIANTS OK (suites,
  vocabulary, corpus 37/37). Tool commit 56b90e5 on kbuild-intree.

## 06:40– whole-tree derivation corrected: dirs the build WRITES to
The first whole-tree list (560 dirs holding a `*.a`) missed every Kbuild dir
that produces an image or a generated header instead of a library — exactly
arch/x86/boot (voffset.h, setup.bin), boot/compressed (piggy.S), realmode/rm
(realmode.bin), so their rules stayed in root while consumers re-spelled to
`//arch/x86:boot/...`. Two consequences found in build #3 (2138 raw errors,
267 distinct): labels into dirs the emitter never routed, and stale trial
BUILD files (boot, boot/compressed, rm) left in the layer by the earlier
install, which made those dirs phantom subpackages ("no such target
//arch/x86/realmode:rm/header.S", "Label ... is invalid because ... is a
subpackage").
New derivation, evidence-based: the 567 directories the reference build
writes at least one output into (model.capture.json outputs). boot,
boot/compressed, realmode/rm, kernel are all in it. Rebuilt
/tmp/conv-kbuild.json from it; /tmp/install-emit.sh now deletes EVERY
BUILD.bazel outside bazel/ before installing (the emitter owns all of them).
Re-emitting fresh into /tmp/all-emit2 (557 BUILD files expected, root ~22k
lines).

## 06:50– whole tree builds green: one package per Kbuild directory
Iterations after the corrected derivation (dirs the build writes to → dirs
whose Makefile has kbuild targets, 2677 dirs):
- `_respell`'s plain-path branch ignored a package boundary between the
  rule's package and the file (syscalls_64.tbl read from arch/x86 while
  arch/x86/entry is a package) → the branch now takes a path only when no
  designated dir sits strictly between pkg and the file; otherwise the
  innermost-designated-ancestor branch spells the subpackage's file label.
- install wiped handwritten infra (platforms/BUILD.bazel, toolchain/BUILD.bazel
  are tracked layer files, not emitter-owned) → install keeps bazel/,
  platforms/, toolchain/.
- the root headers carrier's glob stops at every subpackage, so generated
  headers under a package (arch/x86/include/generated) and quoted includes
  across a boundary (power/power.h) vanished from the sandbox → carriers
  now exist for every designated dir that holds a header (workspace scan,
  `_HDR_GLOB_EXTS`) or that a routed rule needs, and the root carrier
  depends on each of them (hdrs close transitively through one dep).
- tree_recipe's dest-based staging paired a file with itself once the
  tool's own package declares it at the reference path (scripts/kconfig/conf
  = gendir/scripts/kconfig/conf): `cp src src` refuses → the staging skips
  a copy whose source is already at its destination.
Result: `bazel build //... --keep_going` GREEN, 0 errors — 2322 BUILD files
(one per Kbuild directory, plus export-only ones), the root BUILD down to
~22k lines of the tree-wide glue the root package owns. Parity gate
running.

## 07:10– W5 scrub, W3 the kernel library macro (tool 21a3c8c + uncommitted W3)
- Provenance: each BUILD lists its own targets; the root lists only the
  root-staying ones. Gen-carrier rule names from the file's common dir
  (numbered on collision). KERNEL_DIR bookkeeping removed. Note/comment
  paths re-spelled from build-tree (`ref/...`) or workspace spelling.
- Depfile bookkeeping stripped generically (capture, emit, extract):
  `-MF/-MT/-MQ/-MD/-MMD/-MP` and the `-Wp,-MMD,/`-Wp,-MD,`/`-Wp,-MT,`/
  -Wp,-MQ,` forms — Bazel adds and owns the depfile, the tokens carry no
  information. Result: zero `/scratch` anywhere in the emitted tree.
- W3: `kbuild`/`kbuild_modules` on cc_per_source_library compute the
  per-source KBUILD_* defines (built-in: MODFILE path minus ext + mangled
  names; module member: MODFILE `<pkg>/<module>`, MODNAME the module,
  BASENAME per source; module object step: only BASENAME); emitter
  classifies at routing time, keeps only what the arithmetic cannot
  express. 72/78 maps reduced; `kernel/sched`'s core.c keeps its
  `-fno-omit-frame-pointer`, lib string.c its `-ffreestanding`.
  Suites 92/92 + 180/180.
- Build #14: Starlark forbids implicit string concat in attr docs — `+`.
- Build #15: 6 errors "absolute path inclusion(s) found in rule" on the
  subcmd (objtool support) cc_libraries. Mechanism found by reading the
  depfile: with the `-Wp,-MT,` token gone Bazel *validates* the depfile;
  those host TUs (no `-nostdinc`) read `/usr/include` and the compiler's
  resource dir — none declared in `cxx_builtin_include_directories`
  (the probe-derived list is empty: kernel TUs need nothing). The exec
  toolchain passes because toolchains_llvm declares both.
  Attempts: `%workspace%/external/...` entries (rejected — clang spells
  the resource dir by its real path, not the execroot one); an in-repo
  `lib/clang` link (clang still resolves to the real path). Fix: the
  kernel_llvm_toolchain repo rule declares the resource dirs by the
  compiler's real path, derived at repository-rule time (`realpath` of
  the linked distribution's `lib/clang`), plus the system headers spelled
  as toolchains_llvm does — generated, nothing hand-written. `//:subcmd_pager`
  green; full tree building.

## 12:20– acceptance on the new layer: image, boot, hermetic all pass
- `//arch/x86/boot:bzImage` built (project.env's BZIMAGE_TARGET followed the
  target out of the root package — `//:bzImage` no longer exists, updated
  the env, the only project-env change of the run).
- BOOT-SSH OK after 3s: **Linux 7.2.0** (QEMU/KVM, serial console, SSH
  proven with the pinned key).
- HERMETIC OK: the image target builds in the throwaway ubuntu-24.04
  runner container (2,436 fresh actions; the kernel_llvm_toolchain's
  realpath-derived include declarations are computed inside the container
  and work — nothing machine-specific is committed).
- Parity re-run after re-extracting the capture model with the updated
  extractor (parity.sh reuses model.capture.json, so the extractor change
  needs the capture model rebuilt once — 10 tokens fewer, all
  `-Wp,-MT/-Wp,-MQ` depfile targets): **build GREEN, errors=6
  warnings=15, artifacts converged 0 errors** — the release baseline
  profile. IDIOM 5.3.
- Checked and deliberately NOT attempted: flex/bison for
  lexer.lex.c/parser.tab.c. The capture does not record the generators
  (the files are committed from the reference's content), and replacing
  them with rules_flex/rules_bison makes the build NEED flex+bison —
  the runner apt set does not have them and the committed files are why
  the hermetic build passes without. That is a runner-contract decision
  first; recorded in the report's next-run list.

## 12:45– clean regression: re-emit from committed tool HEAD (8049f8f)
The pre-launch check printed `conv-differs` between /tmp/conv-kbuild.json
(the conventions file that produced the verified emit) and the layer's
conventions.json — a semantic diff via jq shows they are IDENTICAL
(differing only in JSON formatting: minified vs pretty). So the re-emit
from committed HEAD with the layer conventions is a true byte-identity
test against /tmp/all-emit12. Result recorded below when it lands.

## 12:50– the re-emit found real drift: the subcmd splits dissolve
The byte-identity test FAILED — and the failure is a scrub win, not a
regression. Timeline: the verified emit (/tmp/all-emit12, installed) was
generated at 13:11 from the PRE-strip capture model; the capture model was
re-extracted at 14:11 with the depfile-strip extractor (for the parity
re-run); the tool was committed at 14:18. Re-emitting from committed HEAD
plus the re-extracted model (/tmp/all-emit13) differs from the installed
layer in exactly two classes, and a per-target diff of the two capture
models shows the ONLY model change is `subcmd`'s 7 actions each losing
their leading `-Wp,-MT,<its own .o>` token:
- `subcmd` was split into 6 per-source cc_libraries (subcmd_help,
  subcmd_pager, ... + 6 TODO review notes, ~373 lines of root BUILD)
  because the `-Wp,-MT` token was the only per-source flag difference.
  Strip it and all 7 TUs have identical argv, so the emitter emits ONE
  `subcmd` with all 7 srcs — the splits were pure depfile artifacts,
  dissolving is exactly the owner's scrub direction (root BUILD
  24,478 -> 24,105 lines).
- 8 inert re-orderings of `//arch/x86:x86_headers` vs
  `//scripts:scripts_headers` in deps lists (header-only deps; no action
  argv changes).
Decision: install /tmp/all-emit13 (EMIT=/tmp/all-emit13 bash
/tmp/install-emit.sh, then git checkout -- toolchain/BUILD.bazel
platforms/BUILD.bazel) so the pairing is clean again -- layer ==
committed tool + current capture model -- and re-run the full gate:
build, parity, IDIOM, invariants, image, boot-ssh, hermetic.

## 12:52–13:05– the full gate re-run on the emit13 layer — all green
- `bazel build //... --keep_going` GREEN (51 actions re-run: the 7 subcmd
  TUs and dependents; the rest action-cache hits).
- PARITY build=GREEN diff=NOT converged errors=6 warnings=15,
  artifacts=converged 0 errors — the accepted baseline profile, unchanged.
- IDIOM score=5.2 (rules 3,125, tus 1,243, genrules 1, dirs 119) — 6
  rules fewer than the previous 3,131 (the dissolved subcmd splits).
- INVARIANTS OK: suites green, vocabulary clean, corpus 37 converged
  before / 37 after.
- Image rebuilt: byte-identical sizes (bzImage 2,417,664, initrd
  2,623,909 — the change is host-tool-only). BOOT-SSH OK after 3s:
  Linux 7.2.0.
- Zero /scratch in the installed layer re-verified after the install.
- Hermetic re-run launched (13:05 UTC) on the emit13 layer; result
  recorded below.

## 13:05–13:15– hermetic green on the final layer; verdict
HERMETIC OK: //bazel/image:image builds in a clean runner container. The
51 fresh actions are the ones the subcmd change touched; the rest came
from this run's earlier hermetic disk cache pass (itself hermetic).
Report finalized: verdict `publish: release`. The pairing claim: the
installed layer IS the committed tool's emit against the current capture
model (verified by re-emit + diff + install + full re-gate).
Run ended with state/STOP at 13:15 UTC, inside the 15.4h budget.
