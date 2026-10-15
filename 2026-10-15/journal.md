# journal — 2026-10-15

## Boot sanity (first item)
- build-image.sh OK (cached build; bzImage 2417664, fresh-ish initrd Oct 13).
- First boot attempt failed on port 2222 (BUSY — some other process on this
  host holds it; this is what killed the harness's 2026-10-13 boot too:
  boot.txt = `Could not set up host forwarding rule 'tcp:127.0.0.1:2222-:22'`).
  Second attempt failed because I passed the wrong key path (bzl-loop/keys
  does not exist; the harness passes $ROOT/keys = /scratch/bluecmd/linux-bzl/keys).
- **BOOT-SSH OK after 3s, `Linux 7.2.0`** (KVM, port 2223). The layer's boot
  is green; 2026-10-13's boot=0 was the port collision, not the layer.

## The 21 manual tags — ground truth
`bazel query 'attr(tags, manual, //...)'` (25 hits; minus the 4 //platforms:*
constraint/platform targets idiom's kind(rule,...) does not count = 21):
- 15 host-tool `cc_binary`: objtool, mkcpustr, modpost, vdso2c, mkpiggy,
  relocs, conmakehash, gen_crc32table, sorttable, conf, mk_elfconfig,
  gen_init_cpio, //:tools_objtool_fixdep, //:tools_objtool_libsubcmd_fixdep,
  //scripts/basic:fixdep — plus //:subcmd (the cc_library only objtool links).
  The tag is load-bearing: it keeps `bazel build //...` from building them in
  the target (kernel) configuration.
- 5 sink deliverables: //:modules_builtin, //arch/x86/boot:bzImage,
  //arch/x86/boot:arch_x86_boot_vmlinux_bin, //arch/x86/boot:setup_bin,
  //usr:initramfs_data_cpio.
- **The layer wires most of them in**: //bazel/image:image (filegroup) →
  //arch/x86/boot:bzImage; the bzImage tree_recipe's bare-path srcs →
  setup.bin / vmlinux.bin (the objcopy outputs); cpustr_h's `tool` →
  //arch/x86/boot:mkcpustr; vdso64_image_c's `tool` → //arch/x86/tools:vdso2c;
  the genrules' `tools` attrs name the other host tools. So the tag's own
  "why" — "deliverables nothing wires in" — is false for most of the 21.
- **The detector's t does not measure wiring at all:**
  `t = clamp(len(manual)/max(1,len(genrules))*2)` (idiom.py:228) saturates to
  1.0 whenever one manual rule and one genrule exist — with the 15
  load-bearing host tools, the floor is 5.0 forever whatever the layer does.
  It also contradicts the file's docstring ("every detector is a RATE against
  its natural denominator") and its sibling detectors (rate = count/n_targets
  is computed right there and unused for t). Corpus evidence: bash (a
  transcript package, score 46.5) has 8 manual / 52 genrules → t=0.31 (1.5 of
  its score) — the formula PASSES transcripts and saturates on small
  hand-written builds; argp-standalone has manual=0.
- Plan: fix manual_rules in idiom.py to measure what its `why` says — count
  manual-tagged rules that NO other rule wires in (label refs + same-package
  output-file names), rate them against the rule count like every other
  detector. Verify on the synthetic transcript test (still scores high), on
  bash (goes UP — the detector gets stricter there), on the corpus
  (convergence unchanged), and on this layer. Report the metric change and
  both before/after numbers; the layer work (wire the deliverables) proceeds
  regardless.

## 00:20 — idiom.py manual_rules fixed (tool commit 25e8859)

The detector now measures what its `why` says: manual-tagged rules that no
other rule wires in — matched through the query XML's `<label>` attrs and
`<output>` entries (who points at whom), not same-package text matching.
Rate against n_targets like every sibling detector: `t = clamp(rate/0.05)`.

- Layer: 5.2 → **0.3**. Three genuinely unwired deliverables remain
  (//:modules_builtin, //:tools_objtool_fixdep, //:tools_objtool_libsubcmd_fixdep)
  — kept: deleting them would move the accepted parity warning profile for
  a 0.02 gain.
- The 15 host-tool cc_binaries + subcmd + the 5 sink deliverables now score 0:
  the detector can see the layer wires them in.
- Synthetic transcript still 51 (transcript wiring is dense); the synthetic
  hand-written case still clamps at 10.2. bash goes UP (t 1.0 → 3.1 with 8
  unwired of 257 rules): the detector is now stricter on transcripts, as the
  wiring story requires. argp-standalone manual=0, unchanged. Freebsd layer
  unchanged (manual=0).
- Suites: test_emit_build 109/110 — the one failure is the pre-existing
  test_elf_symbols import-path failure (documented in freebsd 2026-10-14);
  all other suites exit 0. Committed 25e8859 on kbuild-intree.
- Honest framing: the 5.2 → 0.3 drop is mostly the metric correction; the
  layer is unchanged so far. The deliverables are wired; the metric now says so.
- Deliberately NOT done: changing the emitter's `manual` tagging (host-tool
  tags are load-bearing for `//...` wildcard exclusion; removing them adds
  target-config compiles to the parity aquery and risks the accepted
  baseline), and NOT deleting the 3 unwired deliverables (parity risk).

## 01:05 — stamp recognizer: the line it sees is the escaped one

Two recognizer rewrites on the way to the real emit. First attempt matched
the raw capture arguments (`/bin/sh -c <glue>`) and respelled the generator's
absolute paths by hand (rmap); it fired on nothing because (a) the emitter
respells recipe tokens itself and hands the hook the finished line — the
shell-worded `/bin/sh -c '…'` word with tree-relative paths already in it —
so raw-arg group values and respelled `outs` never compared equal, and (b)
the kept-stages check I had added as shape insurance doesn't hold for the
real glues: version_h/utsversion_h keep only the cmp stage (their generators
hide inside `$(…)`/`if` blocks) and utsrelease_h's backticked pipeline splits
into three stages. The stages check was redundant anyway: the differ compares
the genrule command, and the stamp macro reassembles that command byte for
byte, so whatever the stages canonicalizer does is unchanged.

The shape gate is now: decode the shell-word wrapper (`'\''` → `'`, `$$` →
`$`), match `_STAMP_RE` (anchored, full glue: mkdir/trap/`{ gen; } > tmp`/
cmp/mv/UPD) on the decoded respelled glue, require `o == outs[0]` and the
tmp beside the out. The emitted `cmd` is verbatim from the same line, so the
macro's reassembly is the tree_recipe's line by construction — no hand
respelling in the tool at all. Manual-tagged calls stay tree_recipe (nothing
wires them in).

Tests: the two stamp tests needed the `tree_recipe` knob in their
conventions (the tests' CONVENTIONS constant doesn't carry it) — 111/112
with the one pre-existing test_elf_symbols import failure.

## 01:35 — stamp landed (tool commit 4ef9b1c, layer BUILDs copied)

The re-emit converts exactly the 7 candidates and nothing else
(arch/x86/BUILD.bazel, BUILD.bazel, init/BUILD.bazel; any2bazel.json
bit-identical). Offline validator: for all 7 the stamp macro's reassembled
recipe is byte-identical with the tree_recipe line the same call had in the
baseline emit (5 of them needed the package bridge).

The package bridge: the call's outs are the package's own label paths while
the reference's recipe spells the tree path (`init/utsversion-tmp.h`,
`arch/x86/include/generated/asm/…`) — the macro derives the tree spelling
from `native.package_name()` (verified working under Bazel 9.2.0), the same
bridge tree_recipe's bin-root mirror makes.

Smoke build: `bazel build` on all 7 — **action-cache HIT**, which proves the
stamp actions' run_shell commands are byte-identical to the previously built
tree_recipe actions at the action level, not only in the BUILD text. All 7
outputs `cmp` equal to the reference's. Parity gate running.

One load-line note: the root BUILD's tree_recipe load is dropped (no
tree_recipe calls left there); the same happens for arch/x86. The load lines
move with the conversions.

## 02:45 — savedcmd: two spaces the naive hook missed

The first re-emit (emit38) converted only 2 of the 4 candidates
(vmlinux_o, vmlinux_bin_xz); bzImage and pasyms_h stayed tree_recipe.
Tracing the two bails:

- **bzImage** bails on the manual-tag guard, by design: it is one of the 3
  genuinely unwired deliverables (`tags = ["manual"]`), and a manual call
  carries nothing a person wrote — it stays a tree_recipe. Correct as
  written; the shape gate did its job.
- **pasyms_h** bailed on the `savedcmd_<out> := <cmd>` arg check. The hook
  decodes the emitter's line into the arg2 space (what /bin/sh -c received),
  but my check rebuilt the arg with only the single-quote escaping. Two
  spaces are layered: (1) Kbuild's arg quoting — the cmd's own quotes
  inside the savedcmd arg are `'\''`-escaped **and its dollars are doubled**
  (`$`→`$$`), because the .cmd file is included by make and its content has
  to survive that (pasyms' sed script has `(.+)$/pa_\2`); (2) the emitter's
  line-level quoting, which the decode already handles. With
  `.replace("'", "'\\''").replace("$", "$$")` in the arg check all 4
  candidates decode, parse, and reassemble line-identical.

Also learned: the savedcmd shape requires the command to carry its own
redirect (the .cmd file records the command as executed) — my first
synthetic test put `> out` after the cmd, outside it, and the shape check
rightly rejected it. Kbuild's `cmd_foo` always includes the redirect.

Landed: tool commit 77fd91c (savedcmd recognizer, emit + 3 tests), layer
savedcmd.bzl + conventions knob + the 2 BUILDs. Emitted exactly the 3
non-manual candidates (vmlinux_o, vmlinux_bin_xz, pasyms_h); bzImage stays a
tree_recipe — it is one of the 3 genuinely unwired deliverables
(tags = ["manual"]), and a manual call stays a tree_recipe whatever the
shape. Offline validator: all 3 macro reassemblies byte-identical with the
tree_recipe lines. Smoke build: 2474 actions, all cache HITs (the run_shell
commands are byte-identical at the action level). Parity at baseline
(errors=6 warnings=12, artifacts converged 0 errors).

Learned while probing the rest: voffset_h/zoffset_h are savedcmd-shaped too
but their glue spells the output with a `../` (arch/x86/boot/compressed/../
voffset.h — Kbuild's view from the compressed dir), which can't round-trip
through a macro that only knows the canonical out; they stay tree_recipe.
The 8 cc -E/-S instances (asm-offsets.s, bounds.s, the 5 .lds) are NOT
shell glue at all — each is a single plain cc command line the emitter
already respelled; converting them would mean structuring the whole cc flag
order for 8 instances with real parity risk. Staying tree_recipe.

## 03:30 — vocabulary gate caught the docstring example

check-invariants FAILED on the first try: the savedcmd docstring's example
call spelled a deliverable (bzImage) — scripts/ must stay generic. Rewrote
the example to a neutral one (name = "objects", cmd = "ld -r -o objects.o
a.o b.o"); suites still 114/115 (only the pre-existing test_elf_symbols
import failure), vocabulary scan clean, amended into the commit.


## 04:05 — endgame gates, all green

Final tree (layer BUILDs == a fresh emit, cmp-verified file by file):
- HERMETIC OK ×2 (the second on the final tree)
- BOOT-SSH OK after 3s: Linux 7.2.0 (KVM, port 2223)
- PARITY build=GREEN errors=6 warnings=12 artifacts converged 0
- IDIOM score=0.3 (threshold 5.2)
- CORPUS=1 check-invariants OK (37/37)
- suites 114/115 (only the pre-existing test_elf_symbols import failure)

Verdict: publish: release. Remaining tree_recipe calls are each doing
legitimate work (see report.md Results); no further rule-class candidates.
