# plan — 2026-10-23

## State at start

PARITY build=GREEN diff=converged errors=0 warnings=14 artifacts=converged 0,
IDIOM 0.3 (threshold 5.2), 3126 rules / 1236 tus / 1 genrule / 120 dirs.
Layer at 82ca2c96c (the 2026-10-17 squashed layer), tree clean; any2bazel
wt-kernel at 6259752 (merged, carrying the 2026-10-17 tool work: ld-order
tie-break, per-piece raw-link spelling, replay_env, replay_args).

Runs 2026-10-19 and 2026-10-21 died with empty session.out — no work, no
report; the layer is exactly where 2026-10-17 left it.

## The one red flag: run 2026-10-17 was recorded boot=0 (pre-release)

Its own report says BOOT-SSH OK and `publish: release`, but the harness's
acceptance measured **boot=0**. The saved boot.txt shows why:

    qemu-system-x86_64: -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22:
      Could not set up host forwarding rule 'tcp:127.0.0.1:2222-:22'
    BOOT-SSH FAIL: qemu exited

The harness's boot test uses the default port **2222**; something on the
host held it (the run's own verification had used 2223, and sibling loops
boot on 2222 too). A port collision, not a boot failure — the gate died
before qemu started the guest. Same shape as the 2026-10-17 hermetic
first-attempt (podman arm64 flake) and the 2026-10-19/21 dead runs
(bazel cache symlink target deleted): the release has been environment-
blocked since 2026-10-17, never boot-blocked.

Nothing is holding 2222 now and no qemu-system is running.

## What this run does, in order

1. **Re-establish the release state honestly.** build-image.sh (running)
   + boot-ssh-test.sh on a free port; verify BOOT-SSH OK on the current
   layer. If it fails, that becomes the run's main line.
2. **Port-collision robustness** — cannot edit bin/ scripts (shared), and
   BOOT_ARGS (project.env) sits before the harness's key/timeout args so
   a port cannot ride it. What I can do: verify with an explicit port,
   keep no stale qemu alive across my session's end, and put the concrete
   generic fix in the report (boot-ssh-test.sh should treat "Could not
   set up host forwarding rule" as a retryable failure and pick a free
   port — it already knows qemu died before the guest came up).
3. **The owner's open scrub item: the root BUILD.bazel header.** 20,345
   lines, 3,837 of them comments before the first rule — the emitter
   prints the whole tree's reference-name → emitted-name mapping into the
   root package plus 135 review TODOs. The owner called this out on
   2026-10-06 ("no 4,000-line header comment"); it is still in main.
   Fix in the tool (generic: the emitted provenance header), not by hand:
   keep the one-line provenance + genuinely actionable notes; move or
   drop the mechanical mapping list.
4. **TODO notes that are stale**: ~88 of the 135 are "compiles X with
   different flags: split into cc_library (review)" — and the split
   already exists mechanically (e.g. arch_x86_kernel_built_in_amd_nb in
   arch/x86/kernel/BUILD.bazel with its own defines; parity converged).
   A note that asks a human to review a decision the emitter already made
   and parity already verified is noise; make the emitter emit the note
   only where it did not actually split. Same class: host-tool notes
   that say "check its copts/linkopts" where the differ already verified
   the content.
5. **Parity is the guard rail for every step**: after each tool change,
   re-emit, diff against the layer, install, parity.sh. Commit tool work
   incrementally with suites green. Then hermetic-build.sh (pull
   --platform linux/amd64 first — the arm64 flake), CORPUS=1
   check-invariants with the absolute worktree path.

## "Done"

- All gates green at the harness's own measurement: parity converged,
  image, **boot=1** (the thing the last three published runs lost),
  hermetic, corpus 37/37, tool merged.
- The release recorded (idiom threshold lowers to 0.3).
- Residual: fewer/shorter emitter review notes in the root BUILD, no
  tree-wide mapping comment in a package's BUILD.
