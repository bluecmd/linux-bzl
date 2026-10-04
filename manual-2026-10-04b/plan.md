# plan — manual-2026-10-04b

## Start state
PARITY build=GREEN diff=NOT converged errors=6 warnings=17 artifacts=converged 0 errors
IDIOM score=75.9 (threshold 75.9 — a release must stay UNDER it)
HERMETIC FAILED (//bazel/image:image): objtool `gelf.h: file not found` (libelf
is a host dependency: `-lelf` link + `<gelf.h>` include, both satisfied from
/usr on this host, absent in the clean container). A second compile failure
(arch/x86/boot/video.c) shows in the log with its message truncated — needs a
hermetic re-run after the first fix to see it.

## Goals, in order
1. **Hermeticity**: make `//bazel/image:image` build in the clean container.
   The only known blocker is libelf (objtool). Plan: pinned elfutils source
   fetched as a Bazel external (`http_archive` + handwritten BUILD), a
   `cc_library` with gelf.h/libelf.h + libelf, wired into `//:objtool`
   (deps + includes, `-lelf` resolved from the dep). Guard: parity build stays
   GREEN; objtool's own binary is a host tool, its bytes were never part of the
   converged artifact set — verify that assumption with artifact_diff after the
   change. Then `hermetic-build.sh` (~20 min); iterate on whatever the
   container reveals next (video.c …) until HERMETIC OK.
2. **Idiom score** (must land under 75.9 at equal-or-better parity):
   the score decomposes (contribution = t·weight): recipe_replay 14.6,
   genrules_per_tu 10.0, env_replayed 10.0, shape_duplicates 8.3,
   packages_vs_dirs 9.7, grp_splits 4.6, todo 4.0, repeated_flags 2.4,
   include_flags 1.9, hermeticity 10.0 (2 pts of that are this host's
   uncommitted user.bazelrc action_env lines).
   Attack order (biggest, cheapest first):
   a. **The ~585 repeated genrule shapes → real Starlark rules** in
      bazel/rules/ (emitter change): the `$$A2B_AR cDPrST …` ar-recipe
      genrules (~520+) become an `ar`-member-order rule; the `cp -p`-staging +
      `cc -E` refresh genrules (~30) become a preprocess rule. Same commands,
      emitted from rules instead of genrule bodies. Expected: recipe_replay,
      shape_duplicates, env_replayed, genrules_per_tu, tool_as_genrule all
      collapse → roughly −40 pts.
   b. **91 toolchain flags spelled in copts → toolchain features**
      (`--target=x86_64-linux-gnu -fintegrated-as -Werror=… -Werror=…` etc.).
      Fixes the hermeticity detector's 9 real pts and trims repeated_flags.
   c. **TODO comments** (895) — if the emitter's TODOs are stale notes on
      things it now models, retire them at the emitter.
   d. grp_splits (112 `_grpN` splits of cc_per_source_libraries) — investigate
      only if a/b land with time left.
   e. packages_vs_dirs (3 packages for 119 dirs) — NOT this run: the kbuild
      in-tree include layout lives on one-tree single-package assumptions;
      restructuring is its own run.
   Every emitter step: emit → parity.sh GREEN → suites green → small commit.
   CORPUS=1 sweep before any tool-merge claim.
3. Boot test + report. Verdict per acceptance.

## What "done" is
- HERMETIC OK on //bazel/image:image.
- PARITY build=GREEN, artifacts converged, diff errors ≤ current 6 (no
  regression).
- IDIOM score < 75.9 with the same parity.
- BOOT-SSH OK.
- report.md with verdict.
