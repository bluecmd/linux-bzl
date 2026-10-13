# report — 2026-10-13

*(updated as the run proceeds; verdict at the end)*

## State at run start
PARITY build=GREEN diff=NOT converged errors=6 warnings=15 (the accepted
release baseline profile: generated_content_diff x4 + defines/extra_tu
warning classes), artifacts converged 0 errors. IDIOM score=5.2 (threshold
5.2). HERMETIC OK, BOOT-SSH OK carried from 2026-10-08. Layer at c3a4913
(main), any2bazel worktree kbuild-intree at 034a03f. 93 `tree_recipe`
rules in the layer (arch/x86 34, root 22, boot 6, vt 5, realmode 4,
compressed 4, scripts/mod 3, vdso 3...).

## Plan
(see plan.md — the owner's order: purpose-built rules for the recurring
tree_recipe kinds; per-package boilerplate; the kernel library macro owns
the archive; flex/bison.)

## Journal
journal.md in this directory, updated as steps land.

## What landed
*(updated as steps land)*

- **Owner item 1, phase 1 — 46 of the 93 `tree_recipe` instances converted to
  purpose-built rules.** The kinds, chosen by ground-truth kept-stage shape
  (`/tmp/ref-stages.txt`, the reference's `command_stages` reduction):
  `wrap_header` x26 (the `echo '#include <generic>'` header wrappers),
  `copy_file` x6 (`cat src > out`; vmlinux_a converts too — its ~200 object
  srcs were staging for the ar path, the rule's only input is the fixup
  archive), `objcopy` x7 (tool `@kernel_llvm//:bin/llvm-objcopy`), 
  `offsets_header` x4 (Kbuild's `sed-offsets` + cmp/mv stamping, verbatim),
  `chksha1` x3. Rules live in `bazel/rules/`, all with the `Genrule`
  mnemonic so the aquery filter and idiom counting are untouched.
- **Emitter mechanism (generic, tool commit c9a6caf on kbuild-intree):**
  conventions `recipe_kinds: {kind: {load, rule}}`; recognizers
  `_emit_kind_<kind>` match the reference ACTION's kept stages, never recipe
  text; anything not seen plainly stays a `tree_recipe`. Shared reduction:
  `codegen.bookkeeping_stage`/`kept_stages` (the trailing `.cmd` printf) now
  used by both the differ and the recognizers. Emitter is byte-deterministic
  (emit22 == emit23; the last nondeterminism, set-iteration deps order, now
  `sorted()`).
- **Layer amended** as the single commit 90254bd4f "Bazel layer (2026-10-08)
  on v7.2" (2092 files; includes the release.yml `bison flex` apt line for
  owner item 4).
- **Full parity gate on the converted layer: exact baseline.** errors=6
  (the four known nondeterministic-content files), warnings=15, artifacts
  converged 0 errors, build GREEN, IDIOM 5.2 unchanged. check-invariants
  CORPUS=1: INVARIANTS OK, corpus 37 converged before → 37 after.
- 47 `tree_recipe` instances remain (root 15, arch/x86 8, boot 4,
  realmode/rm 3, boot/compressed 3, scripts/mod 2, vdso64 2, + singletons).
- **Owner item 3 — per-package boilerplate (tool commit 4d39512):**
  - *Load only used lines:* the emitter's loads are collected globally, and
    every BUILD carried the union — 25020 load statements, 26k dead symbol
    instances across 2085 files (`chksha1` loaded in 2084 files that use
    none). Each BUILD now carries only the loads its own body names
    (25020 → 2761 lines); usage implies occurrence, so the filter can only
    err toward keeping.
  - *The shared recipe env is not BUILD content:* every env-bearing package
    carried the ~2KB `_COMMON_ENV` dict. New conventions key
    `env_module {bzl, symbol}`: the emitter writes the dict once into
    `bazel/rules/kbuild_env.bzl` (new `extra_files` channel), packages
    `load("...kbuild_env.bzl", "COMMON_ENV")` and spell
    `dict(COMMON_ENV, ...)`. Without the key the emitter keeps the
    per-BUILD constant (the corpus sees no change).
  Gate after both: exact baseline (errors=6 warnings=15 IDIOM 5.2, artifacts
  converged), suites 92/92, INVARIANTS OK corpus 37→37, layer amended.

- **Owner item 2 — the kernel library macro owns the archive (tool
  commit 9a84c0c):** conventions `library_macro`; after routing the emitter
  folds a library's `ar_archive` (the reference's own ar recipe) and
  `cc_object_files` (the objects a recipe reads by path) into one
  `kernel_library(...)` call in the library's package — 81 folds, one per
  kernel directory that owns its built-in.a. Only same-package pairs fold
  (the macro creates its targets where it is called) and only when the
  ar rule's srcs are its members; the top aggregates stay the explicit
  pair, and the labels (`name`, `name_a`, `name_objects`) are unchanged,
  so consumers keep spelling them. Gate: exact baseline.

- **Owner item 4 — the checked-in flex/bison outputs are rules now (tool
  commit 3400a14, layer amended 9a01f8760 "Bazel layer (2026-10-13) on
  v7.2"):** scripts/kconfig's `lexer.lex.c` and `parser.tab.[ch]` are
  generated in-tree by Kbuild pattern rules exec capture cannot see (the
  reference's own recipe lines: `flex -o scripts/kconfig/lexer.lex.c -L
  lexer.l`, `bison -o scripts/kconfig/parser.tab.c
  --defines=scripts/kconfig/parser.tab.h -t -l parser.y`); until now they
  shipped as checked-in copies of the reference's bytes (three
  `generated_unrecorded` TODOs, and `generated_unrecorded` warnings).
  - `bazel/rules/flex.bzl` runs `flex -o <out> -L <src>`; the generated
    content is path-independent. `bazel/rules/bison.bzl` stages the
    grammar into a tree-shaped directory and runs the reference's exact
    argv there, because **bison's include guard comes from the path the
    `-o` argument spells** (`YY_YY_SCRIPTS_KCONFIG_PARSER_TAB_H_INCLUDED`)
    — then moves the two outputs to their declared places.
  - **Pinned versions: flex 2.6.4, bison 3.8.2** — those are what
    reproduces the reference's bytes byte for byte (verified for
    /usr/bin/flex and the linuxbrew one; bison relative-vs-absolute `.y`
    spellings both fine since `-l` strips the `#line` that carries paths).
    The runner and the hermetic container carry both from apt.
  - The emitter wires them through a **generic conventions channel,
    `unrecorded_codegen`** ({kind, name, src, outputs, load, rule}): the
    rule is emitted once per group, the outputs join the generated-file
    machinery (conf compiles both `.c`s; the generated header reaches
    lexer.lex.c beside it in genfiles), and the three checked-in copies
    are gone (`git rm`) after the emitter's byte check confirmed each was
    the reference's output.
  - Gate on the final tree: **errors=6 unchanged** (the four known
    nondeterministic-content files + the tool/args pair), **warnings 15→12**
    (the three `generated_unrecorded` gone), artifacts converged 0 errors,
    build GREEN, IDIOM 5.2 (rules 3127, dirs 120). conf smoke-built first
    under the real runner: all three files `cmp`-equal to the reference's.
  - The loads-filter fix that shipped with it (a symbol named in a comment
    or inside a string — `-fstrict-flex-arrays` — is not a use) also
    removed the dead `load("//bazel/rules:objcopy.bzl", "objcopy")` lines
    comments had kept in ~11 packages. check-invariants CORPUS=1: OK,
    corpus 37→37.

- **Owner item 1 phase 2 — the one-off generator steps are `tool_stdout`
  rules (tool commit bd6dce6, layer amended 10573dfd0):** 18 more
  `tree_recipe` instances converted (93 → 29 in the layer). The steps
  share one ground-truth shape: one stage, argv[0] a workspace-built tool
  (conmakehash, gen_crc32table, mk_elfconfig, mkcpustr, mkpiggy, relocs,
  vdso2c) or an interpreter (sh over syscallhdr/syscalltbl/mkcapflags,
  awk over the in-tree table generators), every token an input, an option
  or a bare value, the output redirected from the tool's stdout or spelled
  as its last argument.
  - The emitted shape is the shared `tool_stdout` rule
    (`bazel/rules/tool_stdout.bzl`), not one genrule per step: `tool` a
    label for a built generator (a PATH program rides the `cmd`),
    `srcs` the files, `out`, `cmd` the line the reference ran spelled
    genrule-style (`$(location)`, `$@` the output). A first cut emitted
    bare genrules — parity held (errors=6, warnings=12) but IDIOM regressed
    5.2 → 9.0 (`shape_duplicates` +3.6 over three repeated cmd shapes; with
    them dissolved the floor was still ≈5.29): N steps of one shape are one
    rule class, as the metric itself states. The rule dissolves it: IDIOM
    back to 5.2, genrules 1 (the lone auto_conf).
  - A guard the shape needed: the line is the rule's only window on its
    files, so a step the reference runs with a file it does not name on the
    line (`gen_initramfs.sh` runs the `gen_init_cpio` tool it builds by
    path) stays a `tree_recipe` — the recognizer rejects it.
  - Smoke: the 18 rules' deterministic outputs (consolemap_deftbl.c,
    crc32table.h, elfconfig.h, cpustr.h, both inat-tables.c,
    cpu-feature-names.c, capflags.c, all 5 unistd_*.h, both syscalls_*.h)
    cmp-equal to the reference; piggy.S/realmode.relocs/vdso64-image.c
    differ only through their upstream inputs, which the accepted
    content-diff class owns. Gate (fresh, t4, on the amended layer):
    **exact baseline (errors=6, warnings=12, artifacts converged 0 errors,
    build GREEN) with IDIOM 5.2 unchanged, genrules 1**. check-invariants
    CORPUS=1 on the amended commit bd6dce6: suites 97/97, vocabulary OK,
    corpus 37 converged before → 37 after.

## Results

State at end (tool commit bd6dce6 on kbuild-intree; layer single commit
10573dfd0 "Bazel layer (2026-10-13) on v7.2" on v7.2):

- **PARITY (fresh full gate t4):** build=GREEN, diff=NOT converged
  **errors=6, warnings=12** — exactly the accepted release baseline
  profile (generated_content_diff x4: voffset.h, zoffset.h,
  vdso64-image.c, autoconf.h — all four nondeterministic-content files the
  accepted release carries; plus generated_tool_diff +
  generated_args_diff on autoconf; defines_diff x7 NDEBUG/_FORTIFY_SOURCE
  and extra_tu x5 as warnings). Artifacts converged 0 errors.
- **IDIOM 5.2** (threshold 5.2, rules 3127, genrules 1, dirs 120): the
  residual is `manual_rules` (21 manual tags ≈ 5.0) + todo 0.2 + genrules
  0.02; every replay/shape/hermeticity/layering detector is 0.
- **HERMETIC OK:** `//bazel/image:image` builds in the clean
  ubuntu-24.04 runner container (read-only tree, fresh output base).
- **BOOT-SSH OK:** the layer's bzImage (build-image.sh, fresh initrd)
  boots under QEMU/KVM; `ssh root@guest true` succeeds.
- **Invariants:** suites 97/97, no deliverable vocabulary in the tool,
  check-invariants CORPUS=1: corpus 37 converged before → 37 after.
- `tree_recipe` instances 93 → 29 across the run (wrap_header x26,
  copy_file x6, objcopy x7, offsets_header x4, chksha1 x3, flex/bison,
  tool_stdout x18).

## What remains
*(the next run's list)*

- 29 `tree_recipe` instances (the chained recipes): root 13 (auto_conf the
  lone genrule, built_in_fixup_a, compile_h, modules_builtin, timeconst_h,
  tmp_vmlinux_nm_sort, + the vmlinux chain), boot 3 (bzImage, voffset_h,
  zoffset_h — the two known content-diff files), compressed 2,
  kernel 2 (asm_offsets_s, vmlinux_lds), realmode/rm 2 (pasyms_h,
  realmode_lds), vdso64 1, entry syscalls' capflags…: per-package counts
  above. The next shapes worth a rule class:
  - the **cmp-stamp trio** (cpufeaturemasks_h, compile_h, timeconst_h):
    generator writing a `.tmp_<out>` sibling + `cmp -s` stamping
    (Kbuild's if_changed); a `stamp` rule would own the stamp glue once,
    the generator line as `cmd` — the plumbing is the ref's exact `.tmp`
    spelling, which the impl must derive identically.
  - the vmlinux chain and bzImage (multi-tool recipes: nm/sort/xz/objcopy/
    ld), utsrelease (make -s -f utsrelease), voffset/zoffset (sh over
    objdump/nm + awk) — deeper than one line; a `kernel_link`-family rule.
  - the idiom floor is `manual_rules` (21 manual tags, 5.0 of the 5.2) —
    the actual next lever if the score needs to drop further.
  - **"Delete `tree_recipe` attributes nothing uses": audited, nothing to
    prune.** Every attribute the emitter can write still has at least one
    user among the 29 (recipe/exports 29, bin_wrappers 28, cc_wrappers/
    beside_wrappers/env_map 27, stage_dests 18, refresh/refresh_dests 17,
    stage 16, stage_tools 5, tool_words/out_dirs 1).
  - voffset_h/zoffset_h stay `tree_recipe` by nature: the reference
    recorded them as `sh -c .voffset.h.cmd` — the recipe lives in a
    `.cmd` file, not in the argv — so no rule call can carry it as
    meaningful attributes; the next run needs a different mechanism.
- The 2026-10-11 feedback's machine-specific content point: the last
  checked-in generated sources went this run (flex/bison); the layer
  carries no `/scratch` paths and no `.idiom-*.json` (unchanged from the
  accepted 2026-10-08/11 lineage).

## Verdict

**publish: release.** Parity is at the accepted release baseline (same 6
errors / 12 warnings the accepted release carries), the artifact stage
converges with 0 errors, the layer builds hermetically in the runner
container, and the bzImage boots and accepts SSH. IDIOM 5.2 is at the
threshold — the run's own conversions (93 → 29 `tree_recipe` instances,
the one-off generator steps as one `tool_stdout` rule class) held it
there: the first cut of the batch taught that repeated shapes must be
one rule class, not repeated genrules (9.0, dissolved by the rule).

*(acceptance steps' full logs: /tmp/gate-t4.log, /tmp/hermetic-t4.log +
$ROOT/hermetic/, this run's journal.md; the boot log is the
boot-ssh-test.sh transcript.)*
