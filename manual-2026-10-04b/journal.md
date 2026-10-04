# journal — manual-2026-10-04b

## 2026-10-04 — start
- Read feedback + 10-03b report. Start state: parity GREEN (6 errors/17
  warnings, artifacts converged 0), idiom 75.9 (= threshold), hermetic FAILED
  (objtool gelf.h). Plan written (plan.md), report.md skeleton written.
- The idiom decomposition (contribution = t*weight): recipe_replay 14.6,
  genrules_per_tu 10.0, env_replayed 10.0, packages_vs_dirs 9.7,
  shape_duplicates 8.3, hermeticity 10.0 (of which ~9.2 is real: 91 toolchain
  flags spelled in copts; 1 pt is this host's uncommitted user.bazelrc
  --action_env lines, not part of the released layer), grp_splits 4.6,
  todo 4.0. packages_vs_dirs (3 packages / 119 dirs) NOT this run — kbuild
  include layout lives on one-tree single-package assumptions.
- Explore agent mapped the emitter: 630 in-cwd genrules = 554 ar recipes +
  ~76 preprocess/sh-recipe genrules, all sharing _emit_genrule_in_cwd
  (emit_build.py:2823). The A2B_CC/A2B_* anchor exports (2999-3009) are the
  shared env-replay shape. Plan: a `kbuild_ar` layer rule behind a
  conventions `ar_recipe` knob (mirror of raw_link/cc_objects), then the
  remaining in-cwd families, then _RECIPE_ENV -> per-rule env attrs.

## 2026-10-04 — hermetic libelf (layer work)
- elfutils 0.194 (host's version, sha256
  09e2ff033d39baa8b388a2d7fbc5390bfde99ae3b7c67c7daaf7433fbcf0f01e) fetched
  as an http_archive with a handwritten BUILD
  (bazel/third_party/elfutils.BUILD.bazel): only the libelf subset, compiles
  as-is with a 15-line config.h written by a skylib write_file (verified
  with the layer's clang outside Bazel first: 116 TUs, 0 errors).
- zlib (elf_compress.c needs it unconditionally) via bzlmod
  `bazel_dep(name="zlib", version="1.3.1.bcr.3")` -> @zlib//:z.
- //:objtool: linkopts -lelf -> [], deps += @elfutils//:libelf.
- Learned: host-tool cc_binary targets carry tags=["manual"], so `//...`
  never builds them in the target config; the kernel toolchain declares NO
  builtin include dirs, so a direct `bazel build //:objtool` fails the
  absolute-include check (same for //:modpost — pre-existing). Only the
  exec-config build (via genrule tools, //bazel/image:image) is real.
- objtool artifacts are NOT in the artifact diff set (only realmode/boot/
  compressed/vdso64), so switching libelf source cannot regress parity
  artifacts.

## 2026-10-04 — ar_archive rule (layer + tool)
- Emitter knob `ar_archive` in conventions.json (load label +
  `@kernel_llvm//:bin/llvm-ar`): a single-step genrule whose cmd is
  `<AR> <op> <archive> <members...>` becomes an `ar_archive(...)` rule
  call; members keep the reference's order (link order), everything ar
  opens is declared in srcs, mnemonic stays CppArchive so the differ
  still compares the line. Edit chains (built_in_fixup_a's mPi after
  cDPrST) keep the recipe genrule.
- Emit test suite 77/77 (two new tests); committed to wt-kernel e8483b8.
- Re-emitted layer BUILD: 553 ar_archive calls, RC=0. parity.sh running.
- hermetic-build.sh running in the podman oracle with the fetched
  elfutils/zlib (host build was GREEN before it started).
- HERMETIC OK at 12:10 (//bazel/image:image in the podman oracle; last.txt).
  First release-gate satisfied. Will re-run at the end after remaining layer
  changes.
- First parity with ar_archive rules: build=RED, errors=80 -- `llvm-ar: error:
  <member>: No such file or directory`. Root cause: the rule passed members as
  package-relative strings, but the action sandbox materializes generated
  inputs under the genfiles tree; the genrule replay got away with it because
  it `cd $(GENDIR)`. Fix: `members` is now a label list; the rule spells each
  file's own path (`f.path`). Emitter maps operands to labels (output_labels
  entries by their rule label, everything else by its package-relative file
  label). Re-emitted; parity running again.
- Second parity: still RED errors=80, but a different cause -- `invalid label
  '::arch_x86_platform_atom_built_in_a'`: output_labels values already carry
  the leading colon and I prefixed another. One-line fix (defensive:
  prefix only when absent); re-emitted; queries for the previously failing
  targets resolve. Committed 3990072. Parity running again.
- Third parity: RED errors=80 again, but finally the real cause: `ar_archive
  rule ... is misplaced here (expected genrule, cc_library, ...) and does not
  have mandatory providers: 'CcInfo'` — the aggregates put archive labels in
  deps (the reference's graph edges; Bazel tolerates a genrule there, my rule
  is not on the rule-class whitelist). Verified with the old BUILD: grp1
  analyzes green with the genrule in deps. Fix: ar_archive now also provides
  CcInfo (the archive as a LibraryToLink static_library, private-module
  pattern like cc_objects; no extra actions created). grp1 + entry grp1
  analyze and build green. Parity running again (4th).
- FOURTH parity: **PARITY build=GREEN diff=NOT converged errors=6 warnings=17
  artifacts=converged** — exactly the run-start baseline. IDIOM score=66.1
  (was 75.9, threshold; genrules 647->94, dirs 119). The ar_archive
  conversion is the whole delta. Starting build-image.sh.
- **BOOT-SSH OK after 3s: uname 7.2.0** — the re-emitted layer (553
  ar_archive rules) boots and accepts SSH. All four gates pass on this tree:
  parity green (baseline 6/17, artifacts converged), HERMETIC OK, IDIOM 66.1
  (< 75.9), boot OK. Tree snapshotted to /tmp/release-build-ar.bzl (+
  conventions, any2bazel.json) as the fallback release state.
- check-invariants.sh with CORPUS=1: INVARIANTS OK, corpus 37 converged
  before, 37 after (tool commits e8483b8 + 3990072 are mergeable).

## bc hermetic (afternoon)
- Goal: drop `user.bazelrc` (2 --action_env=PATH lines = 10.0 of idiom's
  hermeticity t) by taking bc (the only program the layer needs from the
  machine's PATH — hostbin holds only bc, /usr/bin/bc absent here) from a
  pinned Bazel external. GNU bc 1.07.1 http_archive + handwritten
  `bazel/third_party/bc.BUILD.bazel` reproducing upstream's two-stage
  libmath bootstrap (fbc against the `{0}` placeholder -> `fbc -c libmath.b`
  -> fix-libmath_h -> the real bc).
- Three fixes to the handwritten BUILD while iterating on `bazel build
  @bc//:bc`:
  1. "bcdefs.h file not found": Bazel stages only declared inputs — headers
     the .c list quote-includes were not in srcs. Added the tree's headers
     (bc/*.h, h/{getopt,number}.h) and the generated ones (:config_gen,
     :libmath) to both cc_binaries' srcs.
  2. My awk re-implementation of fix-libmath_h was wrong twice: the ed
     script is `1,$s/$/",/` + `2,$s/^/"/` + `$,$d` + `$,$s/,$$/,0}/` — the
     replacement is `,0}` (keeps the comma: the NULL-sentinel element), and
     NOTHING is dropped from a raw output that ends with a final newline.
     `"...@r"0}` / `"@i"0}` (missing comma) is invalid C — verified with a
     3-line C repro against clang and gcc. Correct: every raw line quoted,
     first opens `{"`, last ends `",0}`.
  3. `absolute path inclusion(s)`: the failing compiles ran in the TARGET
     config (kernel platform -> the freestanding kernel toolchain, builtin
     dirs = []). A red herring: as a genrule `tool`, bc builds in the EXEC
     configuration, where the plain toolchains_llvm toolchain (which
     declares /usr/include and its resource dir) applies — confirmed by
     cquery-subcommand inspection. I briefly added an
     `extra_builtin_include_directories` attr to kernel_llvm_toolchain.bzl
     and reverted it (kept the `or "[]"` cleanup the tool already had).
- A scratch genrule (`//scratch_bc`, deleted after) proved the whole chain:
  `bazel build` green, and the Bazel-built bc produces
  **byte-identical timeconst.h** vs the reference's
  include/generated/timeconst.h. (First attempt hung: `bc -q file </dev/null`
  eats the `echo 250 |` pipe — the reference recipe has no redirect;
  timeconst.bc reads hz from stdin.)
- Emitter change (wt-kernel, commit b60e909): conventions `host_tools`
  values may now be **labels** — `{"bc": "@bc//:bc"}`. A cwd-mirrored
  genrule copies `$(location <label>)` into its `.a2b-bin/<name>` bin dir
  and prepends it to the recipe's PATH; the label joins the genrule's
  `tools` (the cc_binary builds for the exec platform); all other
  host_tools substitution sites (shebang interpreters, plain-genrule i==0
  words, _shebang) keep the reference's word when the value is a label
  instead of spelling the label as a command. Suites 78/78
  (new test_host_tool_by_label_is_copied_into_the_bin_dir) + all suites
  green. REFERENCE-config.md documents the label shape.
- conventions.json: `"host_tools": {"bc": "@bc//:bc"}`; re-emitted BUILD
  (timeconst_h: `cp -f $(location @bc//:bc)` + `tools = ["@bc//:bc"]`,
  recipe keeps `bc -q`). **user.bazelrc moved out of the tree** (saved to
  /tmp/user.bazelrc.saved). Full parity running (action caches invalidated
  by the action_env change — long rebuild).
- **FIFTH parity (after user.bazelrc removal): PARITY build=GREEN diff=NOT
  converged errors=6 warnings=17 artifacts=converged 0 errors** — the same
  baseline, and **IDIOM score=58.9** (was 66.1; threshold 75.9). The
  whole delta is the bc external + host_tools-label wiring replacing the
  host-local --action_env crutch. The layer tree now takes nothing from the
  machine's PATH for its own build steps.
- **BOOT-SSH OK after 3s: uname 7.2.0** on the re-emitted tree (build-image
  byte-identical sizes: bzImage 2413568, initrd 2623909). Hermetic re-run
  started 14:22 (final gate on the new tree).
- Learned the hard way: the objtool elfutils wiring (`deps += @elfutils//:libelf`,
  `-lelf` gone) was a manual BUILD.bazel edit — every re-emit wiped it, and the
  two later re-emits (ar_archive, bc) silently dropped it. The snapshot
  /tmp/release-build-ar.bzl ALSO lacks it (the 12:10 hermetic OK ran on the
  pre-ar_archive tree). Consequence: hermetic went RED again (gelf.h).
- Proper fix (tool commit 4fa0f89): `_render_host_tools` routes a `-l` through
  the conventions resolver when it has an entry — `{"elf": {"deps":
  ["@elfutils//:libelf"], "linkopts": []}}` in conventions.json — so the
  wiring is carried by the conventions, not the emitted file. Unmapped `-l`
  stays a linkopt. Suites 79/79. Re-emitted: objtool `deps =
  ["@elfutils//:libelf"]`, no `-lelf`.
- **HERMETIC OK 15:0x** on the new tree (bc external + objtool wiring via
  conventions). Host image build + **BOOT-SSH OK after 3s: 7.2.0**.
- Sixth parity running for the final record.

## tree_recipe lever (evening 2026-10-04)

- Converted the cwd-recipe genrules to the dedicated `tree_recipe` rule class
  (76 of 92; 17 genrules remain — plain `$(location)`-spelled recipes run in
  the execroot, plus built_in_fixup_a and the image initrd). Two structural
  bugs surfaced and were fixed in emit_build.py:
  - the `_made_from`/`_made_with` cycle-exclusion closures walked only
    `r.kind == "genrule"`, so a converted rule dropped
    `pkg_generated_for_realmode_elf` back to the package-wide group and the
    tree cycled (`realmode.elf_objs → … pasyms.h → … realmode.elf_objs`).
    New `_recipe_kinds()`/`_recipe_inputs()` helpers walk every recipe-carrying
    rule class (genrule, ar_archive, tree_recipe) and its `srcs`/`refresh`/
    `stage` inputs. Root-caused by bazel-query diffing old vs new.
  - a `$(obj)/../<out>` spelling (voffset_h) needs the hop's directory to
    exist; the old genrule rode on dirs other actions had made. Emitter gained
    `_out_spell_dirs` (walks back over path chars from the match, keeps the
    hop's target dir), rule gained the `out_dirs` attr + mkdirs. Lesson: in
    the linux-sandbox execroot a rule must mkdir every dir its recipe's
    spellings traverse.
- **Full `bazel build //... --keep_going` GREEN (exit 0, 0 errors)** — first
  time the whole converted tree builds. Representative shapes checked:
  errno_h, timeconst_h (bc), auto_conf (stage_tools), asm_offsets_s (674
  srcs/refresh), vmlinux_symvers, tmp_vmlinux_nm_sort, vdso64_image_c,
  initramfs_data_cpio, vmlinux_o, voffset_h/zoffset_h (out_dirs).
- Unit tests +3 in test_emit_build.py (82/82): knob on/off emission, the
  `../`-hop out_dirs, and the cycle-exclusion regression parameterized over
  genrule and tree_recipe. All suites green.
- **SIXTH parity (tree_recipe build): PARITY build=GREEN diff=NOT converged
  errors=6 warnings=16 artifacts=converged 0 errors; IDIOM score=49.9**
  (was 58.9; threshold 75.9). genrules 94 → 18 in the idiom census. Error
  profile identical to the fifth parity's (same 6 errors, same classes);
  warnings down one. The zoffset_h diff improved: lines 1–4 now match the
  reference (ZO__data/edata/ehead/end), residual is the same small
  layout-drift class as voffset (ZO__text +0x80, ZO_kernel_info +0x370,
  ZO_z_input_len +0x80). Hermetic on THIS tree and boot-ssh still pending —
  the 15:0x OK predates the conversion.
- **HERMETIC OK 19:05 on the tree_recipe tree** (162 fresh
  processwrapper-sandbox actions in the container = the new rules; 3,107
  cache hits = actions proven hermetic at 15:08). **BOOT-SSH OK after 3s:
  7.2.0** on the same tree (bzImage 2417664 B). **INVARIANTS OK, corpus
  37/37 before and after** (tool commit 9093307). Release snapshots
  refreshed: /tmp/release-BUILD.bazel.treerecipe,
  /tmp/release-conventions.json.treerecipe, /tmp/release-tree_recipe.bzl.
- Disclosed, not taken: the `_RECIPE_ENV` plain-string re-spelling
  (~10 more idiom points) — margin already comfortable at 49.9 vs 75.9.
- All four gates hold on the final tree. Verdict stands: **publish:
  release**.
