# report — 2026-10-31

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=12 artifacts=converged,
IDIOM 0.0 (threshold 5.2) — the 2026-10-29 release state, layer tree
unchanged (only the four untracked `bazel-*` output symlinks). IDIOM is
already at the floor; no detector fires, so this run had no idiom lever and
was a gate re-proof. The tool worktree is at `1864082` (merge
freebsd-intree), one merged branch past the layer's last proven emit
(`19e1626`); the merged branch carries freebsd's `545fc67`, a rewrite of the
common-stem naming heuristic that every BUILD render passes through.

## Plan

plan.md — (1) emit reproducibility under `1864082`, (2) PARITY re-proof,
(3) IMAGE + BOOT-SSH re-proof, (4) HERMETIC re-proof.

## Journal

journal.md in this directory.

## Results

- **PARITY re-proven**: build=GREEN diff=converged errors=0 warnings=12
  artifacts=converged, IDIOM 0.0 (rules=2928 tus=1236 genrules=0 dirs=120)
  — the release line, byte-for-byte (parity.txt). The accounted floor
  stands: defines_diff x7 (toolchains_llvm opt defines) + extra_tu x5
  (stub TUs).
- **Emit reproducibility under the current tool (`1864082`)**: fresh copy
  of the layer at /scratch/bluecmd/emit31, re-emit with emit_build.py —
  **2,327/2,327 BUILD.bazel byte-identical** (cmp-level), any2bazel.json
  identical to `models/kernel/any2bazel.json`, 0 TODOs. The freebsd merge,
  including `545fc67`'s naming-heuristic rewrite, does not move this
  layer's render: the delivered BUILD tree is still exactly the tool's
  output.
- **IMAGE green at release bytes**: bzImage 2,417,664 B, initrd
  2,623,909 B.
- **BOOT-SSH OK after 3s: Linux 7.2.0** (port 2240; 2222 was taken — the
  standing free-port-retry ask, 3rd run in a row).
- **HERMETIC OK re-proven**: the image builds in the clean ubuntu-24.04
  container (Elapsed 46.8s, 3,248 cache hits, 1 action). The run's first
  hermetic attempt failed with exit 37 on a leftover output-base lock —
  its own accidentally-launched/stopped earlier invocation holding the
  container's output base — an environmental failure, not a hermeticity
  finding; the exclusive re-run is the verdict.

## What changed

Nothing, by design: no layer file and no tool commit this run. Every gate
was re-proven on the delivered 2026-10-29 release tree, and emit31 proves
the tree is still byte-identical to what the current tool renders.

## What is next

Nothing load-bearing. Parity is at the release numbers, IDIOM is at 0.0,
and the image boots; no remaining idea moves a measured number. The
standing asks are unchanged (they are about the shared scripts, which this
run does not edit):

- boot-ssh-test.sh: retry the host-forward port when it is taken (2222 was
  taken again this run; the run used an explicit port). A free-port retry
  loop in the script would remove the manual step, which has now cost a
  manual rerun three runs in a row.

## Verdict

**publish: release**

All four gates re-proven on the delivered tree, byte-identical to the
release numbers: PARITY GREEN/converged/0 errors/warnings=12, IDIOM 0.0
(threshold 5.2), emit reproducibility 2,327/2,327 under the current tool,
IMAGE at release bytes, BOOT-SSH OK (Linux 7.2.0, 3s to shell), HERMETIC OK
in the clean container.
