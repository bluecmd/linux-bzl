# plan — 2026-10-13

## Where we start
PARITY build=GREEN diff=NOT converged errors=6 warnings=15 (the accepted
release baseline profile: generated_content_diff x4 nondeterministic-content
files + defines/extra_tu warning classes), artifacts converged 0 errors.
IDIOM 5.2 (threshold 5.2 — the score has stopped guiding; the owner's two
questions take over). HERMETIC OK, BOOT-SSH OK carried. Layer at c3a4913,
tool at 034a03f.

## What I will attack (the owner's order, from the 2026-10-11 feedback)

1. **Purpose-built rules replacing `tree_recipe`** (93 instances). Survey of
   the recipes by kind (from the emitted BUILD files):
   - WRAP headers: `echo "#include <asm-generic/X.h>" > out` — ~40
     instances (arch/x86 generated asm/uapi headers). A `wrap_header` rule:
     `out` + `include`. Fully derivable from attrs.
   - COPY recipes: `cp src out` under Kbuild's filechk/cp glue — ~8
     (defkeymap_c, ucs tables, initramfs_inc_data, vmlinux.a,
     checked-atomic-*, checked-atomic-long). A copy rule: `src` + `out`.
   - objcopy: `llvm-objcopy <flags> src out` — ~8 (vmlinux.bin, realmode.bin,
     `--prefix-symbols=__pi_` pi.o twins, vdso64.so strip, setup.bin...).
     An objcopy rule: `src` + `out` + `args`.
   - asm-offsets/filechk headers: sed over a `-*-offsets.s` — ~6
     (asm-offsets.h, bounds.h, rq-offsets.h, devicetable-offsets.h...).
     A rule: `src` + `out` + `guard`.
   - `.lds.S` preprocessing (clang -E): ~4 (vmlinux.lds, realmode.lds,
     vdso64.lds, compressed vmlinux.lds). A rule: `srcs` + `out` +
     the defines (the -I/-include path is the kernel's global one).
   - the kconfig step (`auto_conf`), `modules.builtin`, the version files
     (compile.h, utsrelease.h, utsversion.h, .version, version.h,
     timeconst.h via bc), the vmlinux link chain (vmlinux.o, vmlinux.a,
     vmlinux, System.map, vmlinux.symvers, built-in-fixup.a), syscall
     tbl/hdr generators (sh scripts + args — 8), the vdso image chain,
     the bzImage chain, the image initramfs (usr/).
   One-offs become hand-written genrules with a cmd a person would write.
   Each recurring kind gets a small rule with a few meaningful attributes;
   the rule's implementation reproduces the reference's meaningful command
   stages (the differ already drops the glue/mkdir/cp/export/cd/trap as
   bookkeeping — verified: today's tree_recipe commands carry all that and
   the wrap recipes converge silently), so parity does not move.
   The shared mirror machinery (staging, exported variables, wrappers, cd,
   env) moves into one helper module the rules load; `tree_recipe` keeps
   working over it (per-package `_COMMON_ENV` moves into the rule module —
   owner item 3's env part).
   **Done when**: 0 (or only genuinely one-off) `tree_recipe` calls remain,
   parity at the baseline profile, build green.
2. **Per-package boilerplate kill** (owner item 3): load lines only for what
   the file uses; the header-glob `cc_library` per package goes (directory
   headers become the library's `hdrs`); `exports_files` only where read
   cross-package.
3. **The kernel library macro owns the archive** (owner item 2): a
   directory's BUILD becomes one call with `srcs` and the directory's real
   extras; objects+archive inside it.
4. **flex/bison** for lexer.lex.c/parser.tab.c (owner: the runner apt set
   has flex/bison — HERMETIC_APT already lists them; a pinned-version check
   vs the reference's bytes is the risk to report).

## How I verify each step
Re-emit (or hand-edit the layer) → `bazel build //... --keep_going` →
parity.sh (build/aquery/diff/artifacts/IDIOM, TARGETS=//...) → the diff
profile must stay the baseline (errors=6: the four nondeterministic-content
files; warnings in the known classes). Tool changes: suites green in the
any2bazel worktree + check-invariants.sh, committed small. Image + boot-ssh
re-run at the end; hermetic-build.sh once the layer is final.

## Out of scope this run (recorded, not attempted)
- The full `kbuild_library` macro (item 3 above) if item 1 consumes the
  budget: it is the largest structural change and needs its own verified
  cycle.
- Emitters' load-dedup, bzImage name collision, review-note wording: taken
  opportunistically when they touch files I am already editing.
