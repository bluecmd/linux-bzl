# journal — 2026-10-23

## 00:25 — start; boot=0 root-caused as a port collision

- Run-start parity (harness, parity-before.txt): GREEN / converged /
  errors=0 / warnings=14, IDIOM 0.3. Layer 82ca2c96c clean; wt-kernel
  6259752.
- build-image.sh kicked off (background) for the boot test.
- 2026-10-17's harness boot=0 root-caused: its boot.txt shows qemu dying
  on "Could not set up host forwarding rule 2222" — host port occupied,
  gate failed before the guest started. The run's own test had used 2223
  and passed. Nothing on 2222 now; no qemu-system running.
- Owner's scrub item from 2026-10-06 still open: root BUILD.bazel is
  20,345 lines with 3,837 comment lines before the first rule (the
  emitter prints the whole tree's name-mapping table + 135 review TODOs
  into the root package's BUILD). Mid-tree BUILD files are lean (2–3
  comment lines). Plan: fix in the emitter (generic), verify by re-emit
  + parity, keep the actionable notes.

## 00:35 — BOOT-SSH OK: the release state is intact

- `build-image.sh` (cache hits) + `boot-ssh-test.sh` on port 2226:
  **BOOT-SSH OK after 3s: Linux 7.2.0**. The boot gate passes on the
  current layer; the 2026-10-17 boot=0 was purely the harness's port 2222
  being held. qemu exited cleanly (trap killed it — no stale process).
- Root BUILD.bazel facts (for the header work): 20,345 lines = 3,837
  comment lines (provenance: the emitter's tree-wide name-mapping table
  ~3,530 lines + Notes + 135 TODOs), then 60 rules with ~16k lines of
  ld-order deps lists. The 60 rules are genuinely root's (vmlinux,
  .config machinery, offsets, tools); the rest of the tree lives in 120
  per-directory packages.
- Why the table is tree-wide: `emit_build.py` filtered the root header's
  mapping lines with `pkg_of.get(et.name) is None` — pkg_of only knows
  RULE names, and a target folded into pieces (arch_x86_built-in ->
  arch_x86_built_in_a ar_archive) never becomes a rule with its own
  name, so every folded target of the whole tree landed in the root's
  table. The table also names rules that do not exist ("-> cc_library
  arch_x86_built_in"): misleading, and the exact thing the owner's
  2026-10-06 scrub item called out.
- Fix (tool, wt-kernel, uncommitted): the root header lists the targets
  whose own rule it carries (`r.name == et.name and r.pkg is None`);
  Notes and review TODOs carry the package they were raised for
  (`_todo`/`_note` record the render context's package — the target's
  source directory when the conventions split it out) and render in
  that package's BUILD header; the root keeps the setup-phase ones.
  Suite: emit_build 126/126 (two new tests:
  test_header_mapping_lists_the_targets_the_file_holds,
  test_review_todos_render_beside_their_rule), all other suites green.
- emit45 re-emit running (background) to measure the real effect and
  diff against the layer (expect: comment-only changes).

## 02:10 — emit45/46: the mapping table is gone from root; the notes remain

- emit45 (with the mapping filter + TODO routing): the root header's
  mapping table **3,530 → 3 lines** (arch_x86_entry_vdso_vdso64_built-in,
  subcmd, vmlinux_export — the targets whose rules actually sit in root).
  102 BUILD files now carry Notes/review sections (the routed ones).
- But the root header stayed at 2.8k lines: the **Notes** section
  (~1,150 bullets, one per archive-recipe target — "the reference built
  X/built-in.a with its own ar recipe; it is a genrule over the captured
  argv") is emitted in the setup passes where no render context exists.
- emit46 (context also set in the setup passes: pass-1/pass-2 archive
  loops, the consumed-objects loop, the chosen/not-emitted loop; the
  hint comes from the target's compiles' dirs): arch/x86/kernel/cpu/
  microcode and 102 packages picked their notes up; sound_built-in etc.
  stayed in root because an archive-only target has NO compile — its
  identity is its output path.
- Fix: `_pkg_hint_of_target` falls back to the outputs' dirs (an
  archive-only Kbuild leaf's built-in.a lives in its own dir). Suites
  green (126 + 150).
- Also found and fixed a pre-existing emitter bug while here: in
  `emit()`, the extra-files loop rebinds `text`, so main()'s TODO
  summary has always counted the last extra file — every emit logged
  "0 TODO(s)" while the layer carries 135 (emit43's journal line
  "9m4s, 0 TODOs" was this bug, not a fact). Renamed the loop var; the
  summary now counts the root BUILD's TODOs truthfully.
- emit47 (background) to measure the routed state; then diff vs the
  layer (comment-only expectation), install, parity.

## 03:40 — the parity RED was my own installer invocation, not the tool

- emit48's tree is **complete and clean**: 2,322 BUILD files = HEAD's
  tracked set minus the 7 infra BUILDs (bazel/, platforms/, toolchain/),
  and a strip-compare (comments removed) of every one against HEAD
  found **0 non-comment differences**. The merged freebsd tool work
  (6259752) reproduces the layer bit-for-bit outside comments — my
  header/TODO-routing edits are the only delta, exactly as intended.
- The "557 files" collapse and the parity RED were self-inflicted: I ran
  `bash /tmp/install-emit.sh` **without EMIT=**, so it defaulted to the
  stale `/tmp/all-emit` (557 files from an old run), deleted 1,765 good
  BUILDs and installed that partial tree. The earlier strip check that
  "found no diffs" had compared the emit tree against the partially
  installed layer — meaningless. Lesson recorded: always EMIT=; never
  install while a background emit is still writing.
- Restored the layer with `git checkout -- .`, removed the stray
  untracked arch/x86/net/BUILD.bazel (also from the partial install),
  reinstalled properly (EMIT=/tmp/all-emit48, 2,322 files).
- Result: root BUILD.bazel header **3,837 → 848 comment lines** before
  the first rule (mapping table 3,530 → 3 lines; all 135 TODOs now sit
  beside the rules they concern, root keeps its own 16, e.g. the
  objtool-from-host hermeticity ask). Root notes: 0 tree-wide bullets.
- parity.sh linux running on the installed emit48 layer (background).
- First parity after install: build=RED — but the errors were only
  "missing input file //:bazel-bin/include/generated/{timeconst,utsversion}.h
  and //:bazel-bin/init/utsversion-tmp.h" on host ([for tool]) compiles,
  everything else cache hits, and `bazel build //:timeconst_h
  //:utsversion_h` alone succeeded from cache. The producers were fine:
  this was **stale Bazel server state** left over from the earlier
  broken-partial-layer build. A fresh `bazel build //... --keep_going`
  went green (exit 0, 0 errors) with no layer change at all.

## 04:10 — PARITY GREEN on the new layer: converged, IDIOM 0.1

- `parity.sh linux`: **PARITY build=GREEN diff=converged errors=0
  warnings=14 artifacts=converged 0 errors**. IDIOM score=0.1 (was 0.3)
  — moving the 135 review TODOs out of the root package lowered the
  todo detector. rules=3126 tus=1236 genrules=1 dirs=120 unchanged.
- The owner's 2026-10-06 scrub item is done: the root BUILD header is
  848 comment lines (was 3,837), the tree-wide name-mapping table is
  gone (3,530 → 3 lines), every review TODO renders beside the rule it
  concerns (root keeps its 16, e.g. objtool-from-host).
- Next: boot on a free port, hermetic container build, check-invariants
  with the corpus, then commit the tool changes.

## 05:10 — the kb-merge lands in the suite; and the probe deletion was a mistake

- `test_kbuild_per_object_defines_merge_into_one_library` failed for two
  reasons, both mine to fix in the test/flow, not the concept:
  1. `_kbuild_refine` rode `_route_packages`, which returns early when
     the conventions have no package_dirs — single-package projects (and
     every test) never refined. Moved the refine to an unconditional
     loop after routing (emit_build.py, before the render loop).
  2. The test's MODFILE spelling: the arithmetic derives it from the
     rule's FINAL package (`pkg + "/" + stem`), so a root-package
     project records `-DKBUILD_MODFILE="a"` — the test had spelled the
     path-qualified form. Also the emitted srcs render one per line.
- With refine unconditional, `test_raw_linker_link_becomes_cc_raw_link`
  improved too: its BASENAME-only per-object defines reduce to
  `kbuild = "module"` (the rule computes exactly those), map dropped.
- Parity hole found and closed while reviewing the plan: a kb-merged
  group that is NOT the main group would keep stripped argv and LOSE its
  defines. Now such a group is its own cc_per_source_library piece
  (`p["group_ps"]`): its common line spelled once in copts, the defines
  computed per source — refine reduces the map again (emit50 vs 49:
  arch/x86/kernel, arch/x86/lib, lib/crypto, vdso64 gained the piece).
- **`toolchain/bazel-probe.json` is NOT a scrub item — restored.** It is
  checked into the layer since 2026-10-13 and the conventions' supply
  reads it at emit time (`toolchain_probe`). I had deleted it as
  "machine-specific diagnostic artifact"; with it gone emit49/50 spelled
  the whole kernel compile line into every piece's copts (107 BUILD
  files ballooned, e.g. fs/9p copts 5 → 115 tokens) — silently, no
  error. Restored from HEAD; emit51 re-runs with it. Lesson: never
  delete an input the emitter reads; verify by re-emit + diff, not by
  parity (parity does not consume the probe).

## 06:05 — the 2 parity errors root-caused: the merge reordered the links

- emit52's parity: errors=2 (zoffset.h +48B, vdso64-image.c). Not a
  compile-flag problem — **every TU object is byte-identical to the
  reference** (1,104 ref .o's compared; the only other "differences" are
  pre-existing DWARF path strings in the 4 realmode/rm objects —
  ref's DWARF records `/scratch/bluecmd/linux-bzl/ref` and the
  src-ref path, bazel's `/proc/self/cwd` + relative path; same sections,
  same sizes, not flagged by the differ, downstream-irrelevant).
- The break is **link order**. The reference links vdso64.so with
  `note.o, vclock_gettime.o, vgetcpu.o, vgetrandom.o,
  vgetrandom-chacha.o`; the kb-merge bucketed note.S and
  vgetrandom-chacha.S together (same argv minus defines) into one
  cc_per_source_library, which hands its objects to the link together —
  chacha.o lands right after note.o instead of last. vdso64.so bytes →
  vdso2c → vdso64-image.c → vdso64-image.o → (thin built-in.a: member
  bytes live in the members, so all 555 .a files compared "identical"
  while their members changed) → vmlinux.o → vmlinux.bin → xz (+56) →
  piggy.o (+56) → compressed vmlinux (+0x30 layout) → zoffset.h. **One
  root cause behind both errors.**
- The false leads, for the record: the compressed package's per_source
  map is token-identical between emit48 and emit52 (the earlier
  "extras shuffled between cpuflags.c/error.c" reading was a truncation
  artifact); the vmlinux_o savedcmd is identical too; vmlinux.a itself
  is byte-identical.
- Fix (tool, generic): `_merge_kbuild_groups` now splits each ≥2-member
  bucket into maximal `_ld_runs` — runs whose objects the reference's
  link keeps adjacent (ld_order stems, scripts don't matter). A
  split-off run of one keeps its full argv verbatim (defines included);
  an adjacent run still merges. Suite: new
  test_kbuild_merge_keeps_the_links_object_order (link order s1, trio,
  s5 asserted on the cc_raw_link args), 128/128 emit_build, engine
  150/150, extract 181/181, idiom, cargo/vcpkg suites green.
- emit53 (with the fix) re-running; parity after install.

## 06:55 — PARITY CONVERGED again: errors=0, IDIOM 0.2

- emit53 installed; `parity.sh linux`: **PARITY build=GREEN
  diff=converged errors=0 warnings=14 artifacts=converged 0 errors.
  IDIOM score=0.2 rules=2930 tus=1236 genrules=1 dirs=120.** The
  kb-merge now lands with parity: the link-order runs are the only
  delta vs emit52 (3 BUILD files outside comments).
- Corpus sweep (CORPUS=1) + suites running for the tool merge; image
  build for the boot gate kicked off on the new layer.

## 07:20 — boot + invariants green; tool committed

- **BOOT-SSH OK after 3s: Linux 7.2.0** (port 2227, key
  /scratch/bluecmd/linux-bzl/keys/id_ed25519), on the image built from
  the emit53 layer. qemu exited cleanly (no stale process).
- **INVARIANTS OK** (CORPUS=1): all suites green, vocabulary clean,
  corpus 37 converged before and after.
- Tool committed in wt-kernel: `7f39c7e emit_build: merge Kbuild's
  per-object defines into per-source libraries, in runs the link keeps
  adjacent` (emit_build.py + test suite; kbuild-intree branch, unmerged
  like last run's a0162a2).
- Hermetic container build running on the final layer.

## 07:45 — HERMETIC OK; verdict

- **HERMETIC OK: //bazel/image:image builds in a clean container.**
- All gates green on the emit53 layer: parity converged 0 errors,
  IDIOM 0.2, BOOT-SSH OK, invariants OK, hermetic OK.
- Tool commits this run (kbuild-intree): a0162a2 (header/TODO routing),
  7f39c7e (kb-merge + link-order runs).
- **Verdict: publish: release.** Report finalized; layer tree left with
  the emit53 BUILD files as the run's deliverable (harness squashes);
  no stray files beyond the bazel convenience symlinks; no stale qemu.
