# report — 2026-10-08

*(updated as the run proceeds; verdict at the end)*

## State at run start
PARITY build=GREEN diff=NOT converged errors=6 warnings=16 artifacts=converged
0 errors (the release baseline). IDIOM score=19.9 (threshold 23.0).
HERMETIC OK (carried), BOOT-SSH OK (carried, re-checked at the end).

## What landed

- **W2a — the global include path became a toolchain feature**
  (`kernel_compile_flags`): the supply include line is spelled once, by the
  toolchain, from `include_dirs` built in Starlark; a requesting target's
  BUILD carries `features = ["kernel_compile_flags"]` and its TU argv is
  byte-identical to the reference's. Deviating targets spell their whole
  line. Emitter commit d392e8b on kbuild-intree.
- **W2b — one package per Kbuild directory, across the whole tree**
  (`package_dirs` in conventions, generic). Rules route to the package of
  the nearest designated directory containing their declared outputs (or,
  with none, their read sources); reads of another package's file re-spell
  to that file's own label there (source files are exported, generated ones
  ride the producer); recipes keep their reference text.
  The designation is derived from Kbuild evidence — the 2,677 directories
  whose `Makefile` names build targets (`obj-`, `targets +=`, `*-y :=`) —
  one Bazel package per Kbuild directory, exactly as the owner asked.
  Four generic fixes the growth exposed (tool commit 8b08627):
  a path re-spells plain only when no package boundary sits between the
  rule's package and the file; headers carriers exist for every designated
  dir holding a header and chain from the root carrier (glob stops at
  package boundaries); tree_recipe staging skips a copy whose source is
  already at its destination (`cp src src` refuses).
- Whole tree: `bazel build //... --keep_going` GREEN, **2,322 BUILD files**
  (one per Kbuild directory plus export-only ones), root BUILD down from
  ~68k to ~22k lines. Parity: build GREEN, diff profile identical to the
  accepted release baseline (defines_diff x7, extra_tu x5,
  generated_content_diff x4 — same four files, same classes), artifacts
  converged 0 errors. **IDIOM score 19.9 → 5.2** (rules 3,125, tus 1,243,
  dirs 119): packages ≈ source dirs now, todo/include-flag/repeated-flag
  terms near zero; the 5.0 remaining is the 21 TODO-tagged host tools.
- Clean regression: re-emit WITHOUT `package_dirs` is byte-IDENTICAL
  (BUILD and CONFIG) against the committed layer content; INVARIANTS OK
  (suites green, vocabulary clean, corpus 37 converged before/37 after).
- **Clean regression, final tool state — the subcmd splits dissolve**: the
  byte-identity test against the just-installed layer FAILED in a good
  way. The strip of Kbuild's depfile bookkeeping had been applied to the
  capture model *after* that layer's emit (the model was re-extracted for
  the parity re-run); the only per-target change is `subcmd`'s 7 TUs each
  losing their leading `-Wp,-MT,<its own .o>` token — which was the ONLY
  per-source flag difference in `tools/lib/subcmd`. With it stripped, all
  7 TUs have identical argv, so the emitter emits ONE `subcmd` with all 7
  srcs instead of 6 per-source `cc_library`s (`subcmd_help`,
  `subcmd_pager`, …) and their 6 TODO review notes — splits that existed
  purely as depfile artifacts (root BUILD 24,478 → 24,105 lines). The
  other diffs are 8 inert re-orderings of header-only deps. Installed the
  re-emit (`/tmp/all-emit13`) so the pairing is clean again — layer ==
  committed tool + current capture model — and re-ran the full gate:
  build GREEN (51 actions re-run, the 7 subcmd TUs and dependents),
  **PARITY build=GREEN diff=NOT converged errors=6 warnings=15,
  artifacts=converged 0 errors** (the accepted baseline profile), **IDIOM
  5.2** (rules 3,125, tus 1,243, dirs 119 — 6 fewer rules), INVARIANTS OK
  (corpus 37/37), image rebuilt with byte-identical sizes (host-tool-only
  change), **BOOT-SSH OK after 3s: Linux 7.2.0**; hermetic below.
- **W5 — layer scrub** (tool commit 21a3c8c): per-BUILD provenance listing
  (each package lists its own targets, the root only the root-staying
  ones); gen-carrier rule names now come from the generated file's common
  directory (numbered only on collision), replacing the
  `pkg_generated_under_arch_x86__include_generated_2`-class names; the
  stray `KERNEL_DIR` make-variable bookkeeping removed everywhere; note
  and comment texts rebased from build-tree to workspace spelling.
- **W5 — zero `/scratch` in the emitted tree**: Kbuild's depfile
  bookkeeping (`-Wp,-MMD,`/`-Wp,-MT,`/`-Wp,-MQ,` and `-MD/-MMD/-MF/-MT/-MQ`)
  is stripped generically in the capture/BUILD emit and the aquery extract
  (Bazel adds and owns the depfile itself, so the tokens carry no
  information); note/comment paths re-spelled to workspace-or-build-tree
  names. The whole emitted layer now has **no absolute host path anywhere**
  (verified by grep).
- **W3 — the kernel library macro** (owner item 2): the
  `cc_per_source_library` rule gained `kbuild` ("built-in" | "module" | a
  module name) and `kbuild_modules` ({module: member sources}); the rule
  computes the per-source `KBUILD_*` defines from the source's path and
  the module arithmetic (Kbuild mangles `-`→`_` in object names but keeps
  the file path), and the emitter classifies the explicit maps at routing
  time — reducing 72 of 78 per-source maps to the attrs, keeping only what
  the arithmetic cannot express (an extra `-f`, a deviating define).
  Suites: emit_build 92/92, extract_capture 180/180.
- **Acceptance re-run on the new layer**: `bazel build //... --keep_going`
  GREEN (3,106 targets); the Bazel-layer bzImage built
  (`//arch/x86/boot:bzImage` — the target moved out of the root package
  with its directory, so project.env's `BZIMAGE_TARGET` moved with it),
  **BOOT-SSH OK after 3s: Linux 7.2.0** (QEMU/KVM, serial console, SSH
  login proven). Parity on the fresh capture model (re-extracted with the
  updated extractor so both sides strip the same tokens): **build GREEN,
  errors=6 warnings=15** (generated_content_diff x4, defines_diff
  warnings — the same accepted classes as the release baseline),
  **artifacts converged 0 errors**. IDIOM 5.3 (rules 3,131, tus 1,249,
  dirs 119). INVARIANTS OK (suites green, vocabulary clean, corpus 37
  converged before/37 after). Tool commit 8049f8f on kbuild-intree.

## Journal
journal.md holds the running log, including the cross-package traps the
whole-tree growth exposed (each fixed generically in the emitter, never
special-cased for this project).

## Results

- Owner items: (1) packages that follow the source tree — **done** (2,322
  BUILD files, one per Kbuild directory, whole-tree parity green); (2) the
  kernel library macro with `srcs` + directory extras and computed
  per-source defines — **done** (72 of 78 per-source maps became
  `kbuild`/`kbuild_modules` attrs; the global include line moved into the
  toolchain feature); (3) purpose-built rules replacing tree_recipe —
  **not started** (see below); (4) scrub — **done** for this run's scope
  (no `/scratch` anywhere, provenance per package, carrier names from the
  reached directory, no `KERNEL_DIR`); (5) parity as the guard rail —
  **held** (the accepted baseline profile, artifacts converged).
- Numbers: PARITY build=GREEN, diff errors=6 warnings=15 (all
  generated_content_diff x4 + defines warning classes of the accepted
  release baseline), artifacts converged 0 errors; **IDIOM 19.9 → 5.2**
  (threshold 23.0; rules 3,125, tus 1,243, dirs 119 — the remainder is the
  ~94 review-tagged split notes and the 21 host tools). Image built;
  **boot-ssh OK, Linux 7.2.0 up and SSH-provable in 3s**;
  INVARIANTS OK (37/37 corpus). **HERMETIC OK**: `//bazel/image:image`
  builds in a throwaway ubuntu-24.04 runner container with nothing from
  this host but bazelisk and the runner's apt set — on the final layer the
  fresh actions were the 51 the subcmd change touched (the hermetic disk
  cache from this run's earlier full pass, built hermetically, covers the
  rest); the toolchain's computed include declarations work in the
  container too.

## What remains (the next run's list)

- **Purpose-built rules** (owner item 3). tree_recipe still carries 93
  instances (34 in arch/x86 — the asm-offsets/offsets recipes and their
  env plumbing, 22 in root — auto_conf, the module headers carriers).
  The recurring kinds are exactly the owner's list: the .lds.S
  preprocessing (also clears the three "link flag names a file outside
  the package" notes), objcopy to .bin, the vdso image link, modules.builtin,
  the kconfig step (the root `auto_conf`). Each needs its own rule +
  emitter recognition + a parity-green cycle; none is a same-session
  change.
- **flex/bison for lexer.lex.c/parser.tab.c** (scrub item): the files are
  committed from the reference's content because the capture does not
  record what wrote them — but converting them to rules_flex/rules_bison
  drags a **runner dependency** along: the GitHub runner's apt set (and
  HERMETIC_APT) does not include flex/bison, and the committed files are
  why the hermetic build passes without them. First step is deciding the
  runner contract (add flex/bison to the workflow's apt set + pin versions
  that reproduce the reference's bytes), then the emitter can model the
  generators.
- **tree_recipe loads polish**: per-package BUILD files carry the union of
  load lines; emitting only the used ones is a small emitter fix.
- **emitter strictness**: fail (not silently fall back) when conventions'
  toolchain_probe is missing.
- The `bzImage` rule/file name collision (warning in arch/x86/boot) and
  the remaining `(review)`-tagged split notes in the root header are
  emitter text/wording work.

## Verdict
publish: release. `main` = upstream v7.2 + the one layer commit; the layer
builds green, parity holds at the accepted baseline profile with artifacts
converged, the image boots and is SSH-provable (Linux 7.2.0, 3s), the
build is hermetic in a clean runner container, invariants OK (corpus
37/37), and the installed layer IS the committed tool's emit (`kbuild-intree`
HEAD 8049f8f) against the current capture model — checked by re-emitting
from committed HEAD and diffing (the two documented classes above, both
the strip doing its job, then installed and re-gated).
