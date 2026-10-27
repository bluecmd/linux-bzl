# journal — 2026-10-27

## 00:05 — state re-established, parity-start

- parity-start: **PARITY build=GREEN diff=converged errors=0 warnings=14
  artifacts=converged, IDIOM score=0.0 (rules=2928 tus=1236 genrules=0
  dirs=120)** on the committed layer (aff0f70a6, the 2026-10-25 emit25
  install); any2bazel wt-kernel at 80639e7. Tree clean (only the bazel
  convenience symlinks). Feedback file empty.
- The 14 warnings, from diff.json: defines_diff x7 (exec toolchain opt
  defines), extra_tu x5 (the accounted stub TUs), generated_tool_diff x1 +
  generated_args_diff x1 (the auto_conf generator-swap pair).

## 00:25 — discovery: the auto_conf warnings are Bazel's run_shell
## command-length threshold, not a layer question

- The layer's tree_recipe actions mostly carry their composed command
  INLINE in the aquery argv (`/bin/bash -c '<mkdir && cp && export && cd &&
  <recipe>'`); the differ's stage machinery (GLUE_PROGRAMS dropped, nested
  `sh -c` descended) compares the recipe's real stage with the reference's
  exec — that is why e.g. the cpufeaturemasks_h pair converges silently.
- auto_conf (and tmp_vmlinux_nm_sort, asm_offsets_s, rq_offsets_s — 7
  actions) had their composed command moved into a
  `<target>.run_shell_N.sh` file by Bazel (over its command-length
  threshold — auto_conf's mkdir line alone names ~2000 Kconfig dirs), so
  the differ saw one opaque stage whose identity is the wrapper file's
  name and whose args are empty → the tool swap + missing-args pair of
  warnings.
- `codegen.genrule_command` already reads Bazel's long-command fallback
  for a genrule (`bash <path>.genrule_script.sh`) — the run_shell wrapper
  naming was just not covered. Tool change (ba06414): the `-c` branch
  reads a wrapper file whose name matches `.run_shell_N.sh` too.
- Verified on real data before commit: re-extract + re-diff on the live
  layer → **the 2 generator warnings gone, converged stays, 0 new rows**
  (defines_diff x7 + extra_tu x5 remain). Suites all green (codegen
  22/22 with the new file-read case, emit_build 131/131, engine 150/150,
  extract_capture 181/181, the rest unchanged). Committed c2a9c8d.

## 00:35 — emitter fix: a `./`-spelled recipe program word is the tree
## path the rule stages the tool at

- The root's 1 open TODO (`vmlinux_o` runs `./tools/objtool/objtool`) is
  factually stale: the emitted rule already carries
  `stage_tools = [":objtool"]` / `stage_dests = ["tools/objtool/objtool"]`
  (built for the exec platform, copied into the mirror tree at the path
  the recipe spells). The emitter's `_unsupplied_recipe_progs` matched
  the word only as spelled, never against the stage_dest's `./`-less
  form → the ask for a tool the rule already builds and stages.
- Tool change (ad852cf): the membership test goes by the word's
  tree-path form too (`./x` from cwd `.` is `x`; cwd-relative spellings
  resolve through the cwd), the TODO text keeps the reference's
  spelling. New test `test_recipe_prog_word_dotted_slash_runs_the_staged_tool`
  (emit_build 131/131): the staged tool asks nothing, `./t/missing`
  still asks. All suites green. Committed ad852cf.
- Re-emit running (emit27, ~15 min) — expected layer delta: the root
  BUILD's TODO line only.

## 01:05 — emit27: verified, installed, parity running

- Emit done: 2,322 BUILD files, EXIT=0, **0 TODOs** (the root's stale
  objtool ask is gone; no "still needs a human" section in the root at
  all). /scratch has room; /tmp's root fs is 100% full again (128M free)
  — all emit work stayed on /scratch; the stale emit25 tree deleted.
- Strip-compare vs the layer: **2,321/2,322 identical outside comments**;
  the only diff is the root BUILD's TODO section (5 comment lines).
  any2bazel.json **identical** to the committed model copy.
- Install: EMIT=/scratch/bluecmd/emit27, 2,322 installed, the 7 infra
  BUILDs kept, config copied to models/kernel/any2bazel.json.
- parity.sh running on the installed layer (cache-heavy: the only rule
  text change is the root TODO line, so the build should be almost all
  cache hits; aquery + diff re-run with the new tool — the diff step now
  reads the run_shell wrapper files, expected 12 warnings).

## 01:35 — gates on the emit27 layer

- parity: **PARITY build=GREEN diff=converged errors=0 warnings=12
  artifacts=converged, IDIOM score=0.0 (rules=2928 tus=1236 genrules=0
  dirs=120)** — warnings 14 → 12 (the auto_conf tool+args pair dissolved
  by the run_shell-wrapper read; the remaining 12 are defines_diff x7 +
  extra_tu x5, the accounted floor).
- IMAGE green: bzImage 2,417,664 B + initrd 2,623,909 B (same numbers as
  the 2026-10-25 release).
- **BOOT-SSH OK after 3s: Linux 7.2.0** (port 2231, key
  $ROOT/keys/id_ed25519).
- Invariants (CORPUS=1) running; hermetic next.

## 01:45 — invariants OK; the defines floor investigated

- **INVARIANTS OK (CORPUS=1)**: suites green, vocabulary clean, **corpus
  37 converged before and after** — neither tool change (the `./`-word
  membership test; the run_shell-wrapper read) regressed a corpus
  package; the picocom/uhubctl residual detectors are the known
  pre-existing corpus findings, unchanged. EXIT=0.
- Layer delta vs the release commit: **BUILD.bazel −5 comment lines**
  (the stale TODO section). Nothing else.
- defines_diff x7 investigated to its source: the flags are
  toolchains_llvm's flat `opt_compile_flags`
  (`-U_FORTIFY_SOURCE … -D_FORTIFY_SOURCE=1 -DNDEBUG` in its
  cc_toolchain_config.bzl) — no feature boundary, no per-target off
  switch; the layer's exec toolchain is the external module. Removing
  them means forking/patching the toolchain config (broad blast radius,
  all exec-platform compiles), and the artifacts these TUs feed compare
  byte-equal today WITH the defines — the defines are inert here.
  Counter-`-U` copts would only move the rows between define sets.
  Recorded as the accounted floor, as in 2026-10-25.
- Hermetic clean-container build running on the final layer.

## 02:05 — hermetic failure is host disk exhaustion, not the layer

- First hermetic run: **HERMETIC FAILED** but the log shows the failure is
  in the container's own setup — `E: You don't have enough free space in
  /var/cache/apt/archives/` — the build never started. The container
  overlay lives in the shared podman store at /opt/podman (on the root fs:
  61G/61G, 128M free; podman df: 15.9GB images, 13.7GB reclaimable,
  2.1GB volumes 100% reclaimable, one foreign active container
  `herdr-gateway` running since Oct 24).
- Decision: do NOT prune the shared store — the images belong to other
  users/loops of this machine. Instead this invocation gets a private
  podman store on /scratch via `CONTAINERS_STORAGE_CONF`
  (hermetic/storage.conf: overlay graphroot+runroot under
  hermetic/podman-*) — env var, per-process, nothing else changes.
  Re-run launched with that env; /scratch has 6.7G free (cache dir 14G
  already mounted at /cache, reused).
- **HERMETIC OK** on the re-run: `//bazel/image:image builds in a clean
  container` — 3248 action cache hits, Elapsed 61.2s, Critical Path 6.78s
  (log tail: Build completed successfully, 1 total action). The private
  store cost only 82M (image + overlay); kept in place so re-runs skip
  the pull. hermetic.txt records both runs honestly.

## 02:25 — all gates green on the final layer

- PARITY converged errors=0 warnings=12, IDIOM 0.0; IMAGE green;
  BOOT-SSH OK after 3s; INVARIANTS OK corpus 37 before/after;
  **HERMETIC OK**. Verdict: publish: release.
