# journal — 2026-10-25

## 00:20 — state re-established

- parity-start: **PARITY build=GREEN diff=converged errors=0 warnings=14
  artifacts=converged, IDIOM score=0.2 (rules=2930 tus=1236 genrules=1
  dirs=120)** on the committed layer c1058a1ae. Tree clean (only the bazel
  convenience symlinks). Feedback file empty.
- Score decomposition (idiom.json, t x weight): manual_rules 3 rules
  (t .0205 x5 = 0.10), todo 16 root TODOs (0.03), genrules_per_tu 1
  genrule (0.016), include_flags 21 (0.007), repeated_flags 22 (0.002)
  = 0.155 -> rounds to 0.2.
- The 3 manual rules: `//:tools_objtool_fixdep` and
  `//:tools_objtool_libsubcmd_fixdep` — two identical cc_binaries of
  tools/build/fixdep.c the reference's tools sub-builds compile; the
  layer's consumed fixdep is //scripts/basic:fixdep. Model check: **0
  consumers** for both (no action takes their binary as an input, no
  recipe names their path) — they are dead: never built (tags=manual
  keeps them out of //...), only unwired rules + review asks.
  `//:modules_builtin` (tree_recipe -> modules.builtin): 0 consumers
  too, but it is the emitter's deliberate sink-deliverable class ("made
  on purpose"), and diff.py's `_codegen_outputs` classes modules.builtin
  benign (not a compile input by extension) — G1 does not demand it.

## 00:40 — tool change A: dead host tools not emitted

- emit_build.py: `plan_codegen` now computes the model's consumed paths
  (declared inputs of every action, normalized, with consuming action
  ids — the tool's own link action names its -o output among its inputs,
  so consumers are `consumed - {own id}`) and skips a host tool whose
  output no other action consumes (a note records the skip). A tool a
  generator runs is emitted as before.
- `host_tool_checked` conventions record (generic mechanism, reviewer
  content, same shape as codegen_map/replay_env): host tools on the
  record get no exec-platform review TODO; tools not on it ask again.
- Suites: emit_build 130/130 (2 new tests: the dead-tool skip; the
  checked-record; the resolver test now models a consumer — its model
  had exactly the dead shape), engine 150/150, extract_capture 181/181,
  extractors 41/41, meson/ninja/npm/ts/codegen/artifact_diff/build_lint/
  build_triage/configure/elf_symbols/idiom/maven/probe_toolchain/triage/
  expand_template all green, cargo/vcpkg exit 0.
- Committed: `933efe3` in wt-kernel.

## 00:50 — the host-tool verification (the record's evidence)

- The 13 remaining host tools build with the exec toolchain:
  `bazel build //arch/x86/boot/compressed:mkpiggy //arch/x86/boot:mkcpustr
  //arch/x86/tools:relocs //arch/x86/tools:vdso2c //drivers/tty/vt:conmakehash
  //lib/crc:gen_crc32table //scripts/basic:fixdep //scripts/kconfig:conf
  //scripts/mod:mk_elfconfig //scripts/mod:modpost //scripts:sorttable
  //:objtool //usr:gen_init_cpio` — 250 actions, all green. (First
  attempt used root names for tools that live in their packages; and the
  `//:usr:` label spelling was wrong — labels don't carry two colons.)
- Recorded in conventions.json: `host_tool_checked` (the 13 names) with
  a `//host_tool_checked` note carrying the verification facts (this
  build + the 2026-10-23 clean-container image build, which runs the
  wired tools as rules' tools).

## 01:10 — the initrd genrule -> rule

- The workspace's one genrule is //bazel/image:initrd (hand-written
  infra, "not part of the kernel's parity"). diff.json already classes
  its action benign (excluded/bazel/codegen_benign: "bazel/image/
  initrd.cpio.gz (make-initrd.sh)"), so the shape change is parity-safe.
- New layer rule module `bazel/rules/initrd_cpio.bzl`
  (`initrd_cpio(init, keys, apks, out, script)`): ctx.actions.run of the
  packer script with the declared inputs; `$@` of the replaced genrule
  was the FULL declared path, so the rule passes `out.path` (the
  freebsd loop's lesson). mnemonic stays "Genrule" so parity's aquery
  line sees the same shape.
- //bazel/image:image builds green (1195 actions). bazel-bin/bazel/image/
  initrd.cpio.gz produced.

## 01:15 — emit25 running

- Emit command (as recovered in the 2026-10-17 journal):
  `cd /scratch/bluecmd/linux-bzl && python3
  /home/bluecmd/any2bazel/wt-kernel/scripts/emit_build.py
  models/kernel/model.capture.json --config models/kernel/any2bazel.json
  --conventions linux/conventions.json --out /tmp/all-emit25/BUILD.bazel
  --config-out /tmp/all-emit25/any2bazel.json` (~9 min).
- Expected vs the layer: root BUILD loses the two dead cc_binaries, 2
  host-tool TODOs, 13 host-tool TODOs (record); a note per skipped tool.
  Nothing else. Verification: strip-compare emit25 vs the layer on all
  BUILD files (comments excluded), then install, then parity.

## 01:30 — notes while emit runs

- The emit to /tmp died at 219 files: **the root filesystem is full** (61G
  used, 124K free; /home also full). Emitted to /scratch instead
  (/scratch/bluecmd/emit25, 261G free). Lesson: this host's /tmp is on the
  full root fs — emit trees go to /scratch.
- The 14 parity warnings, identified (all content-verified, the accounted
  floor):
  - extra_tu x5: the stub TUs the layer compiles where the reference's
    object came from a non-replayed step — .vmlinux.export.c,
    startup/{gdt_idt,map_kernel}.c, init/version-timestamp.c,
    scripts/mod/empty.c.
  - defines_diff x7: tools/lib/subcmd's 7 TUs (exec-cmd, help, pager,
    parse-options, run-command, sigchain, subcmd-config) compiled through
    the toolchains_llvm exec toolchain, whose opt mode adds
    -U_FORTIFY_SOURCE -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=1 -DNDEBUG
    (toolchain-level, not the layer's copts; drop_copts cannot reach it).
    The reference compiled them plain. Artifacts still converged (objtool
    compares byte-equal), so the defines are inert here. Fixing would
    mean exec-toolchain opt-config surgery for 7 warnings — noted as
    residual.
  - generated tool/args diff x2: the //:auto_conf tree_recipe runs
    auto_conf.run_shell_0.sh where the reference ran scripts/kconfig/conf
    directly; content verified (the recorded .config/autoconf.h match);
    codegen.tool_map could record the swap.

## 01:45 — the auto_conf swap warnings: left as the content-verified floor

- G3's stage identity for the //:auto_conf tree_recipe is the rule's staged
  shell script, so `scripts/kconfig/conf` vs `auto_conf.run_shell_0.sh`
  reads as a tool diff. A tool_map entry recording the swap would be
  overwritten by the emitter's own output-path entry on the next emit
  (same dict, two uses), so the honest resolution is diff.py-side work
  (a tree_recipe's tool stage carrying its inner tool's identity) —
  recorded as a candidate tool improvement, not done this run; the pair
  is content-verified (G2 proved the recorded .config/autoconf.h equal),
  warning severity, and worth 0.000 of the score.

## 01:55 — emit25: verified and installed

- Emit done: 2,322 BUILD files, **1 TODO(s)** (was 16). Process: the
  second attempt (to /scratch) ran ~15 min wall (the /tmp attempt died
  at 219 files on a full root fs).
- Strip-compare (full-line comments removed) vs the layer:
  **2,321/2,322 identical**; the only diff is the root BUILD — the layer
  side has exactly the two dead cc_binaries (tools_objtool_fixdep,
  tools_objtool_libsubcmd_fixdep) that the emit no longer emits, and
  the 15 host-tool TODOs are gone (emit has 1: the objtool-from-host
  ask). The emit's notes carry "host tool -> fixdep: the reference
  builds it, nothing consumes it; not emitted". The infra BUILD set
  (bazel/, platforms/, toolchain/, 7 files) is layer-only as always.
- any2bazel.json: **identical** (the emitter keeps the input config's
  stale tool_map entries for the removed tools; they are inert — no
  action pairs those generator identities — and the next emit would
  re-add nothing).
- Install: EMIT=/scratch/bluecmd/emit25, 2,322 BUILD files installed,
  7 infra BUILDs kept, config copied to models/kernel/any2bazel.json.
- parity.sh running (cache-heavy: the removed targets were never built).

## 02:10 — gates on the emit25 layer

- parity: **PARITY build=GREEN diff=converged errors=0 warnings=14
  artifacts=converged 0 errors, IDIOM score=0.0 (rules=2928 tus=1236
  genrules=0 dirs=120)** — the floor reached; the 14 warnings are the
  same accounted floor as at run start.
- IMAGE green: bzImage 2,417,664 B + initrd 2,623,909 B
  (build-image.sh, the initrd now via the initrd_cpio rule).
- **BOOT-SSH OK after 3s: Linux 7.2.0** (port 2229, key
  /scratch/bluecmd/linux-bzl/keys/id_ed25519); qemu exited cleanly.
- Invariants (CORPUS=1) running; hermetic container build next.

## 02:25 — INVARIANTS OK

- **INVARIANTS OK (CORPUS=1)**: suites green, vocabulary clean, **corpus
  37 converged before and after** — the dead-host-tool skip regressed
  no corpus package (the riskiest class was a recipe running a tool the
  capture did not record as an input: such a tool was already unwired in
  the emitted layer, so skipping changes no build).
- Hermetic container build running on the final layer.

## 02:4x — HERMETIC OK, run closed

- Hermetic container build: **HERMETIC OK: //bazel/image:image builds in
  a clean container** (EXIT=0). All gates green.
- Report finalized with verdict **publish: release**.
- Layer diff vs c1058a1ae: root BUILD.bazel (−2 dead cc_binaries, −15
  TODOs, +1 skip note), bazel/image/BUILD.bazel (genrule → initrd_cpio),
  conventions.json (+host_tool_checked), new bazel/rules/initrd_cpio.bzl.
  Tool: wt-kernel 933efe3 (dead-host-tool skip + host_tool_checked), tests
  130/130.
- IDIOM 0.2 → 0.0; parity unchanged (converged, warnings=14); boot OK.
- Residuals recorded in report.md: diff.py tree_recipe tool-stage identity,
  exec-toolchain defines floor, boot-port retry (owner-side), include/
  repeated-flags residues.
