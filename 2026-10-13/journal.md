# linux convergence run 2026-10-13 — journal

Baseline on entry (parity-before.txt, full gate): `PARITY build=GREEN
diff=NOT converged errors=6 warnings=15 artifacts=converged 0 errors`,
`IDIOM score=5.2 rules=3125 tus=1243 genrules=1 dirs=119`. errors=6 are the
four known nondeterministic-content files (voffset_h, zoffset_h,
vdso64-image.c, autoconf.h); warnings are the known classes (defines_diff
x7 NDEBUG/_FORTIFY_SOURCE, extra_tu x5, generated_unrecorded x3).

## Phase 1 — purpose-built rules for the shaped recipe lines (owner item 1)

The wrap spike (`bazel/rules/wrap_header.bzl`, 26 hand-converted calls in
arch/x86/BUILD.bazel) validated the design: a purpose-built rule converges
iff its action's kept stages are identical, post-keying, to the reference
action's — the differ already drops the glue (echo/trap/mkdir/mv/exit/
touch/'[') and the `.cmd` bookkeeping lines, so the rule needs only the
meaningful stages.

Ground truth for all 67 `tree_recipe` instances extracted from
model.capture.json kept-stage reduction (/tmp/ref-stages.txt). Phase-1
kinds = 46 instances:

- wrap 26 — `echo '#include <generic>' > out`, no inputs → `wrap_header`
- copy 6 — `cat src > out` (shipped files, vmlinux.a, initramfs_inc_data)
  → `copy_file`
- objcopy 7 — direct `llvm-objcopy opts in out` (realmode/setup/boot &
  compressed vmlinux.bin/gdt_idt.pi.o/map_kernel.pi.o/vdso64.so)
  → `objcopy` (tool = @kernel_llvm//:bin/llvm-objcopy, args attr)
- offsets 4 — Kbuild's `sed-offsets` + cmp/mv stamping (asm-offsets.h,
  bounds.h, rq-offsets.h, devicetable-offsets.h) → `offsets_header`
- chksha1 3 — the atomic headers' CHKSHA1 markers → `chksha1`

Mechanism, generic in the emitter:
- conventions `recipe_kinds: {kind: {load, rule}}`; recognizers
  `_emit_kind_<kind>` in emit_build.py called from `_emit_genrule_in_cwd`
  right after the `ar_archive` try. Each matches the reference ACTION's
  kept stages (`codegen.command_stages` — the same reduction the differ
  makes), never the recipe text; anything it cannot see plainly stays a
  tree_recipe. Emission follows `_emit_ar_archive_rule`'s pattern (load +
  Rule + `_register_genrule_outs`, `manual` tags kept, the tool@backtrace
  comment line kept).
- All new rules keep the action mnemonic `Genrule` — zero changes to the
  aquery capture filter or `any2bazel.json` `codegen.mnemonics`; idiom
  counts genrule rule CALLS in BUILD text, and there are none.
- Rules added under bazel/rules/: copy_file.bzl, objcopy.bzl,
  offsets_header.bzl (Kbuild's `sed-offsets` verbatim), chksha1.bzl.

Decision, applied: vmlinux_a (the cat of built-in-fixup.a) is an
`ar_recipe`-routed action that also matches the copy shape — it converts
to `copy_file` too (its ~200 object srcs were staging for the ar path and
are not needed; the rule's only input is the fixup archive). The parity
gate is the oracle.

First conversion emit (emit18/19): the kinds landed in exactly the 8
expected files (arch/x86 862, root 347, boot/startup 188, boot 85,
compressed 46, vdso64 42, scripts/mod 41, realmode/rm 41) with correct
respelled `src` values (`//arch/x86/kernel:asm-offsets.s`, `//:vmlinux`,
`//arch/x86/boot/compressed:vmlinux`, `vdso64.so.dbg`); the other ~2085
differing files are only the 4 new global load lines (the emitter's
known wart: `_package_text` writes the global loads into every package).

Two emitter findings on the way:

- The `copy` kind initially fired 0 times. Two causes, both fixed:
  (a) `cat` of a shipped file is recorded with the input under the
  pristine source root (`/src-ref/...`) while the extractor's `inputs`
  list carries the build-root twin — `_kind_path` now maps a token under
  `source_root` to `build_root`-joined, the same mapping the extractor
  applied; (b) the trailing `printf ... > .x.cmd` bookkeeping stage made
  `command_stages` return 2 stages for initramfs_inc_data/vmlinux_a —
  `_bookkeeping_stage` moved from diff.py into codegen.py as
  `bookkeeping_stage` (public) with a `kept_stages` helper, shared by the
  differ (its two call sites) and the recognizers, so both sides apply
  one reduction.
- The deps flips seen between emits (lib/crypto, lib/crc,
  drivers/tty/vt, arch/x86/tools — one `//<pkg>:<pkg>_headers` line
  moving by one line) traced to `_package_headers_libs` iterating
  `rule_need.get(r.name, set())` — a set; now `sorted()`. (PYTHONHASHSEED
  pinning alone does not pin set-of-str order across the process the way
  an explicit sort does.) Inert either way — deps order is not compared.

With those fixed, emit22 == emit23 byte-for-byte (`diff -rq` clean): the
emitter is deterministic again. Installed emit22 over the layer (the
install also replaces the 26 hand-edited wrap calls — the emitter now
produces them itself).

One gate cycle lost to a Starlark restriction: the rule modules'
multi-line `command = ("a " "b ") % (...)` used implicit adjacent-string
concatenation, which Bazel's parser forbids — 2115 build errors, 1105
missing_tu in the diff (aquery saw no loaded package). Fixed with `+`
concatenation in offsets_header.bzl/chksha1.bzl; `bazel query` on one
consuming target confirms the modules load. Lesson: every new .bzl gets
a `bazel query` smoke before a gate.

## Phase 2 — owner item 3, per-package boilerplate (2026-10-13, after phase 1)

Two emitter changes, both text-only (the aquery model is untouched, so the
gate cannot see them except through BUILD content):

- **Load only used lines.** `self.loads` is collected globally (a rule loads
  while it is emitted, wherever routing puts it), and `_package_text` wrote
  the union into every BUILD — 25020 load statements across 2322 files, most
  of them dead (26k dead symbol instances: `chksha1` loaded in 2084 files
  that use none). `_loads_text(body)` now keeps a load only for symbols the
  package's own body names; the body is exactly the text written, so the
  filter errs toward keeping — usage implies occurrence, under-retention is
  impossible. 2761 load lines remain (emit24: all 2085 diffs vs emit22 are
  load-line-only).
- **The shared recipe environment is one module, not BUILD content.** Every
  env-bearing package carried the ~2KB `_COMMON_ENV` dict plus a `dict(
  _COMMON_ENV, ...)` diff (16 packages after phase 1's conversions). New
  conventions key `env_module: {bzl, symbol}`: the emitter writes the dict
  once into `bazel/rules/kbuild_env.bzl` (new `extra_files` channel beside
  `extra_builds`, written by `emit()`), packages `load("...kbuild_env.bzl",
  "COMMON_ENV")` and spell `dict(COMMON_ENV, ...)`. The symbol cannot keep
  the private `_COMMON_ENV` name (a load cannot carry an underscore symbol).
  Without the conventions key the emitter keeps the per-BUILD constant —
  the corpus sees no change.

Gate: `PARITY build=GREEN diff=NOT converged errors=6 warnings=15
artifacts=converged 0 errors`, `IDIOM score=5.2` — exact baseline. Suites
92/92. Lesson kept: `python3 -I tests/test_emit_build.py` fails
`test_meson_archives...` with ModuleNotFoundError (sibling import); run it
without `-I` from tests/.

## Phase 3 — owner item 2, the kernel library macro owns the archive

Tool commit 9a84c0c: conventions `library_macro {load, rule}`; after
routing, `_fold_libraries` merges the pair (`cc_library`/`cc_per_source_
library` + its `ar_archive` X_a) and the `cc_object_files` X_objects rule
into one `kernel_library(...)` call in the library's package. Conditions,
each needed: all three rules in ONE package (the macro creates its targets
where it is called; an archive outside the package would move the file);
every attr within the macro's signature; the ar rule's `srcs` identical to
its `members` (a call the macro can spell — when they differ, the members
are cross-package object labels and the aggregate keeps the explicit
pair). The labels stay: `name`, `name_a`, `name_objects` — consumers keep
spelling them. 81 folds: one `kernel_library` per kernel directory that
owns its built-in.a (kernel/unwind, lib/crc, net/9p, arch/x86/lib x2...).
The top aggregates stay explicit — their libraries live in the root
package or have no TUs at all (certs_built-in's archive has 0 members:
the ar rule with no library rule to own it).

One bug on the way: the merged Rule got the dataclass default pkg=None —
emit26 put all 81 folds in the ROOT BUILD instead of their packages; the
merged rule must carry `pkg=base.pkg` (the fold runs after routing).
emit27 correct.

Layer rules: bazel/rules/kernel_library.bzl (macro over cc_library /
cc_per_source_library + ar_archive + cc_object_files; the class is
re-derived from the attrs — per-source attrs present ⇒ per-source
library). Gate: exact baseline (errors=6 warnings=15, IDIOM 5.2,
artifacts converged), build GREEN, suites 92/92.

## Phase 4 — owner item 4, flex/bison rules replace the checked-in generated parsers (in progress)

Proof first: local flex 2.6.4 / bison 3.8.2 reproduce the reference's
bytes exactly when the action is run the reference's way. flex content
is path-independent; bison's include guard follows the `-o` argument
(`bison -o scripts/kconfig/parser.tab.c` ->
YY_YY_SCRIPTS_KCONFIG_PARSER_TAB_H_INCLUDED), so the rule stages the
grammar into a tree-shaped directory and runs bison with the reference's
exact argv, then moves the two outputs to their declared places.

Layer: bazel/rules/flex.bzl + bison.bzl (run_shell, mnemonic Genrule,
PATH flex/bison); conventions gains a generic `unrecorded_codegen`
channel ({kind, name, src, outputs, load, rule}) wiring the emitter to
tool kinds; emitter gains the hook (rule emission once per group,
output registration, committed-copy byte-check + removal, output_labels
for cross-package consumers). Two wiring artifacts found and fixed:
- loads filter matched `flex` inside flag strings (-fstrict-flex-arrays
  in KBUILD_CFLAGS) -> _loads_text now strips string literals as well as
  comment lines;
- conf srcs carried parser.tab.h twice (plain + label) -> the label
  append skips a path already spelled plainly.
Emitter spelling lesson: a sub-package emission's model rels are
package-relative; the hook spells attrs in the emission's own package
form (workspace-relative only matters under routing in the root
emission). Tests: test_unrecorded_codegen_wires_a_rule_instead_of_a_committed_copy
+ the loads-filter test; suite 94/94.

Phase 4 landed (tool 3400a14, layer 9a01f8760): the hook spells rule
attrs in the emission's own package form; `outs` must be
attr.output_list (string_list does not create implicit output file
labels — conf's srcs resolved to nothing and the compiles failed with
missing inputs); bison.bzl needed explicit `+` for its command string
(implicit string concat is removed from Bazel's Starlark). The bison
staging runs under the linux-sandbox; /usr/bin/flex 2.6.4 and bison
3.8.2 reproduce the reference's bytes (the linuxbrew flex 2.6.4 too).
Gate on the final tree: errors=6 (same four nondeterministic contents +
tool/args pair), warnings 15→12 (the three generated_unrecorded gone),
artifacts converged, IDIOM 5.2 (rules 3127, dirs 120), build GREEN.
Side effect of the loads filter fix: the dead `load(objcopy)` lines
comments kept in ~11 packages are gone.

## Owner item 1 phase 2, batch 1 (tool_stdout genrules)

The remaining one-off generator steps (conmakehash, gen_crc32table,
mk_elfconfig, mkpiggy, relocs, vdso2c, the two awk table generators,
mkcpustr) all share one ground-truth shape: ONE stage, argv[0] a
workspace-built tool, every later token an input, the output (redirected
stdout or a final argument), or a bare option word (`--realmode`). New
recipe kind `tool_stdout` (conventions `{"rule": "genrule"}`; `_emit_kind_call`
learns to skip the load and place `tools` beside `srcs`), emitting exactly
the genrule a person writes:

    genrule(
        name = "consolemap_deftbl_c",
        srcs = ["cp437.uni"],
        tools = [":conmakehash"],
        outs = ["consolemap_deftbl.c"],
        cmd = "$(location :conmakehash) $(location cp437.uni) > $@",
    )

`_kind_input` generalized to `_kind_file` (a token -> its label spelling
against every input). 10 of 47 tree_recipe instances converted (root 15->13,
boot 4->3, compressed 3->2, vdso64 2->1, mod 2->1, rm 3->2; cpu, lib, vt ->0).
Smoke build green (13 linux-sandbox actions); consolemap_deftbl.c,
crc32table.h, elfconfig.h, cpustr.h, both inat-tables.c and
cpu-feature-names.c cmp-equal to the reference; piggy.S/realmode.relocs/
vdso64-image.c differ only through their upstream inputs (the same inputs
the tree_recipe replayed), which the accepted content-diff class owns.

**Correction — the shape is a rule, not a genrule.** The gate on the
genrule shape returned exact parity (errors=6, warnings=12) but IDIOM 9.0
against the 5.2 threshold: `shape_duplicates` 0->4 (+3.6, three repeated
cmd shapes over 11 genrules) and `genrules_per_tu` up with them -- and
with dup=0 the floor is still ~5.29, so no arrangement of repeated genrules
stays under the threshold. That is the metric's own advice, and the flex/
bison precedent: N one-off steps of the same shape are ONE rule class. The
kind now emits the shared `tool_stdout` rule (bazel/rules/tool_stdout.bzl;
conventions `{"load": "//bazel/rules:tool_stdout.bzl", "rule":
"tool_stdout"}`) -- `tool` a label for a workspace-built generator (a PATH
program like awk rides the cmd), `srcs`, `out`, `cmd` the line the
reference ran spelled genrule-style ($(location)s, `$@` the output; the
impl expands locations, replaces `$@`, run_shell, mnemonic `Genrule` so
the aquery filter and the differ see the same action they saw from the
tree_recipe). Smoke build green (29 actions); the 7 deterministic outputs
still cmp-equal. Gate t2: **PARITY exact baseline (errors=6, warnings=12,
artifacts converged, build GREEN) and IDIOM 5.2 -- the regression is
dissolved**: shape_duplicates 0 (was 4), genrules 11 -> 1 (the lone
auto_conf), tus 1236. The kind's shape is now a rule class, exactly the
flex/bison precedent.

## Owner item 1 phase 2, batch 2 (the syscall + shell-script generators)

The recognizer's interpreter branch: argv[0] `sh`/`bash` -- the interpreter
on the PATH, the script `$(location)`-spelled, the output the tool's last
argument (the `$@`); bare value words (`--abis i386`, `common,64`) pass
through as themselves. 7 more tree_recipe instances convert (5 unistd_*
headers + 2 syscalls_*, all in arch/x86, 37 -> 30), and one more caught by
the widened matcher: capflags.c (mkcapflags.sh, 38 -> 30). One guard the
shape needed: **the line is the rule's only window on its inputs** --
gen_initramfs.sh runs the gen_init_cpio tool by path without naming it on
the line, so the rule could not declare it -- the recognizer now rejects
any action with an input no argv token names, and that one stays a
tree_recipe. Smoke build green; capflags.c + all 7 syscall headers
cmp-equal to the reference. Gate t3: **exact baseline again (errors=6,
warnings=12, artifacts converged, build GREEN) and IDIOM 5.2, genrules 1**.
47 -> 29 tree_recipe instances (18 tool_stdout rules). Landed: tool commit
bd6dce6 (suites 97/97, INVARIANTS OK), layer amended 10573dfd0 "Bazel
layer (2026-10-13) on v7.2". Full check-invariants CORPUS=1 running.

## Acceptance (running)

One catch the vocabulary guard caught on the tool commit: the recognizer
comment named `gen_initramfs.sh` — `initramfs` is deliverable vocabulary;
reworded, commit amended bd6dce6 (suites + vocabulary OK on the amended
commit; the corpus sweep 37→37 had already run on behaviorally identical
code, re-run below).

- BOOT-SSH OK: the layer's bzImage (built by build-image.sh into
  /tmp/accept-image with a fresh initrd) boots under QEMU/KVM and
  `ssh root@guest true` succeeds.
- Fresh gate t4 + hermetic-build.sh running in parallel; CORPUS=1 after.

## Acceptance results

- **Gate t4 (fresh, on the amended layer):** PARITY build=GREEN
  diff=NOT converged errors=6 warnings=12 artifacts=converged 0 errors —
  exact baseline; IDIOM score=5.2 rules=3127 tus=1236 genrules=1 dirs=120
  (threshold 5.2). The 5.2's residual: manual_rules 21 ≈ 5.0, todo 135
  ≈ 0.2, genrules_per_tu 0.02; every replay/shape/hermeticity/layering
  detector 0.
- **BOOT-SSH OK:** build-image.sh built the layer's bzImage into
  /tmp/accept-image (fresh initrd with the key), boot-ssh-test.sh booted
  it under QEMU/KVM, exit 0 (`ssh root@guest true` succeeded).
- **HERMETIC OK:** //bazel/image:image builds in the clean ubuntu-24.04
  runner container (read-only tree, fresh output base), 1295
  processwrapper-sandbox actions, 0 errors.
- **check-invariants CORPUS=1 (amended commit bd6dce6):** suites 97/97,
  vocabulary OK, corpus 37 converged before → 37 after.

## Closing audit (the owner's "delete tree_recipe attributes nothing uses")

Audited the 29 remaining tree_recipe instances attribute by attribute:
every attribute the emitter can write still has at least one user —
recipe/exports 29, bin_wrappers 28, cc_wrappers/beside_wrappers/env_map
27, stage_dests 18, refresh/refresh_dests 17, stage 16, stage_tools 5,
tool_words 1, out_dirs 1. Nothing to prune; the instruction's condition
is empty.

Determinism re-verified on the final tool state: emit34 == emit35
byte-for-byte, and the committed tree matches the emit tree file for file
(diff-emit clean). voffset_h/zoffset_h stay tree_recipe by nature — the
reference recorded them as `sh -c .voffset.h.cmd` (the recipe lives in a
.cmd file, not in the argv), so no rule a person would write can carry
it; noted for the next run.

Verdict written: publish: release.
