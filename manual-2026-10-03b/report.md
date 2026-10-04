# report — manual-2026-10-03b

*(draft; updated as the run proceeds)*

## State at run start
PARITY build=RED diff=NOT converged errors=76 warnings=22
artifacts=skipped(build red). The previous run (manual-2026-10-03) was cut
off after emitting v14 from its then-uncommitted tool work; that work was
the direct cause of both the 76 diff errors and the single red target.

## What changed (tool, wt-kernel)
- **committed b183c47** (the previous run's extractor work, suites green:
  180/180 capture): linker/archiver operands recovered from argv into
  traced inputs; inter-recipe objcopy/strip steps re-admitted when consumed
  (`dropped_bin`); VPATH tools subtree (objtool) mapped through the
  source/build overlay before the cwd test; `-Bsymbolic` kept a flag
  (`-B` value resolved only when it looks like a path); `-soname` pairs
  with its operand; recipe lines iterate until their operands' makers
  register. Golden `capture_ccache_strace` regenerated: the only delta is
  the intentional linker-operand enrichment (plus empty-input `mv` recipe
  lines, build_relevant=False, never emitted).
- **committed c9a7f6a** (the previous run's emitter work + this run's
  three fixes, suites green: 68/68 emit, 180/180 capture):
  - (prev. run) `toolchain_features`/`_deviates`/`keep_supply` feature
    inversion for the `-m16` families, `gen_archived`
    (cc_static_library for genrule-consumed aggregates), `_generator_tools`
    seeded with target-consumed producers, tool-name collisions by path,
    package-TU textual-include walk, `wired_gen`, root-reach narrowed to
    named generated files.
  - (this run) `_per_source_split` factors **units not tokens** — the
    `-include include/linux/compiler_types.h` pair split across C/S flag
    groups before, so the emitted line read `-include -D__KERNEL__` (64 of
    the 76 errors). Raw-link dep whose TUs split into flag groups: the
    parent's own TUs move under `<lib>_own` (cc_library) and the parent
    becomes `cc_static_library` over it + the groups — before, the link saw
    only note.o and every `__vdso_*` symbol was undefined (the one red
    target). `_generator_tools.pull` no longer swallows ConfigureFile
    producers on the queue path (glib-mkenums expand_template returned);
    the gate stays on the target-consumed seed path only.
- **layer**: BUILD.bazel re-emitted from the fixed extractor's model
  (v16); `models/kernel/model.capture.json` regenerated with the fixed
  extractor; the emitter's config-out is now copied back into
  `models/kernel/any2bazel.json` (the previous run never did, so its
  accepts were invisible to the parity diff).

## Parity now

- v33: `//:bzImage` BUILDS (2.4 MB); parity down from 76 errors to
  7 errors / 17 warnings — all errors generated-content diffs
  (voffset/zoffset/vdso64-image address deltas, .vmlinux.export.c modpost
  lines, autoconf.h rustc probe).
- v39–v41: the archive-recipe chain (see the iteration log) is
  analysis-clean end to end; the last execution failure is the vmlinux.o
  LINK opening THIN `vmlinux.a` (a `cat` copy of thin `built-in-fixup.a`)
  whose leaf members are not in the link's sandbox.
- **v42 — `PARITY build=GREEN diff=NOT converged errors=6 warnings=17
  artifacts=converged 0 errors`**: the first GREEN full-tree build with
  the ar-recipe chain (the fix: `_thin_leaves` — a consumer that OPENS a
  thin archive, directly or through a `cat`/`cp` copy, gets the archive's
  transitive leaf members declared as srcs). Artifact diff converged with
  0 errors: realmode.elf, setup.elf, the compressed `vmlinux` and
  `vdso64.so` match the reference on symbols/weak symbols/soname/needed.
- Residual diff (6 errors / 17 warnings, all reviewed):
  - `generated_content_diff` x4: `arch/x86/boot/voffset.h` +
    `zoffset.h` address deltas (our vmlinux layout shifts by 0x1000 vs
    the reference's), `vdso64-image.c` byte deltas (the vdso image the
    reference embedded), `autoconf.h` 4 config lines (the sandbox `conf`
    probe saw no rustc → `CONFIG_RUSTC_*_VERSION 0`).
  - `generated_tool_diff` + `generated_args_diff` (autoconf.h, same
    root cause): the reference runs in-tree-exe `scripts/kconfig/conf`,
    we run the `//:auto_conf` genrule; the `--syncconfig Kconfig` args
    are unmodeled on the bazel side.
  - warnings: `defines_diff` x7 (`NDEBUG`/`_FORTIFY_SOURCE=1` bazel-only
    on the tools/lib/subcmd host tool), `extra_tu` x5 (nested-make
    compiles: gdt_idt, map_kernel, version-timestamp, empty.c,
    .vmlinux.export.c), `extra_target :fixdep`, `extra_generated`
    (compressed/voffset.h), `generated_unrecorded` x3 (kconfig
    lexer.lex.c/parser.tab.c/.h — circular committed-copy check;
    accept via codegen_map "committed").
  - The v39 `missing_tu x388` regression is GONE (the unmark cascade).

## Acceptance

- `build-image.sh`: `IMAGE: 2413568 /scratch/bluecmd/linux-bzl/image/bzImage`.
- `boot-ssh-test.sh` (QEMU/KVM, initrd, SSH): **`BOOT-SSH OK after 3s:
  7.2.0`** — both on the direct bazel-out bzImage and on the canonical
  image. The net/netlink/built-in.a member order (af_netlink, genetlink,
  policy — the initcall-order fix from the ar-recipe chain) is confirmed
  live: the BUG_ON(!nl_table) panic the merged-order aggregate produced is
  gone.

## Tool state (wt-kernel, to commit with this run)

- extractor: `ar` move ops (`mPi` edit steps) recorded as actions on the
  archive (the built-in-fixup.a `mPi init/main.o` front-move is in the
  model).
- emitter: ar-recipe genrules for archives read by name (members in
  reference order = link order); empty member lists reproduce the recipe
  verbatim (kbuild's `cDPrST` on every visited dir); skip-vs-fail rule for
  members outside the emitted scope; nested-thin leaf srcs for ar parents;
  `_thin_leaves` consumer pull for thin archives read by links/copies;
  `$(AR)` anchored as `$$A2B_AR` (exported before the `cd $(GENDIR)`);
  cc_object_files lib naming fixed (target name / `<name>_static`).
- Suites green at every step: 74/74 emit (one new test:
  `test_thin_archive_consumer_declares_the_leaf_members`), 180/180
  capture.
- Post-verdict corpus sweep (optional invariant) caught an 18-package
  regression inherited from c9a7f6a: the scoped generated-header
  libraries' reach walk dropped configure/expand_template outputs (their
  label has no path — bash's `config.h: No such file or directory`).
  Fixed in 538096b (all_gen adds template-mode header paths) with a
  regression test that only bites on the scoped path (75/75 emit,
  180/180 capture, CORPUS=1 sweep 37/37 converged). v43 re-emission with
  the fix is byte-identical to the installed v42 BUILD + config, so the
  released kernel build and boot evidence stand unchanged.

## Verdict

`publish: release` — main = v7.2 + one Bazel-layer commit; the layer's
bzImage builds GREEN from //..., the recorded artifacts converge with the
reference (0 errors), and the boot test passes (QEMU/KVM + SSH, 3 s to
`uname -r` = 7.2.0). The 6 remaining diff errors are reviewed
generated-content deltas on four known files (voffset/zoffset/vdso64-image
addresses, autoconf.h rustc probe) with the boot and artifact evidence on
the other side.
