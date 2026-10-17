# report — 2026-10-17

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=**RED** — new since 2026-10-15: the layer's initrd pins Alpine
v3.22 main apks by hash in MODULE.bazel, and Alpine dropped
`zlib-1.3.2-r0.apk` from the CDN (superseded by `-r1`); a fresh fetch 404s
(`/…+http_file+apk_zlib//file` — "GET returned 404"). The other 7 pins still
resolve; the diff itself still reads errors=6 warnings=12 (the accepted
baseline: 4 generated-content diffs + the conf→auto_conf tool/args pair)
because it compares recorded models, but `artifacts=skipped(build red)`.
IDIOM 0.3 (threshold 5.2). Layer clean at 136983ac4; any2bazel kbuild-intree
at dc0f877 (now carrying the freebsd loop's 2026-10-16 tool work: emitted
config_template, codegen.tool_map, replay_stages waiver).

## Plan

plan.md — unblock the fetch, restore green, then apply the emitted-config
mechanism the freebsd loop proved, and attack the 6 residual errors.

## Journal

journal.md in this directory, updated as steps land.

## What landed

**1. zlib apk rot unblocked (layer, MODULE.bazel).** `apk_zlib` bumped from
`zlib-1.3.2-r0` to `zlib-1.3.2-r1`, sha256 af24e502645e2b392cae833856d776691
ac21655362e5db69d7b89f147f76216 (downloaded + hashed by this run). No other
pin affected; `//bazel/image:image` builds green again. Not a hand-edit of an
emitted file — MODULE.bazel is layer content.

**2. ld-order tie-break in the emitter (tool, wt-kernel).** TU order inside
and across flag-group pieces follows the target's recorded ld order
(`_ld_stem`/`_ld_src_key`/`_group_tus`/`_plan_one`); 121/121 with the new
tie-break test. Re-emit (emit40) + install: realmode.elf_objs and the vdso64
pieces now compile in the reference's link order; parity 6 → 5
(voffset_h converged), IDIOM 0.3, artifacts converged 0, build GREEN.

**3. Raw-link flag groups spell per piece in the ld order (tool).** The
emitter no longer invents a cc_static_library aggregate over the flag-group
libraries for raw-link targets — Bazel merges a cc_static_library's deps'
objects in its topological (dependents-first) order, which scrambled the
vDSO layout ([note, chacha, vgetrandom, vgetcpu, vclock] vs the reference's
ld order [note, vclock, vgetcpu, vgetrandom, chacha]) and shifted
vdso64-image.c. The cc_raw_link now spells each group's carrier
`--whole-archive $(location :piece) --no-whole-archive` where the reference
linked its object (a stem shared by two groups still falls back to the
aggregate). `objects_lib_of` maps to `<lib>_objs_own` in the per-piece path
so cc_object_files still finds member objects. 122/122 with the new
per-piece-spelling test.

**4. autoconf.h CONFIG_RUSTC_* accepted in config (conventions).** The conf
replay's rustc probe is environment-dependent: the reference ran
`RUSTC=rustc` (rustc 1.94.1 / LLVM 21, then on the build shell's PATH);
since then rustup has moved the tool to 1.99.1 / LLVM 23, and the layer's
probe PATH (`/bin:/usr/bin:/usr/local/bin`, bazel-probe.json) has no rustc
at all — the replay writes `CONFIG_RUSTC_LLVM_MAJOR_VERSION 0`. A host
probe of a tool the layer does not build is not layer content; recorded as
`config_template.codegen.content_ignore_lines = ["^#define CONFIG_RUSTC_"]`
in linux/conventions.json (the freebsd loop's mechanism), so the differ
drops the probe's lines on both sides.

**5. The wall-clock pins (replay_env + replay_args, tool).** The last
zoffset component was the tree-packing generator's stamp:
`usr/gen_init_cpio` defaults its entry mtime to `time(NULL)` — the
reference's moment (22:25:41 UTC, epoch 1790979941) survives only in the
recorded OUTPUT bytes, not in the recorded argv, and `usr/Makefile`'s own
pin (KBUILD_BUILD_TIMESTAMP → `-d`) carries a different moment (00:30:11
CEST, the utsversion stamp, 4.5 min later), so the env pin alone cannot
reach it. Two knobs, both generic, both reviewer-recorded in
linux/conventions.json:
- `replay_env` — env pairs merged into the common recipe env (rides
  COMMON_ENV and every rule's env_map): KBUILD_BUILD_VERSION/TIMESTAMP,
  so the replayed link's inner make (link-vmlinux.sh:176 re-runs
  `make obj=init init/version-timestamp.o`, whose filechk re-expands
  `$(shell date)`) reads the reference's recorded stamp instead of the
  wall clock. 123/123 with the pins-ride-the-recipe-env test.
- `replay_args` — recipe words appended to a replayed generator's line,
  keyed by the recipe's output path: `usr/initramfs_data.cpio: ["-d",
  "@1790979941"]` — the reference's own generator moment as an epoch
  (`date -d @N +%s` is TZ-independent); `usr/default_cpio_list` is 2
  `dir` + 1 `nod` entries, so forcing the default mtime cannot disturb
  a file entry's recorded mtime. 124/124 with the words-append test.
  Differ-side the appended words are bazel-only (`b_extra`) — only
  cmake_only args error, so the pair stays clean.

**6. Lane toolchain builtin-include repair (corpus lanes, shared).** The
CORPUS=1 sweep exposed a pre-existing corpus defect, not a tool change: the
lane `cc_toolchain_config.bzl` declared builtin include dirs under
`/home/bluecmd/any2bazel/toolchain` while the real files have lived at
`/scratch/any2bazel/toolchain` since the Sep 25 symlink rework — fresh
linux-sandbox compiles fail Bazel's builtin-include check, and the corpus's
converged rows since Sep 29 rode stale action-cache entries. Proven
independent of this run's tool work by a control run with the committed
tool (dc0f877): identical failure, and the corpus's own Sep-29 seed BUILD
fails the same way. Repair (base ws + lanes 0–3, byte-identical; another
session applied the same shape at 04:28 — the lanes are shared state):
keep the capture-recorded `/home` root for the include surface AND declare
the real `/scratch` tree (`REAL_ROOT`) as builtin too, so whichever path
the compiler resolves through is covered and the include roots stay the
captures'.

## Results

**PARITY (emit43, converged):** build=GREEN diff=converged errors=**0**
warnings=14 artifacts=converged 0 errors, IDIOM score=0.3 (threshold 5.2)
— 3126 rules, 1236 tus, 1 genrule, 120 dirs. The last residual (zoffset_h)
closed when both wall-clock pins landed: the 38-byte gap (20 B build-id +
18 B cpio entry mtimes) followed the stamp, since the build-id hashes the
link inputs, the xz'd piggy size follows the cpio, and zoffset.h follows
the layout. Remaining warnings all explained, pre-existing: defines_diff
x7 (NDEBUG/_FORTIFY_SOURCE), extra_tu x5, conf→auto_conf tool/args pair
x2 (content-verified WARN).

**BOOT-SSH: OK after 3s** — `Linux 7.2.0` (KVM, port 2223), from
`bazel build //bazel/image:image` + boot-ssh-test.sh on the layer's
bzImage/initrd.

**HERMETIC: OK** — //bazel/image:image builds in the clean
ubuntu-24.04 runner container (fresh output base, read-only tree).

**CORPUS: 37 converged before, 37 after — INVARIANTS OK.** Formal
CORPUS=1 check-invariants pass (suites + vocabulary + 37-package corpus
sweep, lanes 4, absolute worktree path). Category tally back to its
pre-run shape; the 2 build:absolute_inclusion and 2 diff:includes_diff
rows that moved are the lane toolchain repair above, with the moved rows
honestly fresh-built.

**Tool change committed:** wt-kernel 90bd5a5 ("emit_build: ld-order
tie-break, per-piece raw-link spelling, replay_env, replay_args") on
kbuild-intree, after check-invariants (suites + vocabulary + corpus)
passed. Post-commit determinism re-emit (emit44): byte-equal to emit43.

## Verdict

**publish: release** — parity CONVERGED (0 errors, 14 explained
warnings, artifacts converged 0, IDIOM 0.3), bzImage + initrd boot and
accept SSH, hermetic runner build green, corpus 37/37 converged, tool
change committed with all suites green.

## Notes for the owner

- **Corpus lane toolchain template**: the REAL_ROOT repair (item 6) is
  applied to the base ws + lanes 0–3; it belongs in whatever template
  future lane generation uses, or the next symlink move re-breaks fresh
  builds.
- **check-invariants quirk**: a CORPUS=1 pass computes before/after from
  results.tsv rows with `$2=="converged"` — an empty package list (e.g.
  after a failed rerun wiped the rows) gives 0 before / 0 after and
  corpus.py's rerun errors on the empty list, yet the gate still prints
  INVARIANTS OK (vacuous pass). Worth a guard.
- **podman arm64 flake**: hermetic-build.sh's `podman pull` resolved
  ubuntu:24.04 to linux/arm64 on this host ("Exec format error"); the
  script should pin `--platform linux/amd64` (or the runner image).
