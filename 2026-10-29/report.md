# report — 2026-10-29

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=12 artifacts=converged,
IDIOM 0.0 (threshold 5.2) — the 2026-10-27 release state, re-measured by
the harness; the layer tree is unchanged vs the release commit. The
"HERMETIC FAILED" pointer in the start state is the **stale 2026-10-27
01:06 first-attempt file** (apt disk-exhaustion in the container's setup,
build never started; the 2026-10-27 journal records the re-run with the
private podman store as HERMETIC OK). The tool worktree moved past this
layer's last emit: bcbfdce merged freebsd-intree (the per-package piece
render + generated-outs filegroup) — the linux BUILD files have never
been re-emitted under the merged tool.

## Plan

plan.md — (1) hermetic re-proof with the private podman store, (2) image
+ boot re-proof, (3) emitter reproducibility under the merged tool
(scratch copy, re-emit, cmp vs layer), (4) parity re-proof on the
untouched layer.

## Journal

journal.md in this directory.

## Results

*(in progress — updated as gates land)*

- PARITY re-proven identical to release: GREEN/converged/0 errors/
  warnings=12/artifacts converged, IDIOM 0.0 (parity.txt).
- **HERMETIC OK re-proven** (the release gate the start state flagged as
  failed was the stale 2026-10-27 first-attempt file): the image builds
  in a clean ubuntu-24.04 container with the private podman store
  (Elapsed 78.1s, 3248 cache hits).
- IMAGE green: bzImage 2,417,664 B + initrd 2,623,909 B — release bytes.
- **BOOT-SSH OK after 3s: Linux 7.2.0** (port 2240; the first attempt
  failed only because port 2222 was taken — the standing free-port-retry
  ask, unchanged).
- **The run's real finding — the merged tool no longer reproduces the
  layer**: re-emit of the untouched layer with bcbfdce (first emit under
  the freebsd-intree changes) differs on 99 of 2,327 BUILD files, one
  class on 97: the layer's `cc_object_files` rules (the objects recipes
  read by path) are dropped, the object paths moved into `exports_files`
  (files that do not exist in the tree), while the root's aggregates and
  recipes still spell the `//pkg:obj.o` labels — the emit tree would not
  build. Root cause found by instrumenting the emitter
  (A2B_DEBUG_OBJECTS, emit30/emit31): `fdccd6a`'s claimed-consumers skip
  fires with **consumers=0** — the object_file_consumers dict never
  holds the entry the lookup reads, so "not live" is true vacuously and
  every object_files entry is skipped. On freebsd the skip could not be
  calibrated against this shape at all: freebsd carries consumed objects
  in step rules with `archive = <target>` + `member = <name>` and has no
  `object_files` conventions key — the linux shape is the first that
  exercises this code path. **Fix written** (generic): record the readers
  across all of the lib's object paths and skip only when readers are
  recorded AND all claimed — an object whose only reader is its own
  target's rule (the ar recipe over the members it compiled) needs the
  hand-out. emit_build suite 131/131; a second drift class (2 files:
  recipe-kind `src` respelled bare `setup.elf` where the layer spells the
  rule label `:setup.elf`) — root-caused too: `_kind_file` returns the
  right label; the strip is `fdccd6a`'s UNCONDITIONAL bare respell of
  same-package file targets in `_respell` (true for freebsd's layout,
  not linux's). Fix: the bare spelling is a conventions `style` fact —
  `file_target_bare`, default true (the emitter's layout, freebsd
  unaffected); the linux layer sets it false. Unit test added (routed
  package + cwd-dependent objcopy recipe over the package's raw-link
  output: default → bare, fact false → `:label`); suites all green,
  emit_build 132/132. The layer's conventions.json gains the 3-line
  fact.
- **emit35 (both fixes + the fact): 2,327/2,327 BUILD.bazel
  byte-identical to the layer** (cmp clean, only_emit=0 only_layer=0),
  any2bazel.json identical to the model's config, 0 TODOs. The merged
  tool reproduces the linux layer fully again.
- **Freebsd no-regression proven**: the merged+fixed tool renders the
  freebsd tree byte-identically to the pre-merge wt-freebsd tool
  (179/179 BUILD.bazel agree). Both tools' fresh renders differ from
  the freebsd LAYER on the same 4 files (root + sys/{amd64,x86,i386}/
  include) — hand-converged text neither tool reproduces; pre-existing,
  a freebsd-loop matter (an earlier "baseline 179/179 identical" read
  the emit mid-flight; corrected in the journal).
- Tool commits on kbuild-intree: 046b2ca (claimed-readers skip),
  19e1626 (style fact + test). check-invariants.sh CORPUS=1:
  INVARIANTS OK (suites green, vocabulary clean, corpus 37 converged
  before, 37 after).
- The gates re-proven at the top stand on the delivered BUILD tree:
  this run's only layer delta is the 3-line conventions.json fact,
  which Bazel never reads — PARITY/IDIOM/HERMETIC/IMAGE/BOOT-SSH
  results are unchanged by it, and emit35 proves the BUILD tree is
  still exactly what the (fixed) tool reproduces.


## Verdict

**publish: release**

Every gate re-proven on the untouched layer, byte-identical to the
release numbers: PARITY GREEN/converged/0 errors/warnings=12 (the
accounted floor: defines_diff x7 toolchains_llvm opt defines + extra_tu
x5 stub TUs), IDIOM 0.0 (threshold 5.2), HERMETIC OK in the clean
container (the start-state FAILED pointer was the stale 2026-10-27
first-attempt file — journal §00:00), IMAGE green at release bytes,
BOOT-SSH OK (Linux 7.2.0, 3s to shell).

The run's real work was the emitter: the merged freebsd-intree tool no
longer reproduced the linux layer (99/2,327 differ). Both drift classes
root-caused and fixed generically, committed on kbuild-intree
(046b2ca, 19e1626), suites green (emit_build 132/132), corpus invariants
OK — and the re-emit is byte-identical again (emit35 2,327/2,327), with
freebsd proven unaffected (179/179 vs the pre-merge tool). The layer
carries the one fact the fixed tool needs (conventions.json
`style.file_target_bare: false`, +3 lines).

## Standing asks (shared scripts, unchanged this run)

- boot-ssh-test.sh: retry the host-forward port when it is taken (this
  run's first boot failed on 2222; an explicit --port 2240 fixed it).
  A free-port retry loop in the script would remove the manual step.
