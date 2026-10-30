# plan — 2026-10-31

## State at start

PARITY build=GREEN diff=converged errors=0 warnings=12 artifacts=converged,
IDIOM 0.0 (threshold 5.2) — the 2026-10-29 release state, tree unchanged
(only the four untracked `bazel-*` output symlinks). IDIOM is already at the
floor; no idiom lever remains. The tool worktree moved past the layer's last
emit again: `1864082` (merge freebsd-intree) contains freebsd's `545fc67`
(the commonprefix→character-scan rename, which touches the naming heuristic
every BUILD render goes through). The linux BUILD tree has not been re-emitted
under `545fc67`/`1864082`.

## What this run attacks (in order)

1. **Emit reproducibility under the current tool** (`1864082`): fresh copy of
   the layer (cp -a, `bazel-*` symlinks out), re-emit with emit_build.py,
   compare every BUILD.bazel vs the layer. Done = 2,327/2,327 identical,
   any2bazel.json identical to `models/kernel/any2bazel.json`, 0 TODOs.
   If anything drifts, root-cause in the emitter (generic fix + suite test),
   as last run did.
2. **PARITY re-proof** (parity.sh linux) — require the release line:
   GREEN / converged / 0 errors / warnings=12 / artifacts converged,
   IDIOM 0.0.
3. **IMAGE + BOOT-SSH re-proof** (build-image.sh, boot-ssh-test.sh) —
   bzImage + initrd at release bytes, Linux 7.2.0 over SSH.
4. **HERMETIC re-proof** (hermetic-build.sh linux, private podman store) —
   required for a release; cheap once the store cache is warm.
5. Only if a tool change happens: check-invariants.sh CORPUS=1 and a freebsd
   no-regression emit.

## What "done" is

All four gates re-proven on the delivered tree; report.md ends with the
verdict. Expected verdict: `publish: release` (nothing in the tree changed;
the gates re-prove the release state).

## Not attacked

- IDIOM: 0.0, threshold 5.2 — no detector fires; nothing to lower.
- Standing shared-script asks (boot-ssh free-port retry, freebsd's
  `--cdrom` ask) — unchanged, not mine to edit.
