# report — 2026-10-25

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=14 artifacts=converged
0 errors, IDIOM 0.2 (threshold 5.2) — re-measured this session on the
committed layer (c1058a1ae, the 2026-10-23 emit53 install); any2bazel
wt-kernel at 4bd8887. Feedback file empty this run. Parity + boot +
hermetic are all green, so per the standing goal this run attacks the
idiom floor.

## Plan

plan.md — the idiom score's remaining 0.2 lives in: manual_rules x3
(two dead fixdep cc_binaries + the unwired modules_builtin tree_recipe,
0.10 of the score), 16 open TODOs in the root package (14 of them the
same "host tool builds with the exec toolchain" review ask, 0.03), and
small include/repeated-flags residues. Order: manual_rules first
(emitter: don't emit host tools nothing consumes; decide modules_builtin
on what artifact_diff actually guards), then the review-ask resolution
(verify + record in conventions.json, generic), then the small
residues. Parity as the regression test throughout.

## Journal

journal.md in this directory.

## Results

### (1) Tool: dead host tools are not emitted (emitter, generic)

`plan_codegen` now computes the model's consumed paths (the declared inputs
of every action, keyed by consuming action id — a tool's own link action
names its `-o` output among its inputs, so that self-reference is not a
consumer) and **skips a host tool whose binary nothing consumes**: no
recorded action takes it as an input and no recipe names it. Such a tool
could only be carried unwired — never built (the `manual` tag keeps it out
of `//...`), one more unwired rule, one more open review ask. On the layer
this removes `//:tools_objtool_fixdep` and
`//:tools_objtool_libsubcmd_fixdep` (two identical cc_binaries of
`tools/build/fixdep.c` the reference's tools sub-builds compile; the layer's
consumed fixdep is `//scripts/basic:fixdep`, which stays). A tool a
generator runs is emitted as before; a note in the header records each skip.

### (2) Tool + conventions: the exec-platform review ask is answerable

The 15 host-tool TODOs in the root package were all the same question —
"check its copts/linkopts build with the exec toolchain". New conventions
record **`host_tool_checked`** (a generic mechanism, reviewer content —
same shape as `codegen_map: "committed"` / `replay_env`): the emitter asks
no exec-platform question for tools on the record, and asks again for any
not on it. This run verified the 13 remaining host tools by building them
explicitly with the exec toolchain (`//arch/x86/boot/compressed:mkpiggy …
//usr:gen_init_cpio` — 250 actions, all green) plus the 2026-10-23
clean-container image build, and recorded the names in
`linux/conventions.json` with a `//host_tool_checked` note carrying the
verification facts. Root TODOs: **16 → 1** (the objtool-from-host ask on
the `vmlinux_o` recipe, a genuinely open hermeticity question).

### (3) Layer: the initrd genrule is a purpose rule

The workspace's one genrule (`//bazel/image:initrd`, hand-written infra)
became the rule **`initrd_cpio`** (`bazel/rules/initrd_cpio.bzl`): the
packer script as the rule's tool, every input declared, `out.path` passed
for the script's `$@` (the full declared path — the freebsd loop's
lesson). mnemonic stays `Genrule` so parity's aquery sees the same action
shape; diff.json still classes the action `codegen_benign` (not a compile
input), and the declared output path is unchanged
(`bazel-bin/bazel/image/initrd.cpio.gz`, which the release workflow and
build-image.sh copy). **genrules 1 → 0.**

### (4) The re-emit gate (the 2026-10-23 lesson, applied)

Emit25 (2,322 BUILD files): strip-compare against the layer found
**2,321/2,322 identical outside comments** — the only diff is the root
BUILD losing the two dead cc_binaries and the 15 host-tool TODOs; the
emit's notes carry one skip record per removed tool. `any2bazel.json`
identical. Installed (2,322 files, the 7 hand-written infra BUILDs kept,
config copied to `models/kernel/any2bazel.json`).

### (5) Parity + idiom on the emit25 layer

- **PARITY build=GREEN diff=converged errors=0 warnings=14
  artifacts=converged 0 errors** — parity.sh on the installed layer; the
  14 are the same accounted floor as at run start (5 stub-TU extra_tu,
  7 exec-toolchain defines_diff on tools/lib/subcmd, 2 content-verified
  auto_conf generator-swap warnings).
- **IDIOM score=0.0 (rules=2928 tus=1236 genrules=0 dirs=120)** — from
  0.2; the residual detectors are the 1 deliberate sink deliverable
  (`//:modules_builtin`, rate 0.0003) and the root's 1 open ask; both
  round away.
- **IMAGE green**: bzImage 2,417,664 B + initrd 2,623,909 B (the initrd
  now packed by the `initrd_cpio` rule).
- **BOOT-SSH OK after 3s: Linux 7.2.0** (port 2229, key
  `$ROOT/keys/id_ed25519`); qemu exited cleanly.

### (6) Invariants

- **INVARIANTS OK** (suites, vocabulary, corpus sweep with CORPUS=1):
  corpus **37 converged before, 37 after**; the 2 visible residual
  detectors (picocom/uhubctl: genrule_plumbing + include_flag_in_copts)
  are the known pre-existing corpus findings, unchanged by the tool
  changes. EXIT=0.
- **HERMETIC OK**: `//bazel/image:image` builds in a clean container —
  the `initrd_cpio` rule (new bzl file, new exec `script` attr) is
  hermetic-clean; EXIT=0.

## Verdict

**publish: release**

Every gate is green on the emit25 layer, at the run's target idiom
score:

| gate | result |
|---|---|
| parity build | GREEN, 0 errors |
| parity diff | converged, warnings=14 (the accounted floor) |
| parity artifacts | converged |
| idiom | **0.0** (threshold 5.2; was 0.2; rules 2928, genrules 0) |
| image | bzImage 2,417,664 B + initrd 2,623,909 B |
| boot | BOOT-SSH OK after 3s: Linux 7.2.0 |
| invariants | INVARIANTS OK, corpus 37 converged before and after |
| hermetic | HERMETIC OK (clean-container image build) |

Idiom motion this run (0.2 → 0.0, both remaining detectors now round
away):

- **manual_rules → ~0**: the emitter no longer emits a host tool whose
  binary nothing consumes (generic, in `plan_codegen`; the layer loses
  the two dead fixdep cc_binaries). The one remaining manual rule is
  `//:modules_builtin`, a deliberate sink deliverable the diff's
  extension-based relevance never demands — a rate of 0.0003 that
  rounds away, and the policy question ("drop every non-compile-input
  sink deliverable?") was rejected as dangerous for other projects'
  wanted deliverables.
- **todo → ~0**: the 15 identical "host tool builds with the exec
  toolchain" review asks are now answerable through a generic reviewer
  record, conventions **`host_tool_checked`** — verified by actually
  building all 13 remaining tools with the exec toolchain (250 actions,
  green) plus the 2026-10-23 clean-container build, then recorded in
  `conventions.json`. Root TODOs 16 → 1 (the genuinely open
  objtool-from-host hermeticity question on `vmlinux_o`).
- **genrules → 0**: the workspace's last genrule (`//bazel/image:initrd`)
  became the purpose rule `initrd_cpio` (`bazel/rules/initrd_cpio.bzl`),
  script-as-tool, every input declared, same action shape for parity.

Tool changes (wt-kernel, kbuild-intree): commit 933efe3 — dead-host-tool
skip in `plan_codegen` + `host_tool_checked` conventions field; 3 tests
added/extended, suites 130/130; docs updated. Layer changes: root BUILD
−2 dead cc_binaries −15 TODOs; `bazel/image/BUILD.bazel` genrule →
`initrd_cpio`; `conventions.json` +`host_tool_checked`; new
`bazel/rules/initrd_cpio.bzl`. No hand edits — everything went through
the emitter/rules/conventions, re-emit gate 2,321/2,322 identical
outside comments.

What is next (none of it this run's work, all recorded as residuals):

- diff.py: a `tree_recipe` tool stage could carry its inner tool's
  identity, which would dissolve the 2 auto_conf generator-swap
  warnings (content-verified; the emitter's own tool_map entry would
  overwrite a swap record today).
- The 7 `defines_diff` warnings on tools/lib/subcmd are the exec
  toolchain's opt defines (`-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=1
  -DNDEBUG`) vs the reference's; artifacts are converged, so this is
  cosmetic unless someone attacks the toolchain flags.
- Owner-side: `boot-ssh-test.sh` should retry on a free port (the
  2026-10-15 flake); shared scripts, not editable from here.
- include_flags/repeated-flags residues (~17/~20 instances) would need
  a `-isystem`-vs-`-I` mechanism with behavioral risk for a gain that
  no longer shows in the score.

With IDIOM 0.0 and all gates green, there is no idiom headroom left the
score can see; further runs should treat parity (warnings floor) as the
only remaining axis.

## Verdict

*(written at the end)*
