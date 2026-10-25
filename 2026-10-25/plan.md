# plan — 2026-10-25

## State at start (re-measured this session)

- PARITY build=GREEN diff=converged errors=0 warnings=14 artifacts=converged 0
  errors — `parity.sh linux` re-run on the committed layer (c1058a1ae, the
  2026-10-23 emit53 install): **converged**, IDIOM score=0.2 (rules=2930,
  tus=1236, genrules=1, dirs=120).
- Feedback file empty this run (no owner input beyond the standing goal).
- So: this run's goal is the idiom floor (hermeticity passed on the same tree
  in the last run; re-proved at the end if anything changes).

## Where the 0.2 lives (idiom.json, t x weight)

| detector | count | t | contribution | what it is |
|---|---|---|---|---|
| manual_rules | 3 | 0.0205 | **0.10** | `//:tools_objtool_fixdep`, `//:tools_objtool_libsubcmd_fixdep` (two identical cc_binaries of tools/build/fixdep.c the reference built in its tools sub-builds; the layer's consumed fixdep is //scripts/basic:fixdep — these two are wired to nothing), `//:modules_builtin` (tree_recipe emitting modules.builtin; nothing in the build or the deliverable consumes it) |
| todo | 16 (root pkg) | 0.0055 | **0.03** | 14x "host tool `X`: check its copts/linkopts build with the exec toolchain" + vmlinux_o objtool + mkpiggy-adjacent |
| genrules_per_tu | 1 | 0.0016 | 0.016 | the one genrule (usr/initramfs_data.cpio — stamped/replay_args) |
| include_flags | 21 | 0.0014 | 0.007 | -I in copts |
| repeated_flags | 22 | 0.0004 | 0.002 | |

## Attack order

1. **manual_rules → 0** (main lever, 0.10):
   - Tool change (generic): the emitter should not emit a host tool
     `cc_binary` whose binary output no action consumes — it never runs
     (tags=manual keeps it out of `//...`), it only adds an unwired rule and
     an open review ask. Same logic exists for generator outputs
     (`_is_sink_deliverable`); tools have no counterpart yet.
   - `//:modules_builtin`: first establish what artifact_diff/parity actually
     guards (does the layer have to produce modules.builtin at all?). If
     nothing guards it and nothing consumes it, the honest shape is to not
     emit it (the emitter's `_is_sink_deliverable` classes it "a deliverable"
     — for this project the deliverable set is the bzImage only). If parity
     does guard the file, keep the rule and accept the residual (it is
     genuinely an on-purpose artifact of the reference build).
   - Parity as the regression test after each step.
2. **todo → the honest residue** (0.03): the 14 host-tool asks are the same
   question repeated. Answer it this run the way it can actually be answered:
   build every host tool target with the exec toolchain (they are manual-tagged,
   so `bazel build //:X`), and record the verification in conventions.json
   (a generic review-answer record, the same shape as codegen.tool_map);
   the emitter stops asking for tools the record covers. Not a cosmetic move:
   the record is what a re-emit consults.
3. **include_flags / repeated_flags**: inspect the 21/22 instances; only act
   where a generic rule-level mechanism exists (e.g. host tools' -I into
   `includes`), never by hand-editing an emitted file. Small gain; do last.
4. Gates on the final layer: parity, BOOT-SSH, invariants (CORPUS=1 for tool
   changes), hermetic container build. Commit tool changes as they land.

## Done

- IDIOM score below 0.2 with parity converged, 0 errors, on the full tree;
  boot + hermetic still green; tool suites + corpus green; report + verdict.
