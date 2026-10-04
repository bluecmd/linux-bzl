# journal — manual-2026-10-03b

Run brief: PARITY at start build=RED errors=76 warnings=22. Previous run
(manual-2026-10-03) was cut off after emitting v14; its uncommitted tool
work (extract: linker operands / inter-recipe steps / objtool overlay / -B
& -soname fixes; emit: feature inversion, gen_archived, _generator_tools
seed, wired_gen, root-reach walk) is now **committed** in wt-kernel:
b183c47 (extractor + regenerated ccache_strace golden — the only golden
delta is the intentional linker-operand enrichment and empty-input `mv`
recipe lines, build_relevant=False, never emitted) and c9a7f6a (emitter).

## Fixed this session (committed)

1. `_generator_tools.pull` had swallowed ConfigureFile producers entirely —
   the seed path needs that gate, the queue path does not (glib-mkenums
   expand_template disappeared). Restored: gate only on the seed call,
   queue only non-ConfigureFile, `p is g` guard.
2. `_per_source_split` factored common copts **token-wise**: the
   `-include include/linux/compiler_types.h` unit split across the C/S
   groups — flag stayed common, value went per-source, and the next common
   token (`-D__KERNEL__`) was absorbed as the include's value on the emitted
   line. 64 of the 76 errors (36 defines_diff + 28 flags_diff, all in the
   `-m16` boot/compressed families) came from this. Now factored at unit
   granularity (`_units`); C groups carry the pair per-source (8 tokens,
   exactly at _PER_SOURCE_MAX).
3. Raw-link dep whose TUs split into flag groups: the parent cc_library
   carried only its own srcs' objects (vDSO: only note.o), so the
   `--whole-archive` link saw every `__vdso_*` symbol undefined — the one
   red target (vdso64.so.dbg). Parent emitted as `cc_static_library`
   (rules_cc+ CppTransitiveArchive merges the transitive set into one file
   the `$(location)` names).
4. Test `generated_headers_library_is_scoped...` updated to the v11 walk
   regime: under a wide include root, reach is what the TUs *name*; the
   "reaches everything" TU now names all three files (the test's intent,
   pre-walk, was root-reach).
5. Reference model regenerated with the fixed extractor
   (models/kernel/model.capture.json), and the emitter's config-out is now
   copied back into models/kernel/any2bazel.json (the previous run never
   did, so its accepts were invisible to parity).

## Iteration log

- v15 emitted (570 targets, 114 codegen; emit takes ~4.5 min — the pkg TU
  os.walk is the cost). Parity run in flight.
- v15 parity: 69 errors / 19 warnings; build still RED on the vmlinux link
  chain. Work this block is that chain, top-down: `//:vdso64_so` →
  `//:vdso64_image_c` → `//:tmp_vmlinux_nm_sort` (link-vmlinux.sh).
- v16–v18 (`vdso64_so` / `vdso64_image_c`): the raw link's out is declared
  at the reference's own path (`arch/x86/kernel/vdso/vdso64.so`), so a
  consumer genrule staging it with `cp -f $(location :vdso64_so)
  $(GENDIR)/arch/x86/kernel/vdso/vdso64.so` copied it onto itself. Fix in
  the emitter: pre-register `_produced_at_ref` at PLAN time (it was only
  populated in `_render_raw_link`, which renders after the consumer) for
  EXECUTABLE and SHARED targets whose link action is a raw link; the
  staging loop then skips those labels. v18: zero self-copies,
  `//:vdso64_image_c` green.
- v19–v24 (`tmp_vmlinux_nm_sort` — link-vmlinux.sh): the line's recipe runs
  a *nested make* (`${MAKE} -f scripts/Makefile.build obj=init
  init/version-timestamp.o`, link-vmlinux.sh:176). Kbuild's
  `if-changed-cond`/`cmd-check` (scripts/Kbuild.include:168) rebuilds a
  target whenever the `savedcmd_$@` from its `.cmd` bookkeeping is absent —
  the bookkeeping is not part of the mirror, so **the sub-build always
  rebuilds, no matter the mtimes**. The reference's own sub-build compiled
  there too (its filechk re-stamps utsversion.h), so the trace carries the
  sub-build's reads — but only partially, and the attribution stopped at
  the make. Four fixes:
  1. extractor `owners_past_makes()`: a step under a nested make runs for
     the enclosing recipe line's sake too — its non-mechanics reads
     (sources, headers, scripts, Kbuild bookkeeping aside) and the in-tree
     programs it runs (`cmd_and_fixdep` runs the build's `fixdep`) route
     past the make to the line. fixdep's own dep records *elide* the
     configure headers (`include/generated/autoconf.h` is fixdep's blind
     spot by design), so the trace alone can never carry it.
  2. emitter: a genrule whose inputs carry make bookkeeping (Makefile*,
     Kbuild, Kbuild.include) stages the package's generated headers
     (`gen_outs_all` ∪ `template_outs` ∩ header exts) in its mirror —
     kconfig.h pulls in `<generated/autoconf.h>`, and the sandbox sub-build
     has to find it at `$(GENDIR)/include/generated/autoconf.h`.
  3. extractor: in-tree programs past a nested make land in the line's
     inputs (`sub_reads`), so the emitter names the tool that builds the
     binary and stages it at its reference path
     (`cp -p $(location :fixdep) $(GENDIR)/scripts/basic/fixdep`).
  4. staging: `cp -p` (not `-f`) so the staged sources keep their mtimes
     under the refreshed generated files; generated inputs that already sit
     at their reference paths get the refresh dance — fresh writable copies
     at one mtime — because the sandbox keeps its inputs read-only and a
     make may well have to overwrite them (version-timestamp.o). Committed
     inputs stage with `cp -p`; the `:fixdep` tool stages at
     `scripts/basic/fixdep`.
- v24 status: the nested compile *runs* in the sandbox but dies on
  `./include/linux/kconfig.h:5: 'generated/autoconf.h' file not found` —
  fixdep's elision is exactly the hole; v25 (extractor programs-past-makes
  + emitter generated-headers staging) is the fix under test.
- Emitter tests: 68/68; extractor tests: 180/180 (two `cp -f` → `cp -p`
  assertions updated in test_emit_build.py — the tests encode the intended
  staging behavior).
- v27 (`built_in` — the startup archive): the model target `built-in`
  (arch/x86/boot/startup/built-in.a) archives only the two `pi`-objects —
  outputs of the `objcopy --prefix-symbols=__pi_` genrules, no cc target
  compiled them — so the rendered cc_library was empty and the link saw
  `__pi___startup_64` etc. undefined. New layer rule `cc_objects`
  (bazel/rules/cc_objects.bzl): declares files as the objects of a cc
  target. rules_cc's public `cc_common` in Bazel 9.2 has no
  `create_linking_context`; the rule builds the provider from the private
  modules (`//cc/private:cc_info.bzl`, `//cc/private/link:...`) — a direct
  `LibraryToLinkInfo(objects=..., _contains_objects=True, ...)`, the
  objects frozen via `cc_internal.freeze` (a struct with a mutable list is
  not a depset element), and `pic_objects` spelled too (the merge reads
  it). Probe: `cc_static_library` over a `cc_objects` target archives the
  objects (`libcombo.a`: one.o, two.o). Emitter wiring: conventions
  `cc_objects.load`; `_plan_one` computes `p["objects"]` for a sourceless
  archive target whose CppArchive members are objects no compile in the
  model made (`.a` members and model compile outputs keep the old
  rendering); `_render_target` emits `cc_objects` (and, inside the
  gen_archived branch, a sub-target `name_objs` + `cc_static_library` over
  it when a recipe reads the archive by name). Only the startup leaf
  flips: v27 has exactly one `cc_objects(`.
- **v27 GREEN on `//:tmp_vmlinux_nm_sort`** — the whole vmlinux link
  chain: vmlinux.a → vmlinux.o (with the nested make sub-build: `UPD
  utsversion.h`, `CC init/version-timestamp.o`, `LD vmlinux.unstripped`,
  `NM System.map`, `SORTTAB`). `//:vmlinux` links with all 21 `__pi_`
  symbols.
- Next failure `//:voffset_h`: `A2B_CC: unbound variable` — the cmd was
  rendered as one quoted literal. Root cause (emitter, pre-existing — 91
  genrules in v26 too): the `_rel_include` copy path did
  `attrs["cmd"] + " && cp ..."` — `Raw` is a str subclass, `Raw + str`
  returns a plain str, and the renderer then escaped the already-composed
  `" + _RECIPE_ENV + "` expression into the string. Fix: wrap in
  `Raw(...)` when appending the copy. Test added:
  `test_archive_of_objects_no_compile_made_becomes_cc_objects` (69/69
  emit; the test must sit BEFORE the `__main__` runner block — appending
  after it puts it outside the discovery loop).
- v28–v31: the Raw fix's first two attempts mangled 91 genrules worse
  (`Raw(attrs["cmd"] + suffix)` appended after the closing quote —
  Starlark syntax error at `&`; then `cd $(GENDIR) && cp` — already
  inside GENDIR, `cp: cannot stat`). Final fix: detect the in-cwd mirror
  from the cmd text (`cd $(GENDIR)(/path)?`) and spell the copy pair with
  `posixpath.relpath(target, cwd)`; splice INSIDE the last quoted part of
  the Raw expression (`cmd[:rindex('"')] + escaped + '"'`).
- **v32–v33 — `//:bzImage` BUILDS.** The chain from the vmlinux link on:
  - `zoffset_h` read the WRONG vmlinux: the model target `vmlinux` is the
    COMPRESSED link (ld.lld → arch/x86/boot/compressed/vmlinux), but a
    generator took its name (the strip recipe writes `vmlinux`), so
    `_render_target` renamed the binary by its output path
    (`arch_x86_boot_compressed_vmlinux`) — while the plan-time
    `output_labels` registration still said `:vmlinux`. `zoffset_h`'s
    input resolved to that stale label = the STRIPPED top-level image →
    `llvm-nm` found no ZO_* symbols → empty zoffset.h → header.S died on
    "expected relocatable expression". Fix: the rename decision moves to
    plan time (`_codegen_names()`), so `output_labels`, `name_of` and
    `_produced_at_ref` carry the final label from the start (the
    render-time branch keeps its output_labels update for later
    collisions). Test: `test_executable_named_after_a_generated_file_is_
    named_by_its_path`.
  - With the compressed link now actually depended on, `piggy.S`'s
    `.incbin` surfaced: mkpiggy embeds the path it was handed, and the
    emitted argv spells `$(location ...)` = the genfiles-prefixed
    execroot path the compile sandbox can't see. Fix in `_incbin_inputs`:
    match the name as spelled, including a genfiles prefix
    (`strip_genfiles`), read a GENERATED asm source back from the
    reference build tree (`pkg_dir` has only committed files), and wire
    the blob into the raw link's and the binary's per-source objects
    libraries (only group libraries and plain cc_library had the
    wiring). No `-I$(GENDIR)` root for an execroot spelling — the
    declared input sits at its execroot path in the compile sandbox.
    Test: `test_generated_asm_incbin_of_a_generated_blob_is_a_compile_
    input`.
  - zoffset.h now carries the ZO_* defines (390 bytes, reference-shaped);
    `//:voffset_h`, `//:zoffset_h`, `//:bzImage` all build.
- Tool state committed in wt-kernel: e5721d6 (extractor
  owners_past_makes), 34c0fc0 (emitter: cc_objects, Raw-preserving
  suffixes, plan-time renames, declared .incbin inputs). Suites green
  (180/180 capture, 71/71 emit), invariants OK. Full parity in flight.
- Process notes: extraction ~50 s (`extract_capture.py CAP WS
  models/kernel/model.capture.json --build-dir ref --source-dir src-ref
  --project-root . --report` — copy the invocation from loop.sh verbatim);
  emit ~4.5 min; suites are plain `python3 tests/test_*.py` (no pytest);
  `--sandbox_debug` keeps genrule sandboxes under the output base for
  inspection, but the next bazel command cleans them.


### 2026-10-04 (cont.) — archive recipes v35–v38

- Empty-archive cascade root-caused: kbuild's `cmd_ar_builtin` runs
  `$(AR) cDPrST $@` for EVERY visited dir, empty or not — 392 of the 565
  captured archives have zero members, genuinely (verified in the raw
  strace: `llvm-ar cDPrST arch/x86/crypto/built-in.a`, no members, exit 0).
  The plan treated an empty member list as a failure and cascaded the drop
  up the whole chain (413 unmarked incl. built-in_2/built-in-fixup).
  Empty member lists now reproduce the recipe verbatim.
- Out-of-scope members (tests-role dirs: lib/tests, lib/raid/xor/tests,
  drivers/*/test(s), net/wireless/tests): the recipe survives with the
  member dropped and the drop is on the record; an UNMODELED member
  (subcmd's `libsubcmd-in.o`, an `ld -r` the capture has no action for)
  still fails the target → the aggregate fallback as before (v33 path,
  keeps objtool linking). Rule: modeled-but-not-emitted → skip member;
  not modeled at all → fail target. 16 drops → 1 fallback (subcmd) + 9
  documented drops.
- Nested THIN archives: the parent ar opens a thin sub-archive's members
  (flattens it), so the transitive leaf objects must be declared srcs of
  the parent's genrule (sandbox). `archive_extra_src` + `_archive_leaf_rels`;
  the fixpoint now also iterates until member sets stop growing (parents
  may precede children in target order).
- `$(AR)` in ar recipes is anchored (`$$A2B_AR`, exported before the
  `cd $(GENDIR)`) — the make variable is execroot-relative and the recipe
  runs below $(GENDIR); bare `$(AR)` gave exit 127.
- cc_object_files lib naming fixed: the object registry now maps member
  objects to the rule that actually renders them — the target's own
  cc_library (per-source or plain, both render under the target name) and
  the static twin under `<name>_static`; the old `<name>_objs` /
  `<name>_static_objs` spellings named rules that are never emitted.
- v37: analysis clean through the chain, execution hit 'cmdline.o' (nested
  thin) → v38 in flight with the leaf-src fix.

### 2026-10-04 (cont. 2) — v39→v42: build GREEN, artifacts converged, BOOT OK

- v39/v40: the skip-vs-fail rule + empty-archive fix cleared the 413-target
  unmark cascade → 1 aggregate fallback (subcmd) + 9 documented member
  drops. v40 analysis-clean; execution failed at //:vmlinux_o with
  `ld.lld: could not get the buffer for a child of the archive:
  'init/main.o'` — the same nested-thin problem one level UP: vmlinux.a
  (`cat built-in-fixup.a > vmlinux.a`) is still thin, and the vmlinux.o
  LINK opens it, so its leaf members must be in the link's sandbox too.
- v41/v42 — generalized the leaf pull to consumers: `_thin_leaves(norm)`
  (memoized, cycle-guarded) resolves an input rel to an ar-recipe archive
  and returns its transitive leaf members; a `cat`/`cp` copy of a thin
  archive (the reference's `cat built-in-fixup.a > vmlinux.a`) keeps the
  thin format, so the leaves propagate through the copy — detected by
  recipe-line regex (`cat X > Y`, `cp X Y`) or a tool-level cat/cp action.
  `_emit_genrule` pulls the leaves of every thin-archive input as srcs
  (in-gendir staging for generated/obj_label_of members). vmlinux_o's srcs
  went from `["vmlinux.a"]` to the archive + its ~10k leaf objects.
- **v42: PARITY build=GREEN diff=NOT converged errors=6 warnings=17
  artifacts=converged 0 errors.** First green full-tree build with the
  ar-recipe chain. Artifact diff converged with 0 errors (realmode.elf,
  setup.elf, compressed vmlinux, vdso64.so — symbol/weak/soname/needed all
  match). Residual diff errors (6) are the four known generated files:
  voffset.h + zoffset.h address deltas (cmake/bazel vmlinux layout shifts
  by 0x1000), vdso64-image.c byte deltas, autoconf.h (conf tool swap,
  args `--syncconfig Kconfig` unmodeled); plus defines_diff x7
  (NDEBUG/_FORTIFY_SOURCE on the tools host build), extra_tu x5,
  extra_target :fixdep, generated_unrecorded x3 (kconfig lexer/parser —
  circular committed-copy check), missing_tu x388 GONE.
- **ACCEPTANCE: boot-ssh-test.sh on the Bazel bzImage → `BOOT-SSH OK after
  3s: 7.2.0`.** net/netlink/built-in.a member order confirmed
  (af_netlink, genetlink, policy — the initcall-order fix). Canonical
  build-image.sh + boot-ssh-test.sh also run for the record.
- Tests: 74/74 emit (new `test_thin_archive_consumer_declares_the_leaf_
  members`), 180/180 capture. Tool work ready to commit.
- Tool work committed in wt-kernel: a4cbe2e (capture: ar m edit steps as
  actions on the archive) + 732db02 (emit: ar-recipe genrules, empty
  member lists verbatim, skip-vs-fail, nested-thin leaf srcs, consumer
  leaf pull, $$A2B_AR anchoring, cc_object_files naming). check-invariants
  OK (suites + vocabulary); CORPUS=1 sweep in flight.
- Verdict set to `publish: release` in report.md: main = v7.2 + one
  Bazel-layer commit, build GREEN //..., artifacts converged (0 errors),
  BOOT-SSH OK (3 s) on both the direct bazel-out bzImage and the canonical
  build-image.sh image.

### 2026-10-04 (cont. 3) — CORPUS sweep regression found, root-caused, fixed

The optional CORPUS=1 sweep (backgrounded after the release verdict) FAILED
with 18 regressions vs the results.tsv baseline — every one a build:missing_
header/missing_include_dir class (bash, file, gdbm, kmod, libcap-ng, libestr,
libmd, libmnl, libnftnl, libusb, libxcrypt, lldpd, mdio-tools, minicom,
netcat, oniguruma, procps-ng, xz). Bisected through temp worktrees:
upstream dea5d81 converged, b183c47 converged, c9a7f6a broke. Root cause:
c9a7f6a's scoped generated-header libraries compute reach against `all_gen`,
which had dropped expand_template/configure outputs (those register a LABEL
like `:config_h` in generated_hdrs whose PATH lives only in template_outs) —
so bash's config.h fell out of the reach walk and out of the scoped
`bash_generated_under_*` cc_library: `fatal error: config.h: No such file or
directory`. The 74/74 suite missed it because the existing template-mode
test has a single generated file (reach == all_gen → the catch-all library
carries it; the scoped path never ran).

Fix (emit_build.py, target loop): all_gen now adds
`{h for h in self.template_outs if h.endswith(HEADER_EXTS)}`. Regression test
`test_scoped_reach_keeps_configure_headers_the_tus_include`: a ConfigureFile
config.h + a second genrule header in a subdir nothing includes (that is what
forces reach != all_gen so the scoped path runs) — asserts target `a` deps
`:foo_generated_under_x` (not the catch-all) whose hdrs carry BOTH `:config_h`
and the `config.h` path. Verified the test bites: with the fix stashed the
scoped lib's hdrs lose the path.

- Suites 75/75 emit + 180/180 capture; check-invariants (suites+vocabulary) OK.
- Corpus: bash rerun converged, then all 17 other regressed packages rerun —
  all 18 now green/converged; CORPUS=1 full sweep in flight.
- v43 re-emission with the fixed emitter is byte-identical to the installed
  v42 BUILD + config (the kernel has no template-mode generated headers in
  this path), so no parity re-run or re-boot is needed.
- Bisect worktrees /tmp/wt-prev, /tmp/wt-bis1, /tmp/wt-bis2 removed.
- CORPUS=1 full sweep with 538096b: **INVARIANTS OK, 37/37 converged**
  (/tmp/invariants.corpus2.log). Tool work committed: 538096b (emit:
  configure/expand_template outputs join the reach walk) on top of
  a4cbe2e + 732db02. Report.md updated with the sweep outcome; verdict
  stands `publish: release` (v43 emission byte-identical to the
  installed v42, boot evidence unchanged).
