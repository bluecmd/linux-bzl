# journal — 2026-10-17

## 01:05 — baseline restored (zlib apk rot)

- PARITY build=RED at start: Alpine dropped `zlib-1.3.2-r0.apk` from the CDN;
  the layer's `apk_zlib` http_file pin 404'd. Bumped to `zlib-1.3.2-r1`,
  sha256 af24e502645e2b392cae833856d776691ac21655362e5db69d7b89f147f76216.
  PARITY restored: build=GREEN errors=6 warnings=12 artifacts=converged 0,
  IDIOM 0.3 — exactly the 2026-10-15 accepted baseline.
- Root-caused the 4 generated-content errors + 2 of the tool/args pairs
  (the earlier session's work, carried in): the emitter orders flag groups,
  within-group sources, and split pieces by name/size heuristics while the
  reference's link order is recorded — an archive's member order is the
  link's layout order. Consequences measured downstream:
  realmode.elf links reboot.o before trampoline_64.o (the reference puts
  trampoline_64.o right after header.o) → the 4096-aligned trampoline text
  after other text inserts a 0xcc gap (~0xf00) → realmode.bin 20516→24608 B
  → vmlinux `.init.data` +0x1000 → voffset.h/zoffset.h all shift; and
  vdso64.so links vgetrandom-chacha.o before vgetrandom.o → `.text` 0x96c
  vs 0x96b → vdso64-image.c differs.

## 01:20 — ld-order tie-break in the emitter (tool, uncommitted)

emit_build.py (wt-kernel, on kbuild-intree @ dc0f877):
- `_ld_stem` / `_ld_src_key`: a TU source is keyed by its position in the
  target's recorded ld order (`_ld_o_order`, memoized: walk the target's
  CppLink action's inputs, keep `.o`, stem-keyed; None when there is no
  link, no .o inputs, or a stem appears twice), name as the tie-break.
- `_group_tus(tus, ld_order)`: same-size groups now order by the ld index
  of their first TU (was: first-seen ties resolved by sorted source name);
  within-group sources likewise; unlinked targets keep the name order.
- `_plan_one`: per-source branch's `p["srcs"]` and the split-pieces deps
  order follow the same key.
- Not touched: the package_split site (`tus=sorted(tus_, ...)`) and the
  static_tus grouping — corpus regression risk kept for later, deliberate.

Test: `test_ld_order_tiebreaks_the_per_source_sources` (tests/
test_emit_build.py): same-size groups whose recorded ld order disagrees
with name order (cmdline.o before a20.o) — the per-source library's srcs
follow the ld order; a link without .o inputs keeps the name order.
**121/121 passed.**

## 01:40 — re-emit + install (emit40)

- Re-emit command recovered from the manual-2026-10-03b session transcript
  (`/tmp/emitcmd.txt` was a self-referential recovery script, useless):
  `cd /scratch/bluecmd/linux-bzl && python3 …/emit_build.py
  models/kernel/model.capture.json --config models/kernel/any2bazel.json
  --conventions linux/conventions.json --out /tmp/all-emit40/BUILD.bazel
  --config-out /tmp/all-emit40/any2bazel.json` (9m26s, 0 TODOs).
- `/tmp/diff-emit.sh /tmp/all-emit40`: exactly 5 BUILD files differ from
  the installed layer, all orderings (root TODO/deps, arch/x86/boot,
  boot/compressed, vdso64, realmode/rm); 2322 BUILD files, same set as
  the layer (verified: HEAD-minus-handwritten == emit39 == emit40).
- Spot-check: realmode.elf_objs srcs now `header.S, trampoline_64.S,
  stack.S, reboot.S` = the reference ld order; vdso64_so pieces
  vclock_gettime → vgetcpu → vgetrandom → vgetrandom_chacha = the
  reference ld order.
- Install lesson: `install-emit.sh` takes EMIT from the env, not $1 — the
  first call ran with the stale /tmp/all-emit default and half-installed;
  re-ran cleanly with `EMIT=/tmp/all-emit40`. After the clean install the
  tree differs from HEAD by exactly those 5 BUILD files + MODULE.bazel.
- Parity gate running (bj48j0yzo).

## 02:20 — parity 6→5, remaining errors triaged

- Parity (emit40): build=GREEN errors=5 warnings=12 artifacts=converged 0,
  IDIOM 0.3. voffset_h converged; gone are realmode's errors. Left:
  zoffset_h, vdso2c (vdso64-image.c), autoconf.h (all generated_content_diff)
  + 12 warnings (defines_diff x7 NDEBUG/_FORTIFY_SOURCE, extra_tu x5 —
  pre-existing, WARN class).
- zoffset_h: INHERENT, not a layer defect. The reference's .rodata carries
  `linux_banner` with a live build stamp (`#1 SMP PREEMPT Sat Oct  3
  00:30:11 CEST 2026` from mkcompile_h replay / the .version counter);
  a fresh build stamps its own time (`#2 … Sat Oct 17 01:17:13`), the xz'd
  piggy size changes by 24 B, ZO_* shift. Byte-level proof: vmlinux.bin
  same size (12226560 B), 3008 differing bytes = the banner string +
  cascades; z_input_len 0x243214 vs 0x24322c (+0x18).
- vdso64-image.c: REAL, established above — the invented
  cc_static_library aggregate (vdso64_so_objs) merges the pieces in
  Bazel's topological (dependents-first) order [note, chacha, vgetrandom,
  vgetcpu, vclock] instead of the reference's ld order [note, vclock,
  vgetcpu, vgetrandom, chacha] → .text 0x96b vs 0x96c. Deps-arrangement
  experiments (forward vs backward chain) cannot fix it: the chain that
  reverses the archive also inverts the pieces' relative order.
- autoconf.h: 8 CONFIG_RUSTC_* host-probe lines the conf→auto_conf replay
  cannot reproduce (the reference probed the live rustc). Plan: recorded
  `codegen.content_ignore_lines` decision, which also G2-downgrades the
  conf→auto_conf tool/args pair.

## 02:35 — raw-link flag groups spell per piece in the ld order (tool)

emit_build.py (wt-kernel, `_render_raw_link`):
- The flag-group branch no longer invents a cc_static_library aggregate
  `<lib>_objs` over `<lib>_own` + the groups (Bazel's topological merge
  order would scramble the layout — the vdso64-image.c root cause).
  `<lib>_own` keeps the main group's TUs; the link (cc_raw_link) spells
  each group's carrier `--whole-archive $(location :piece)
  --no-whole-archive` where the reference linked its object: the
  fallback loop visits `link.inputs` in the ld order, and
  `grp_piece` (source stem → own/piece carrier) resolves each own object.
- A stem two groups share (the map cannot say which piece compiles it)
  falls back to the aggregate (`grp_ok = False`); only that path still
  emits a cc_static_library.
- `objects_lib_of[name]` maps to `<lib>_objs_own` (not the now-absent
  aggregate) in the per-piece path, so cc_object_files still finds the
  member objects a recipe reads.
- Test: `test_raw_linker_flag_groups_spell_each_piece_in_the_ld_order`
  (3 TUs, one with 13 extra defines → flag groups; ld order vdso.o,
  a20.o, cmdline.o) — the link spells own → a20 → cmdline in that order,
  each `--whole-archive`-wrapped, no cc_static_library.
  **122/122 passed.**

## 02:50 — parity 5→1 (emit41): vdso2c + autoconf converged

- emit41 install + parity: build=GREEN errors=**1** warnings=14
  artifacts=converged 0, IDIOM 0.3. The cc_raw_link spells
  own → vclock_gettime → vgetcpu → vgetrandom → vgetrandom_chacha
  (the reference ld order); vdso64-image.c converged. autoconf.h
  converged with the recorded `content_ignore_lines` (`^#define
  CONFIG_RUSTC_`); the conf→auto_conf pair downgraded to
  `generated_tool_diff` WARN ("content verified: warning") — G2 as
  expected. warnings went 12 → 14: the two content-verified pairs now
  WARN instead of hiding in the error count.
- The one error left is zoffset_h — the live banner stamp. Root cause
  (deeper than "inherent"): init/Makefile's `filechk_uts_version` picks
  `build-timestamp = $(or $(KBUILD_BUILD_TIMESTAMP), $(shell date))` and
  `build-version = $(or $(KBUILD_BUILD_VERSION), $(shell
  scripts/build-version))` — and `scripts/link-vmlinux.sh:176` re-runs
  `make obj=init init/version-timestamp.o` AT LINK TIME, whose FORCE rule
  re-expands `$(shell date)` live in the mirrored tree. The layer's
  `utsversion_h` stamp already carries the reference's recorded values
  (`#1 SMP PREEMPT Sat Oct  3 00:30:11 CEST 2026` — built file byte-equal
  to the ref's), but the mirrored link's inner make regenerates its own:
  the linked vmlinux carried `#2 … Oct 17 02:30:37` (the link moment)
  while every version-timestamp.o in bazel-out carries `#1 … Oct  3`.
  The kernel's own reproducible-builds knobs (used ONLY by init/Makefile,
  verified) pin it.

## 02:55 — replay_env pins in the emitter (tool)

emit_build.py (wt-kernel):
- Conventions `replay_env` (dict): env pairs the reviewer pins on every
  recipe replay, merged into the common recipe env (`_common_env`) — so
  kbuild_env.bzl's COMMON_ENV, the `_RECIPE_ENV`/`_COMMON_ENV` constants,
  and every rule's `env_map` carry them, and the replayed link's inner
  make reads KBUILD_BUILD_TIMESTAMP / KBUILD_BUILD_VERSION instead of
  the wall clock.
- linux/conventions.json records the decision:
  `KBUILD_BUILD_VERSION: "1"`, `KBUILD_BUILD_TIMESTAMP: "Sat Oct  3
  00:30:11 CEST 2026"` (the reference's recorded stamp, as the layer's
  own utsversion_h stamp already spells it).
- Test: `test_replay_env_pins_ride_the_recipe_env` — the pins appear in
  the emitted env even when the model's generators share no env.
  **123/123 passed.**

## 03:05 — replay_args: the last zoffset component (tool)

- The remaining zoffset drift is the tree-packing generator's stamp
  (usr/gen_init_cpio's `default_mtime = time(NULL)`; its 3 dir/nod
  entries carry the reference's 0x6AC02F65 = 22:25:41 UTC vs bazel's
  live 01:06:46). The recorded argv has no date flag, so the env pin
  cannot reach it — and `usr/Makefile`'s own `cmd_initfs` shows the
  value the pin would carry is a DIFFERENT moment than the reference's
  actual generator run: 00:30:11 CEST (1790980211, the utsversion
  stamp) vs 00:25:41 CEST (1790979941) — so `-d
  "$(KBUILD_BUILD_TIMESTAMP)"` would still drift. The recorded OUTPUT
  is the only place the reference's generator moment survives.
- Mechanism: conventions `replay_args` — recipe words the reviewer
  appends to a replayed generator's line, keyed by the recipe's output
  path. emit_build.py (wt-kernel): `_replay_args_of(outs)` + the words
  appended to `toks` in `_emit_genrule` before the tree_recipe /
  genrule rendering (both shapes ride the same list); each word goes
  through `_shell_word`. Mid-line words, so the recipe-prog review is
  untouched; the savedcmd/stamp recognizers still see the line with the
  words in it (a keyed recipe whose shape match would break falls back
  to the tree_recipe).
- linux/conventions.json records the decision:
  `usr/initramfs_data.cpio: ["-d", "@1790979941"]` — the reference's
  own generator moment as an epoch (`@`), TZ-independent through GNU
  date's `date -d @N +%s` round-trip; `usr/default_cpio_list` is 2 dir
  + 1 nod entries, so forcing `default_mtime` via `-t` cannot disturb a
  file entry's recorded mtime (do_file_mtime only affects file entries
  when they exist).
- Differ-side: only `cmake_only` generator args error; the appended
  words land in `b_extra`, which rides the detail without a
  discrepancy — the pair stays clean, no G2 downgrade needed.
- Test: `test_replay_args_words_append_to_a_replayed_recipe` — the
  tree_recipe recipe line ends with the appended words; knob off, the
  same recipe keeps the reference's words only. **124/124 passed.**
  check-invariants.sh wt-kernel: OK.

## 03:40 — CONVERGED (emit43)

- emit43 (9m4s, 0 TODOs): exactly one BUILD file differs from the
  layer — usr/BUILD.bazel, the recipe line's appended words. Install +
  parity:
  **PARITY build=GREEN diff=converged errors=0 warnings=14
  artifacts=converged 0 errors, IDIOM 0.3.**
- The appended words stayed warning-free (14, unchanged): the tree
  packing generator's pair has no cmake_only args, so the epoch lands
  in `b_extra` only. zoffset_h converged — the 38-byte residual (20 B
  build-id + 18 B entry mtimes) closed once the stamp matched: the
  build-id hashes the link inputs, the xz'd piggy size follows the
  cpio, zoffset.h follows the layout.
- Remaining warnings (all explained, pre-existing): defines_diff x7
  (NDEBUG/_FORTIFY_SOURCE, WARN class), extra_tu x5, and the
  conf→auto_conf tool/args pair x2 downgraded by
  content_ignore_lines.

## 03:50 — boot-ssh OK; hermetic + corpus environment flakes

- **BOOT-SSH OK after 3s: `Linux 7.2.0`** (KVM, port 2223): `bazel build
  //bazel/image:image` (all cache hits — parity already built it) +
  boot-ssh-test.sh on the layer's bzImage/initrd.
- Hermetic first attempt FAILED in the harness environment, not the
  layer: podman resolved `docker.io/library/ubuntu:24.04` to **arm64**
  ("image platform linux/arm64/v8 does not match"; `exec /usr/bin/bash:
  Exec format error`). Retrying after `podman pull --platform
  linux/amd64` (inspect: linux/amd64).
- Corpus sweep first attempt FAILED in the harness invocation, not the
  tool: I passed the worktree as the RELATIVE name `wt-kernel` — the
  lanes resolved A2B to
  `/scratch/any2bazel/wt-kernel/wt-kernel/scripts` (extract:crash for
  all 37) and rewrote results.tsv's converged rows with crash entries;
  a second CORPUS=1 pass was vacuously OK (0 before / 0 after — and
  corpus.py's rerun errors on an empty package list while
  check-invariants still reports OK). Lesson: pass the worktree as an
  absolute path. Re-running the 37 packages directly with the absolute
  A2B_SCRIPTS to restore their rows; a formal CORPUS=1 pass follows.
- **HERMETIC OK** (after the amd64 pull): //bazel/image:image builds in
  the clean ubuntu-24.04 runner container.
- Corpus absolute_inclusion root-caused (NOT this run's tool change):
  with the tool at the last committed state (dc0f877 — control run,
  /tmp/wt-committed) argp-standalone fails identically, and even the
  corpus's own Sep-29 seed BUILD fails the same way — the lane
  toolchain's `cc_toolchain_config.bzl` declared builtin include dirs
  under `/home/bluecmd/any2bazel/toolchain` while the real files live
  at `/scratch/any2bazel/toolchain` (the Sep 25 symlink rework). Fresh
  sandbox compiles fail Bazel's builtin-include check; the corpus's
  converged rows since Sep 29 rode stale action-cache entries, and
  today's fresh reruns exposed it. Pointing lane 0's TOOLCHAIN_ROOT at
  the real path makes the compile run fresh and green (8 linux-sandbox
  actions, build OK) — mechanism confirmed. The template (base ws +
  lanes) now spells the real path; re-running the 37 to restore their
  rows honestly.
- But the repair flipped the OTHER side: the lanes' `-I` now spelled
  /scratch while the corpus captures (Sep 28/29) recorded the /home
  view → 37 `diff:includes_diff` (cmake_only /home/.../include/fortify
  vs bazel_only /scratch/.../include/fortify). The consistent template
  keeps the capture-recorded /home root for the include surface AND
  declares the real /scratch tree as builtin too (`REAL_ROOT`
  alongside `TOOLCHAIN_ROOT` in `cxx_builtin_include_directories`) —
  whichever path the compiler resolves through is covered, and the
  include roots stay the captures'. Note: another session repaired the
  lanes/base ws the same way at 04:28 (all five configs byte-identical
  now) — the corpus lanes are shared state; verified identical before
  the re-run.

## 05:10 — all gates green; tool change committed

- Formal CORPUS=1 check-invariants pass (absolute worktree path):
  **corpus 37 converged before, 37 after — INVARIANTS OK** (suites +
  vocabulary + 37-package sweep). All four gates green: parity
  CONVERGED (emit43), boot-ssh OK, hermetic OK, corpus 37/37.
- Tool change committed: wt-kernel **90bd5a5** ("emit_build: ld-order
  tie-break, per-piece raw-link spelling, replay_env, replay_args") on
  kbuild-intree. Control worktree /tmp/wt-committed removed.
- Post-commit determinism re-emit (emit44): 9m40s, 0 TODOs —
  **byte-equal to emit43** (diff -r clean) and clean against the
  installed layer (/tmp/diff-emit.sh exit 0). The committed tool
  reproduces the converged emit exactly.


