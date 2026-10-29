# plan — 2026-10-29

## Read of the state

- PARITY build=GREEN diff=converged errors=0 warnings=12 artifacts=converged,
  IDIOM 0.0 (threshold 5.2) — the 2026-10-27 release state, re-measured by
  the harness this run; the layer tree is unchanged vs the release commit
  (only the four bazel-* symlinks untracked).
- The "HERMETIC FAILED" pointer in the start state is the **stale**
  2026-10-27 01:06 file: the disk-exhaustion first attempt whose log says
  `E: You don't have enough free space in /var/cache/apt/archives/` — the
  container's own setup failed before the build started. The 2026-10-27
  journal records the re-run with the private podman store as **HERMETIC OK**.
  A release requires hermetic, so this run re-proves it on the live tree.
- The tool worktree moved past this layer's last emit: bcbfdce merged
  freebsd-intree (fdccd6a per-package piece render + 1d6c916 generated
  outs in the filegroup). The linux layer's BUILD files were emitted with
  the pre-merge tool (ad852cf/c2a9c8d). The freebsd run proved
  re-emit reproducibility for its tree; the linux tree has never been
  re-emitted under the merged tool.

## Attack order

1. **Hermetic re-proof** (release gate): hermetic-build.sh linux with the
   private podman store (CONTAINERS_STORAGE_CONF, hermetic/storage.conf,
   store kept in place from last run). Done when HERMETIC OK with the
   full log tail. If it fails for a real reason, root-cause and fix the
   layer through conventions.json/rules (never a hand edit).
2. **Image + boot re-proof**: build-image.sh then boot-ssh-test.sh —
   parity is unchanged, so this is confirmation, not attack.
3. **Emitter reproducibility under the merged tool** (the run's real
   work): scratch copy of the layer, re-emit with bcbfdce, cmp every
   BUILD file vs the layer. Done when 0 differ (or the drift is
   root-caused — a tool change that re-spells this project's files is a
   corpus question and would need its own proof before any install).
4. **Parity re-proof** on the untouched layer (background while 1 runs):
   parity.sh linux must reproduce the release numbers exactly.
5. If time remains: the defines floor (x7, toolchains_llvm flat
   opt_compile_flags) — recorded floor in two runs, out of lane last
   run; only moved by a toolchain-config change with broad blast radius.
   Not planned unless 1–3 finish early and leave real hours.

Tool changes are not planned. Invariants run only if a tool change
happens.

## Done

Every gate re-proven on the delivered tree with recorded outputs in this
run's directory: PARITY identical to release (warnings=12, IDIOM 0.0),
HERMETIC OK, IMAGE green, BOOT-SSH OK, emit reproducible under the
merged tool (0 differ / 0 TODOs). Report written early and kept current.
