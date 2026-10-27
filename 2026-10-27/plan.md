# plan — 2026-10-27

## Start state

PARITY build=GREEN diff=converged errors=0 warnings=14 artifacts=converged,
IDIOM 0.0 (threshold 5.2), boot + hermetic green at the 2026-10-25 release
(aff0f70a6). Feedback file empty. So this run's goal is the residuals the
2026-10-25 report left on the table — parity (warnings floor) and honest
review-asks — not the idiom score, which has no headroom the score can see.

## The three residuals, and what I will attack

1. **The root's 1 open TODO — the objtool-from-host ask on `vmlinux_o` —
   looks stale.** The emitted rule already carries
   `stage_tools = [":objtool"]` / `stage_dests = ["tools/objtool/objtool"]`
   (the binary is built for the exec platform and copied into the mirror
   tree at the path the recipe spells), yet the emitter's TODO matcher
   (`_unsupplied_recipe_progs`) does not recognize the recipe's
   `./tools/objtool/objtool` word against the `./`-less stage_dest. The
   ask ("runs objtool from the host PATH") is factually wrong on the
   layer. **Fix: emitter, generic** — a `./`-prefixed recipe program word
   matches its bare stage_dest form (the reference ran in the tree root,
   so `./x` is `x`). Expected: root TODOs 1 → 0. Verified by re-emit gate
   (the only expected layer diff is the root TODO line) + parity.
2. **The 2 auto_conf generator-swap warnings** (diff classes the
   tree_recipe's staged shell script as a different tool than the
   reference's `scripts/kconfig/conf`; content-verified equal). The
   2026-10-25 journal records why the emitter-side tool_map fix is
   wrong-shape (the emit's own output-path entry would overwrite it);
   the honest fix is **diff.py-side, generic**: a tree_recipe's tool
   stage carrying its inner tool's identity. Expected: warnings 14 → 12.
3. **The 7 `defines_diff` warnings on tools/lib/subcmd** — the exec
   toolchain's opt defines vs the reference's plain compile. Removing
   them risks changing the artifacts that are currently byte-equal
   (fortify codegen); the 2026-10-25 report called them cosmetic. I will
   investigate whether a legitimate generic mechanism exists (a toolchain
   feature boundary the layer can select) and otherwise re-record the
   floor as-is.

## Order

1. Confirm the start state (parity on the committed layer, cache-warm).
2. Fix 1 (emitter, `./` vs stage_dests): suites → commit → re-emit gate
   → install → parity → image → boot.
3. Fix 2 (diff.py tool-stage identity): suites + corpus → commit →
   re-run parity diff for warnings 14 → 12.
4. Fix 3 investigation; record the floor.
5. Invariants (CORPUS=1) + hermetic on the final layer; report; verdict.

## Done

All gates green (parity converged, image, BOOT-SSH, invariants, hermetic),
root TODOs 0, warnings ≤ 14 (12 if fix 2 lands), IDIOM ≤ 0.0 + threshold
held, and the verdict `publish: release` if the boot test passes.
