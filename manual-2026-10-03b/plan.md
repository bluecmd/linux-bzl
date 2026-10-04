# plan — manual-2026-10-03b

Start state: PARITY build=RED diff=NOT converged errors=76 warnings=22,
artifacts skipped (build red). The previous run was cut off after emitting
v14 from its fixed extractor; its tool work (411/54 lines in
extract_capture.py + emit_build.py) is uncommitted in wt-kernel and is the
cause of both the 76 errors and the single red target.

Diagnosis of this run's start state (from parity-before + build.log + the
emitted BUILD.bazel):

1. **64 of the 76 errors are one bug in the per-source splitter**
   (`emit_build.py:_per_source_split`): `common` is computed token-wise, so
   the `-include` flag of the reference's
   `-include include/linux/compiler_types.h` stayed in the common copts while
   its value went per-source; the next common token (`-D__KERNEL__`) was then
   absorbed as the include's value on the emitted line. Result: 36 targets
   lose `__KERNEL__`, 28 lose `-include compiler_types.h`, and the diff
   reports `-include -D__KERNEL__` on the bazel side. All affected TUs are
   the `-m16` deviating families (arch/x86/boot, boot/compressed) whose C/S
   split is exactly where the pair matters. Fix: compute `common` and the
   per-source extras at unit granularity (`_units`, which already pairs
   `-include x`).

2. **The single build error** (`vdso64.so.dbg` link, version-script symbols
   not defined): `cc_raw_link._own_libraries` stages only the direct dep's
   OWN archive; the parent library `vdso64_so_objs` (srcs=[note.S]) carries
   its other TUs as `grp1..4` cc_library deps, which never merge into a file,
   so the link saw only note.o and every `__vdso_*` symbol was undefined.
   Generic fix (emitter side, same trick as `gen_archived`): when the
   aggregate standing for a raw link's objects was split into flag groups,
   emit the parent as `cc_static_library` (rules_cc+ CppTransitiveArchive
   merges the transitive objects into one file the `$(location)` can name).

3. **Stale cmake side**: parity.sh diffs against
   `models/kernel/model.capture.json`, extracted with the OLD extractor
   (mangled `-B<ref>/symbolic`, orphaned `-soname`, no objtool/subcmd TUs —
   hence `extra_tu` for tools/lib/subcmd and `<unlinked>` compiles).
   Regenerate it with the fixed extractor before judging diffs.

## Order of attack

1. Baseline suites on the uncommitted wt-kernel diff; commit it
   ("Intra-recipe intermediates: objtool subtree, linker operands, recipe
   lines") so the work is not lost. If red, fix or revert first.
2. `_per_source_split` unit-wise common/extras; re-extract + re-emit; parity
   → expect errors 76→~12 (the includes_diff/extra_tu/generated_unrecorded
   remainder).
3. `_render_raw_link` cc_static_library merge → re-emit; expect build GREEN.
4. Regenerate `models/kernel/model.capture.json` with the fixed extractor;
   re-run parity for an honest cmake side; assess the new diff honestly.
5. Remaining diff items as far as they are honest wins: kconfig
   lexer/parser committed codegen_map accepts (conventions), the 5
   includes_diff layout links (include_prefix views), rustc probe.
6. If build green: build-image.sh, boot-ssh-test.sh.

## What "done" is this run

- Build GREEN with the layer emitted purely from the tool, or a documented
  blocker.
- If green: image + boot test attempted; verdict release/pre-release
  accordingly, else `publish: none`.
