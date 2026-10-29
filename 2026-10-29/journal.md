# journal — 2026-10-29

## 00:00 — state re-established

- parity-before (harness-measured): **PARITY build=GREEN diff=converged
  errors=0 warnings=12 artifacts=converged, IDIOM 0.0** (rules=2928
  tus=1236 genrules=0 dirs=120). Layer tree clean vs the release commit
  5636591ff; only the bazel-* symlinks untracked. Tool worktree at
  bcbfdce (Merge branch 'freebsd-intree').
- The start-state "HERMETIC FAILED" pointer
  (runs/2026-10-27/hermetic.txt) read to its source:
  /scratch/bluecmd/linux-bzl/hermetic/last.txt + hermetic.log are dated
  2026-10-27 01:06 and contain `E: You don't have enough free space in
  /var/cache/apt/archives/` — the container's setup failed before the
  build; the 2026-10-27 journal records the re-run (private podman store
  via CONTAINERS_STORAGE_CONF) as **HERMETIC OK**. Stale pointer, not a
  regression. This run re-proves it on the live tree anyway (release
  gate).
- Feedback file empty this run.

## 00:10 — gates re-proof launched

- parity.sh re-run completed: **PARITY build=GREEN diff=converged
  errors=0 warnings=12 artifacts=converged 0 errors, IDIOM score=0.0
  rules=2928 tus=1236 genrules=0 dirs=120** — byte-identical to the
  release numbers (parity.txt). Recorded floor stands: defines_diff x7
  (toolchains_llvm opt defines, accounted) + extra_tu x5 (stub TUs).
- hermetic re-run launched with the private podman store
  (CONTAINERS_STORAGE_CONF=hermetic/storage.conf; store kept from last
  run so the image pull is cached). /scratch has 185G free; / is 14G
  free (the last run's 128M exhaustion is over).
- emit29 launched: fresh real copy of the layer (cp -a, symlinks out)
  at /scratch/bluecmd/emit29, re-emit with the **merged** tool (bcbfdce
  — first emit of this tree under the freebsd-intree changes). Compare
  vs the layer when it finishes; 0 differ / 0 TODOs is the done line.

## 00:50 — the drift root-caused; tool fix written

- Instrumentation facts (emit30/31/32, A2B_DEBUG_OBJECTS): every
  object_files entry skips with **consumers=0** — the
  `object_file_consumers` dict never holds the entry. The entries come
  from `_plan_member_objects` (an archive recipe's compiled members must
  be addressable at the path the ar recipe names), which fills
  `object_files` directly; the consumers dict is filled only from
  codegen/raw-link replays reading an object. `fdccd6a`'s skip condition
  `if rels and not live:` treats "no recorded readers" as "all readers
  claimed" — on this tree every consumed-object library loses its
  cc_object_files hand-out, and the readers' labels dangle. On freebsd
  the path was never exercised (no object_files entries; its consumed
  objects ride step rules with `archive=` + `member=`), so the skip's
  bug could not show there.
- **Tool fix (uncommitted yet)**: record the readers across ALL of the
  lib's rels, and skip only when `recorded and not live` — an object
  whose reader is its own target's rule (the ar recipe over the members
  it compiled) needs the hand-out. emit_build suite 131/131 with the
  fix. A2B_DEBUG_KIND instrumentation added for the second drift class
  (2 files: recipe-kind `src` spelled bare `setup.elf`/`realmode.elf`
  where the layer spells the rule label `:setup.elf` — _kind_file's
  output_labels miss falling through to the srcs spelling).
- BOOT-SSH OK re-proven (port 2240 — first attempt failed on the
  standing port-collision ask, 2222 taken).
- **emit33 (fixed tool): 2,325/2,327 identical — class 1 gone**; the
  only remaining drift is the 2 bare-label files (arch/x86/boot,
  arch/x86/realmode/rm: recipe-kind `src` respelled bare where the layer
  spells `:name`). any2bazel.json identical, 0 TODOs. DBG-KIND
  instrumentation running (emit34) to root-cause the label spelling.

## Results so far

- PARITY re-proven on the untouched layer, identical to release.
- **HERMETIC OK re-proven** (00:30): `//bazel/image:image builds in a clean
  container` — 3248 action cache hits, Elapsed 78.1s, Critical Path 9.7s
  (hermetic/last.txt + hermetic.log refreshed; the private podman store
  reused). The start-state FAILED pointer was the stale 2026-10-27
  first-attempt file.
- IMAGE green: bzImage 2,417,664 B (release bytes) + initrd 2,623,909 B.


## 01:10 — class 2 root-caused; fix + fact + test landed

- DBG-KIND (emit34): `_kind_file` returns the RIGHT value on the drifting
  tokens — `ol_val=':setup.elf'` / `':realmode.elf'` — the strip happens
  later, in the respell pass: `fdccd6a` added an UNCONDITIONAL bare
  respell of same-package file targets in `_respell` ("the layer spells
  it the bare package-relative path" — true for freebsd, not for linux:
  the linux layer reads its same-package link outputs by their rule
  labels, `:setup.elf`).
- **Tool fix 2 (generic)**: the bare spelling is a style fact —
  `_respell` strips a same-package file label only when the conventions'
  `style.file_target_bare` is not false (default true = the emitter's
  own layout, so freebsd — whose `style` key has no such fact — is
  unaffected). Unit test `test_file_target_bare_style_fact_gates_the_respell`
  added: a routed package's raw-link output read by an objcopy recipe,
  default → bare, fact false → `:label`. (The first two test drafts used
  shapes that never reach the respell loop — an unrouted genrule's srcs
  are spelled at render, a non-cwd-dependent action never enters the
  recipe-kind path; the landed shape is a routed package + a
  cwd-dependent recipe, the real drift path.)
- **Layer fact**: conventions.json gains `"style": {"file_target_bare":
  false}` (3 lines; a layer file the harness squashes).
- Suites: all 22 green (emit_build now 132/132 with the new test).
- emit35 running: fresh layer copy (with the style fact), re-emit with
  both fixes — require same=2327 differs=0.
- freebsd no-regression emit running: fb-emit-check (byte-identical copy
  of the freebsd layer, verified), emit with the merged+fixed tool —
  require every BUILD.bazel identical to the layer.
- check-invariants.sh CORPUS=1 running on the worktree.

## 01:55 — emit35: the layer reproduces byte-identically again

- **emit35 (both fixes + the layer's style fact): 2,327/2,327
  BUILD.bazel byte-identical** (stronger than the strip-compare standard:
  cmp is clean, only_emit=0 only_layer=0), any2bazel.json identical to
  the model's config, 0 TODOs. The merged tool (bcbfdce + the two
  commits) reproduces the linux layer fully again.
- check-invariants.sh CORPUS=1: **INVARIANTS OK** — suites green, no
  deliverable vocabulary, corpus 37 converged before, 37 after.
- Tool commits landed on kbuild-intree: 046b2ca (the claimed-readers
  skip), 19e1626 (the `style.file_target_bare` fact + test).
- freebsd no-regression emit: the emit into fb-emit-check rewrote only
  4 of 179 BUILD files (root + sys/{amd64,x86,i386}/include) — 175/179
  byte-identical. The layer's copies differ from the emit's render on
  those 4. Since the merged branch contains ALL of wt-freebsd
  (1d6c916 is an ancestor of bcbfdce) and neither fix changes freebsd's
  render (no object_files entries; no `style` key → default true), this
  4-file drift is expected to be pre-existing — proving it now: the
  same emit with wt-freebsd's tool (fb-emit-base) is running; if it
  differs on the same 4 files, no regression from the merge or the
  fixes.

## 02:15 — freebsd no-regression proof: clean; the 4-file story resolved

- The earlier "fb-emit-base: 179/179 identical" was read MID-EMIT (the
  log's last line was still the DeprecationWarning — the emit had not
  written the 4 files yet). Corrected result: **the baseline tool
  (wt-freebsd 1d6c916) differs from the freebsd layer on the same 4
  files** (root + sys/{amd64,x86,i386}/include) — the layer's root and
  include-package BUILDs are hand-converged text (freebsd style render:
  multiline globs, `cc:cc_library.bzl` load spelling, hand comments)
  that neither tool's fresh render reproduces. Pre-existing, a
  freebsd-loop matter.
- **No-regression proof (the decisive comparison): merged+fixed tool
  (19e1626) vs pre-merge tool (1d6c916) on the freebsd tree:
  179/179 BUILD.bazel byte-identical.** Neither the freebsd-intree
  merge nor the two fixes changed the freebsd render. (Bisecting: the
  fix-1-only emit also differs on the same 4 — vs the layer, not vs
  the baseline emit; the tools themselves agree everywhere.)
- The merge's tool delta vs 1d6c916 is exactly the two commits (git
  diff --stat 1d6c916 19e1626 -- scripts = emit_build.py 22+/6-).
- Both freebsd emits: 0 TODOs, emitted configs identical.
