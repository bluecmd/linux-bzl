# journal — 2026-10-06

## 00:00–00:30 orientation
- Re-ran parity on the untouched tree: PARITY GREEN, errors=6 warnings=16,
  artifacts converged, IDIOM 49.9 (delta +0.0). Baseline identical to
  manual-2026-10-04b.
- Read idiom.py in full. Score 49.9 decomposes: env_replayed 10.0,
  packages_vs_dirs 9.75, shape_duplicates 8.33, manual_rules 5.0,
  grp_splits 4.61, todo 3.96, repeated_flags 2.45, hermeticity 2.81,
  include_flags 1.87, genrules_per_tu 0.29, recipe_replay 0.83.
- env_replayed = 131 names, only droppable by not spelling the 96-var
  common env as `"K=V "` command text (denominator 50).
- The differ strips leading `K=V` assignments per stage (codegen.py), so
  recipe env is parity-invisible. The capture records Action.env (the real
  environment), so the data survives the move.
- The 17 remaining genrules are all the execroot shape: the reference ran
  the recipe in the build root, the layer's outputs already sit at
  build-root-relative paths under $(GENDIR) → `tree_recipe(cwd=".")` can
  replay them verbatim without the $(location) respelling.
- 21 manual tags: 14 host-tool cc_binaries (all consumed as `tools`),
  2 objtool fixdeps (truly unwired), the boot endgame chain (setup_bin,
  arch_x86_boot_vmlinux_bin, bzImage, initramfs_data_cpio, modules_builtin).
- TODOs: ~340 blanket "verify the cmd runs in the sandbox" (per recipe rule
  and per ar_archive), 111 "compiles X with different flags", rest misc.
- toolchain_flag_in_copts=91: flags the cc toolchain's probe says it already
  supplies, spelled in copts anyway.

Plan written; starting step 1+2 (tree_recipe for the execroot recipes +
env-as-dict).

## 00:30–01:10 emitter edits (steps 1+2)
- tree_recipe.bzl: new `env_map` string_dict attr; values shell-quoted onto
  the line by `_sh_word` (single-quote on shell meta, `$`→`$$` for the
  expand). `env` stays for the fallback shape.
- emit_build.py: `_action_env_map` (pairs the capture recorded, common part
  → `_COMMON_ENV`, rule carries only what differs, values respelled raw —
  quoting is the bzl's job); `_render_recipe_env` emits `_COMMON_ENV = {...}`
  beside the legacy `_RECIPE_ENV`; `_emit_genrule` execroot gate (cwd=".")
  when the `execroot` knob is on; `_emit_genrule_in_cwd` computes the map
  form only when the `env: "map"` knob is on, folds `genrule_env` statics
  into it, and falls back to the line-prefixed string only when the
  tree_recipe conversion refuses; `_emit_tree_recipe` takes `env_map` and
  renders `env_map = dict(_COMMON_ENV, …)` / `env_map = _COMMON_ENV`; the
  ar refusal is relaxed to plain creates only (`ar_recipe and not
  chained_toks`) so the `ar m` edit chain (built_in_fixup_a) converts.
- conventions.json: `tree_recipe: {…, "env": "map", "execroot": true}`.
- Re-emitting BUILD.bazel now; next: build, iterate, parity.

## 01:10–01:50 steps 1+2 land: PARITY GREEN, IDIOM 49.9 → 30.5
- First build RED: Starlark strings are not iterable (`for c in w` in
  `_sh_word`) — fixed with `meta.elems()`. Second build GREEN on cache (the
  tree_recipe action commands are byte-identical to the old genrule cmds —
  only 21 actions ran).
- PARITY build=GREEN diff=NOT converged errors=6 warnings=16 artifacts
  converged 0 errors — same classes as the baseline (4× generated_content_diff
  + generated_tool_diff + generated_args_diff on the accepted auto.conf
  cluster; warnings 5 extra_tu, 7 defines_diff, 1 extra_target,
  3 generated_unrecorded).
- IDIOM 30.5 (from 49.9). env_replayed 10→0, shape_duplicates 8.33→0,
  recipe_replay 0.83→0, genrules_per_tu 0.29→0.016 (genrules=1:
  //bazel/image:initrd). recipe_replay/env_replayed/shape_duplicates
  detectors all t=0.
- All 17 execroot genrules converted, including the two awk ones (their
  reference cwd is in the SOURCE tree, src-ref/tools/objtool — the gate now
  also maps a source-root cwd: the mirror of a source dir is
  $(GENDIR)/<its package path>, inside the build-root mirror, so `../` hops
  land the same). built_in_fixup_a's `ar m` chain converts too (the
  tree_recipe refusal relaxed to plain creates only).
- 93 tree_recipe rules, 0 genrules in BUILD.bazel, no `_RECIPE_ENV` text,
  `_COMMON_ENV` hoisted once, 92 rules carry `env_map`.
- env_map rendering bug caught before it shipped: keyword args must be bare
  identifiers (`dict(_COMMON_ENV, K = "v")`, not `"K" = "v"`); guarded with
  an identifier check that falls back to the string form.
- Unit tests +3 (env as mapping / no-common-part dict / execroot verbatim
  replay) — 85/85; all suites green.
- Remaining: packages_vs_dirs 9.75 (next run), manual_rules 5.0, grp_splits
  4.61, todo 3.96, hermeticity 2.81, include_flags 1.87, repeated_flags 2.45.
- Next: check-invariants CORPUS=1, commit tool changes; then step 3 (manual
  tags → wiring) and step 4 (TODO hygiene).

## 02:00–02:30 steps 4+6: computed TODOs + semantic grp names
- Blanket sandbox TODO removed from the emitter: `_recipe_prog_words` /
  `_unsupplied_recipe_progs` parse the composed command lines (quote-aware
  `_stages` splitter), take each stage's first word, and emit a TODO naming
  the programs a reviewer owes an opinion on -- anything not staged by the
  rule, not a mapped compiler/binutils, not a host-tool the rule supplies,
  and outside the shell's own PATH contract (sh/bash/env + the coreutils
  run_shell contract). ar_archive rules get no TODO at all.
- BUILD.bazel TODO entries 179 → 141, and the earlier junk TODOs (first
  words like `vmlinux.o`, `.comment`, `__X32_SYSCALL_BIT`, `vmlinux.lds`
  parsed off flag positions) are gone -- the fix was passing composed
  lines, not raw argv tokens.
- Remaining 141: 111 per-source flag-variant notes, 15 host-tool
  copts/linkopts checks, 4 genuine prog TODOs (awk x3, objtool), 2 link
  flags naming outside-package files, 2 lexer/parser capture notes.
- grp naming: `_grp_name` names each per-source group after the source it
  compiles (`exe_grp1` → `exe_c`), collision-guarded; zero `_grpN`
  fallbacks remain in BUILD.bazel.
- Tests: test_emit_build 86/86 (new: computed-TODO test -- mapped recipe
  gets none, `awk` recipe gets one); all 22 suites green.
- check-invariants.sh CORPUS=1: INVARIANTS OK, corpus 37 converged before
  and after. Tool changes committed (d77313d).

## 02:30–03:10 endgame: all gates green, IDIOM 21.0 — publish: release
- bazel build //... GREEN after the re-emit (338 actions; 227 re-ran from
  the grp renames, rest cache hits). PARITY re-run: errors=6 warnings=16,
  same classes as baseline; artifacts converged 0 errors.
- IDIOM **21.0** (from 49.9 at run start, 30.5 after steps 1+2):
  packages_vs_dirs 9.7, manual_rules 5.0 (honest floor — t is 1.0 with
  genrules=1 regardless of the manual count), repeated_flags 2.45,
  include_flags 1.87, hermeticity 0.8, todo ~1.1 (141 real + 112 prose
  cross-refs — left as-is, not detector-gamed), genrules_per_tu ~0.1.
- Endgame gates on the final tree: HERMETIC OK (clean container);
  build-image bzImage 2417664 B — byte-identical size to the
  manual-2026-10-04b release's, no artifact drift; **BOOT-SSH OK after
  3s: Linux 7.2.0**. (One false start: `OUT=… boot-ssh-test.sh $OUT/…`
  expanded $OUT before the assignment — empty → `/bzImage`; reran with
  the real path, 3s.)
- Tool commits this run: 301c50f (steps 1+2), d77313d (steps 4+6); both
  gated with CORPUS=1 INVARIANTS OK (37/37 corpus). Step 5 (toolchain
  flag dedup, ~0.1 pts) skipped — not worth a gate cycle for 0.1.
- Step 3 (manual tags → wiring) dropped with evidence: manual_rules t =
  clamp(len(manual)/max(1,len(genrules))*2) = 1.0 whenever genrules=1,
  so no score gain; untagging the 14 host-tool cc_binaries would add
  duplicate target-config actions to aquery and the 2 objtool fixdeps
  are genuinely unwired.
- report.md final: disclosure (env-map re-spelling), results, acceptance,
  verdict — **publish: release** (next run's threshold: 21.0; next lever:
  packages_vs_dirs 9.7).
