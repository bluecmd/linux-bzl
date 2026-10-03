# plan — manual-2026-10-03

Start state: PARITY build=RED diff=NOT converged errors=13 warnings=8,
artifacts skipped (build red). Three red genrules, one class (smoke-dry
journal): consumer genrules whose inputs are intermediates written inside
*other* recipe lines that the extractor never models:

1. `//:vmlinux_symvers` — modpost reads `vmlinux.o`; the capture records the
   recipe (`ld.lld -r -o vmlinux.o --whole-archive vmlinux.a … ; objtool
   --link vmlinux.o`) but `vmlinux.o` is a "library-ish" intermediate the
   extractor drops, so no producer action → genrule srcs empty → modpost
   "ignores" the missing input and never writes `.vmlinux.export.c` →
   "declared output not created".
2. `//:vdso64_image_c` — vdso2c reads both `vdso64.so.dbg` (modeled,
   cc_raw_link) and the stripped `vdso64.so` (objcopy inside the same
   recipe line; unmodeled).
3. `//:tmp_vmlinux_nm_sort` — link-vmlinux.sh genrule gets only 9 recorded
   inputs; the nested `make -f scripts/Makefile.vmlinux_o`-style child work
   (version-timestamp.o) and the whole vmlinux object graph (vmlinux.o,
   built-in.a pieces) never reach its srcs, so GNU make falls back to
   builtin rules and dies (`m2c: No such file`).

## Order of attack

1. **Tool: model intra-recipe intermediates** (`extract_capture.py`).
   The capture is a strace file-trace capture — every exec carries
   `reads`/`writes`/`redirects`/`appends`, so the evidence is already
   there; only the model is missing. The generic shape: a build-phase
   file the trace names that (a) no argv-classified action produces,
   (b) IS consumed by a later build action (modpost, vdso2c,
   link-vmlinux.sh — i.e. a `cwd_dependent` genrule script, not just a
   link target), and (c) is a link/archive/object-shaped artifact. Today
   `FileTrace.useful` filters those out as "objects, libraries, …".
   Generalize: when the *only* consumers of such a file are
   recipe-line/generator actions (not a modeled link or archive target),
   it is a real intermediate and its recipe line must be emitted too.
   Specifically expect three actions:
   - `vmlinux.o` ← recipe line (`sh -c 'LD vmlinux.o'`): ld.lld -r reads
     vmlinux.a, objtool appends. Inputs wired to vmlinux.a producer.
   - `vmlinux.a` ← recipe line (`cat built-in-fixup.a > vmlinux.a`).
   - stripped `vdso64.so` ← the vdso recipe line (link + objcopy).
   Done = `bazel build` turns green for the three genrules and their
   consumers, without hand edits to BUILD.bazel.
2. **Re-run parity** (`A2B_SCRIPTS=wt-kernel/scripts parity.sh`). Expect
   the build to go GREEN, then the post-build content diffs
   (zoffset.h/pasyms.h/voffset.h) to clear and a new, richer diff to
   appear (link-vmlinux.sh now carrying the real object graph).
3. **Config-side accepts** (conventions.json / any2bazel.json): kconfig
   `lexer.lex.c`/`parser.tab.c/.h` codegen_map "committed"; `conf`→
   `auto_conf` tool_map; include-prefix views for the vdso64 layout links.
4. **Rustc probe** for CONFIG_RUSTC_LLVM_MAJOR_VERSION, `-B$(GENDIR)/symbolic`
   normalization, `linux-vdso` external dep.
5. **Boot test**: build-image.sh then boot-ssh-test.sh once bzImage builds.

## What "done" is this run

- The three red genrules green via tool-side modeling (no BUILD hand
  edits), or a documented reason why they cannot converge generically.
- If the build goes green: post-build content diffs re-assessed; as many
  of the 13 errors cleared as the tool/config honestly allow.
- Boot test if the image builds. Verdict per protocol.

## Non-goals

- No hand-patching the emitted BUILD.bazel (emitter would overwrite it).
- No image/boot/initrd/QEMU/SSH knowledge in any2bazel scripts/.
