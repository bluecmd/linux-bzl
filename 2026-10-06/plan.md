# plan — run 2026-10-06

State at start: PARITY build=GREEN diff=NOT converged errors=6 warnings=16
artifacts=converged 0 errors; IDIOM 49.9 (threshold 49.9 — must go lower);
HERMETIC OK (manual-2026-10-04b); BOOT-SSH OK. Re-verified the parity line
at 00:12 on the untouched tree: identical.

This run's goal is the idiom score. Score decomposition (points = t·weight,
from models/kernel/idiom.json):

| detector         | pts  | lever |
|------------------|------|-------|
| env_replayed     | 10.0 | 131 env names = the 96-name `_RECIPE_ENV` blob spelled as `" ".join(["K=V",…])` + ~35 spelled inside the 17 genrule cmds |
| packages_vs_dirs | 9.75 | 3 packages for 119 source dirs |
| shape_duplicates | 8.33 | 15 repeats of the env-prefixed execroot-genrule shape over 18 genrules |
| manual_rules     | 5.0  | 21 rules tagged `manual` (14 host-tool cc_binaries, 2 objtool fixdeps, the boot endgame chain) |
| grp_splits       | 4.61 | 112 `_grpN` flag groups |
| todo             | 3.96 | 895 TODOs: ~340 blanket "verify the cmd runs in the sandbox" (one per recipe rule AND per ar_archive), 111 "compiles X with different flags", misc |
| repeated_flags   | 2.45 | 11051 repeated flag literals |
| hermeticity      | 2.81 | 91 toolchain flags still spelled in copts + host_tools bc |
| include_flags    | 1.87 | 2109 -I in copts |
| genrules_per_tu  | 0.29 | 18 genrules |
| recipe_replay    | 0.83 | 1 genrule (built_in_fixup_a) still replaying |

## What I will attack, in order

1. **Convert the remaining 17 execroot genrules to `tree_recipe`** (+ the
   ar-edit-chain `built_in_fixup_a`; only //bazel/image:initrd stays a
   genrule). These are the recipes the reference ran in the build root with
   outputs/inputs at build-root-relative paths — which in the layer already
   sit at their logical paths under $(GENDIR). So `tree_recipe(cwd=".")`
   replays them verbatim (no mirror staging beyond sources/tools), instead
   of the current genrule that respells every word into `$(location)`.
   The differ strips env assignments and resolves the last `cd`, so the
   recipe line compares exactly as it does today.
   Gains: shape_duplicates 8.33→0, recipe_replay→0, genrules_per_tu→~0.02.
2. **Env as data, not command text** (same step): `tree_recipe.env` becomes
   a `string_dict`; the emitter hoists the common env into a `_COMMON_ENV`
   dict constant and renders per-rule env as `dict(_COMMON_ENV, K = …)`;
   the rule composes the same `K=V` prefix onto the recipe line internally
   (shell-quoting the values as `_shell_word` does today). The executed
   environment is unchanged — this is the same 96 variables the reference's
   make exported, now spelled once as a mapping instead of as command text
   per rule. Gains: env_replayed 10→~0 (disclosed as a re-spelling in the
   report, like the last run's disclosure).
3. **manual tags → wiring**: the 14 host-tool cc_binaries are consumed as
   `tools` of the rules that run them — drop the tag. The boot endgame
   chain (setup_bin, arch_x86_boot_vmlinux_bin, bzImage, initramfs_data_cpio,
   modules_builtin) gets wired into //bazel/image:image. The two objtool
   fixdeps stay tagged (honest: nothing consumes them; wiring them into
   //:objtool would change the binary).
   Gain: depends on the genrule count after step 1 — with 1 genrule left and
   2 manual rules, t stays 1.0; the detector's t is manual/genrules·2, so
   this step alone may gain nothing. Do it for honesty anyway; revisit if
   the initrd genrule can also leave the class.
4. **TODOs**: (a) ar_archive emission must not emit the genrule sandbox
   TODO (it has no cmd, no host tool — ~250 of the 340); (b) the recipe
   sandbox TODO only when the recipe names a tool the build does not supply
   (PATH-found words the conventions don't map), not unconditionally;
   (c) see what remains. Gain up to ~3.
5. **Toolchain flags in copts (91)**: the emitter drops a copt the toolchain
   probe says the toolchain already supplies with the same value. Gain ~0.8.
6. If time remains: grp_splits naming (4.6), repeated_flags/include_flags
   (4.3), or the per-directory package split (9.75 — likely its own run:
   big emitter feature, high parity risk).

## What "done" is

- PARITY stays at the baseline (build=GREEN, errors=6 same classes,
  warnings ≤ 16, artifacts converged 0 errors) after every step.
- IDIOM well under 49.9 (target ~26).
- HERMETIC OK re-run on the final tree; build-image.sh + boot-ssh-test.sh
  pass (uname 7.2.0).
- check-invariants.sh with CORPUS=1 on the tool changes.
- report.md current; verdict published.
