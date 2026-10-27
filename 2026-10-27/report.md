# report — 2026-10-27

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=14 artifacts=converged,
IDIOM 0.0 (threshold 5.2) — the 2026-10-25 release state. Feedback file
empty this run. Boot + hermetic green at that release. This run attacks
the recorded residuals: the stale objtool TODO on `vmlinux_o`, the 2
auto_conf generator-swap warnings, the 7 exec-toolchain defines_diff
warnings.

## Plan

plan.md — (1) the emitter's TODO matcher vs `./`-prefixed stage_dests
(generic, expected TODOs 1 → 0), (2) diff.py tree_recipe tool-stage
identity for the generator-swap warnings (generic, warnings 14 → 12),
(3) the defines floor investigation.

## Journal

journal.md in this directory.

## Results

Two tool changes landed on kbuild-intree (both generic, both with the
proof done on live data before commit):

1. **emitter, ad852cf — `./`-spelled recipe program words resolve to the
   tree path the rule stages the tool at.** The run started with exactly
   one open TODO in the layer (`vmlinux_o` "runs
   `./tools/objtool/objtool` from the host PATH") — factually stale: the
   emitted rule already carries `stage_tools = [":objtool"]` /
   `stage_dests = ["tools/objtool/objtool"]`. The emitter's
   `_unsupplied_recipe_progs` matched the word only as spelled, never
   against the stage_dest's `./`-less form. Fixed via `_prog_tree_paths`
   (word + cwd-resolved tree path, membership against `supplied`);
   cwd passed at the tree_recipe call site. New test in emit_build;
   suites all green. **TODOs 1 → 0** — the layer root's
   "still needs a human" section is gone entirely.
2. **codegen, c2a9c8d — `genrule_command` reads Bazel's run_shell
   wrapper files.** The 2 auto_conf generator-swap warnings
   (generated_tool_diff + generated_args_diff) were not a layer or
   tool_map question: Bazel's run_shell command-length threshold had
   moved those composed commands into `<target>.run_shell_N.sh` files
   (auto_conf's mkdir line names ~2000 Kconfig dirs), so the differ saw
   one opaque stage. The existing `.genrule_script.sh` fallback already
   covers the genrule long-command form; the `-c` branch now also reads
   a file whose name matches `.run_shell_N.sh` (read where the aquery
   ran). Verified on the live layer before commit: 2 warnings gone,
   converged stays, 0 new rows. **warnings 14 → 12.**

emit27: 2,322 BUILD files, EXIT=0, 0 TODOs, 2,321/2,322
strip-identical vs the layer (the only diff is the root BUILD's deleted
stale TODO comment block), any2bazel.json identical. Installed with the
7 infra BUILDs kept; model copied to models/kernel/.

Gates on the installed emit27 layer (all re-proven, not carried):

- **PARITY build=GREEN diff=converged errors=0 warnings=12
  artifacts=converged, IDIOM score=0.0** (rules=2928 tus=1236
  genrules=0 dirs=120) — floor of warnings 12: defines_diff x7 + the
  accounted extra_tu stub TUs x5.
- **IMAGE green**: bzImage 2,417,664 B + initrd 2,623,909 B (the
  release numbers).
- **BOOT-SSH OK after 3s: Linux 7.2.0** (port 2231).
- **HERMETIC OK**: the image builds in a clean ubuntu-24.04 container
  (after the disk-exhaustion workaround described below).
- **INVARIANTS OK (CORPUS=1)**: suites green, vocabulary clean, corpus
  37 converged before and after — neither tool change regressed a
  package (the picocom/uhubctl residuals are the known pre-existing
  corpus findings, unchanged).

### The defines floor

defines_diff x7 investigated to its source: the flags
(`-U_FORTIFY_SOURCE … -D_FORTIFY_SOURCE=1 -DNDEBUG`) are
toolchains_llvm's flat `opt_compile_flags` in its
cc_toolchain_config.bzl — no feature boundary, no per-target off
switch; the layer's exec toolchain is the external module. Removing
them means patching the toolchain config (broad blast radius, every
exec-platform compile), and the artifacts these TUs feed compare
byte-equal today WITH the defines — the defines are inert here.
Counter-`-U` copts would only move the rows between define sets.
Recorded as the accounted floor, as in 2026-10-25. Not attacked.

### Hermetic incident

The first hermetic run FAILED before the build started: the container's
apt hit `E: You don't have enough free space in /var/cache/apt/archives/`
— host disk exhaustion, not layer content (root fs 61G/61G, 128M free;
the shared podman store at /opt/podman ~65.1/65.28GB, 13.7GB reclaimable
images + 2.1GB volumes, one foreign active container `herdr-gateway`).
The shared store was NOT pruned (the images belong to other users of
this machine); the re-run got a private podman store on /scratch via
`CONTAINERS_STORAGE_CONF` (env, per-process; 82M — image + overlay).
Result: **HERMETIC OK: //bazel/image:image builds in a clean container**
(3248 action cache hits, Elapsed 61.2s, Critical Path 6.78s).

### Shared-script asks (report-only; the loop scripts were not edited)

Standing from the previous runs, unchanged this run:

- `boot-ssh-test.sh`: when the picked SSH port is taken by another test
  (this host runs several), the run fails instead of retrying on the
  next free port — a free-port retry loop would make concurrent loop
  runs safe.
- `build-image.sh` (freebsd profile): the boot test expects the `--cdrom`
  form of the QEMU invocation, which the freebsd build does not produce;
  the two scripts disagree on that profile.

## Verdict

`publish: release` — the boot gate stands (BOOT-SSH OK after 3s:
Linux 7.2.0) and every gate was re-proven on the final installed layer:
parity converged (errors=0, warnings=12 — down from 14), IDIOM 0.0
(threshold 5.2), image green, hermetic OK, invariants OK (corpus 37
before/after).

The layer delta vs the 2026-10-25 release commit is exactly the root
BUILD.bazel's deleted stale-TODO comment block (−5 comment lines) plus
an identical any2bazel.json — the release content is unchanged; the run
dissolved the last open TODO in the layer and 2 of the 4 warning rows,
and left the remaining 12 (defines_diff x7 + accounted stub TUs x5)
as the recorded floor. Tool: two generic fixes (the `./`-word vs
stage_dests membership test; the run_shell-wrapper file read), suites
green, corpus unregressed, committed ad852cf + c2a9c8d on kbuild-intree.

Ideas for a next run: the defines floor only moves if the toolchain's
opt defines get a feature boundary (a toolchains_llvm upstream change,
out of the loop's lane); nothing else the score can see has headroom —
IDIOM has been 0.0 with a held threshold for four runs.
