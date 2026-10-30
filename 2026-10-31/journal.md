# journal — 2026-10-31

## 00:00 — start

- Start state: the 2026-10-29 release, untouched (parity GREEN/converged,
  IDIOM 0.0, HERMETIC OK, BOOT-SSH OK — all re-proven last run on this exact
  tree). IDIOM at the floor; no lever left, so this run is a gate re-proof.
- The tool worktree is at `1864082` (merge freebsd-intree) — one merged
  branch past the layer's last proven emit (`19e1626`). `545fc67` (freebsd's
  commonprefix→character-scan rewrite of the naming heuristic) touches every
  BUILD render, so the first gate is emit reproducibility under the current
  tool.
- Launched in parallel:
  - emit31: fresh cp -a of the layer (bazel-* symlinks out) at
    /scratch/bluecmd/emit31, emit with the current tool (1864082);
    done = 2,327/2,327 BUILD.bazel identical to the layer, 0 TODOs,
    any2bazel.json == models/kernel/any2bazel.json.
  - parity.sh linux → parity.txt in this run dir.
- plan.md and report.md written.

## 00:20 — PARITY re-proven; IMAGE green

- parity.sh linux → **PARITY build=GREEN diff=converged errors=0
  warnings=12 artifacts=converged 0 errors, IDIOM score=0.0 rules=2928
  tus=1236 genrules=0 dirs=120** — the release line, byte-for-byte.
- build-image.sh → **IMAGE: 2,417,664 B bzImage + 2,623,909 B initrd**
  (release bytes).
- boot-ssh-test.sh: first invocation with `--port 2240` failed — the shared
  script has no `--port` (only the positional form); and the 2222 default
  was taken again (the standing free-port-retry ask, now 3rd run in a row).
  Re-invoked positionally on 2240; hermetic-build.sh relaunched with the
  private podman store (CONTAINERS_STORAGE_CONF=/scratch/bluecmd/linux-bzl/
  hermetic/storage.conf).
- **BOOT-SSH OK after 3s: Linux 7.2.0** (positional form on port 2240).
- **emit31: 2,327/2,327 BUILD.bazel byte-identical** to the layer
  (cmp-level, byte_compare.py: same=2327 differs=0 only_emit=0
  only_layer=0), any2bazel.json identical to the model's config, 0 TODOs.
  The current tool (`1864082`, incl. freebsd's `545fc67` naming-heuristic
  rewrite) reproduces the linux layer fully — no re-emit needed, the
  delivered tree is the tool's render.

## 00:25 — hermetic attempt 1 failed on a leftover lock, not on the build

- Hermetic attempt 1 (launched while build-image was still finishing):
  **HERMETIC FAILED (exit 37)** — inside the container, "Another command
  holds the output base lock … Server terminated abruptly (error code: 14,
  Socket closed)". The lock was the output base of the *accidental*
  `--help` hermetic launch I stopped minutes earlier (its container's bazel
  server, cwd=/work), not a hermeticity finding. Private podman store
  verified empty afterwards (0 containers). Re-launched exclusively.

## 00:35 — HERMETIC OK; all gates closed

- Hermetic re-run exclusive: **HERMETIC OK** — the image builds in the
  clean ubuntu-24.04 container (Elapsed 46.8s, 3,248 cache hits, 1 action).
  The first attempt's failure was environmental (leftover lock), the layer
  was never implicated.
- No layer change, no tool change this run: the delivered tree is the
  2026-10-29 release tree, and emit31 proves it is still exactly what the
  current tool renders.

## 00:36 — done

All four gates re-proven on the delivered tree; verdict `publish: release`
in report.md. Standing asks unchanged (boot-ssh free-port retry — port 2222
taken again this run).
