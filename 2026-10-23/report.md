# report — 2026-10-23

*(updated as the run proceeds; verdict at the end)*

## State at run start

PARITY build=GREEN diff=converged errors=0 warnings=14 artifacts=converged
0 errors, IDIOM 0.3 (threshold 5.2). Layer at 82ca2c96c, tree clean;
any2bazel wt-kernel at 6259752. Runs 2026-10-19/21 died with empty
sessions — the layer is where 2026-10-17 left it.

## Why the last release was recorded pre-release

Run 2026-10-17's report said BOOT-SSH OK, but the harness measured
**boot=0**. Its saved boot.txt: qemu died at startup with "Could not set
up host forwarding rule 'tcp:127.0.0.1:2222-:22'" — the harness's boot
test uses the default port 2222 and the host had it occupied (the run's
own verification used 2223; sibling loops boot on 2222 too). The gate
failed before qemu started a guest. So the boot blocker since 2026-10-17
has been environmental, like the podman-arm64 flake the same run hit and
the deleted bazel-cache that killed 2026-10-18/20.

## Plan

plan.md — re-establish the release state (image + boot on a free port),
then the open owner scrub item (the emitter's 3,837-line header comment
in the root BUILD.bazel) and the stale review TODOs, parity as the guard
rail throughout.

## Journal

journal.md in this directory.

## Results

### Parity and idiom

- **PARITY build=GREEN diff=converged errors=0 warnings=14
  artifacts=converged 0 errors** — measured by the loop's parity.sh on
  the final layer this run installs (the emit53 tree below).
- **IDIOM score=0.2** (was 0.3; threshold 5.2), rules=2930 tus=1236
  genrules=1 dirs=120.
- **BOOT-SSH OK after 3s: Linux 7.2.0** (shared bin/boot-ssh-test.sh,
  port 2227, key `$ROOT/keys/id_ed25519`), on the image built from the
  final layer.
- **INVARIANTS OK** — suites green in the tool worktree, vocabulary
  clean, corpus 37 converged before and after (CORPUS=1).
- **HERMETIC OK: //bazel/image:image builds in a clean container**
  (ubuntu-24.04, read-only layer tree, fresh output base).

### What changed

- **The owner's 2026-10-06 scrub item is done** (tool change, generic):
  `emit_build.py`'s provenance header now lists only the targets whose
  own rule a BUILD file carries, and review TODOs/Notes record the
  package they were raised for and render beside that rule. On the
  linux layer: root BUILD.bazel header **3,837 → 848 comment lines**
  before the first rule; the tree-wide name-mapping table is gone
  (3,530 → 3 lines); all 135 review TODOs now sit in the packages whose
  rules need the human decision (root keeps its own 16, e.g.
  objtool-from-host). The emit summary also now counts TODOs truthfully
  (the extra-files loop rebound `text`, so every emit logged
  "0 TODO(s)"). Verified: the re-emit differs from the layer outside
  comments in **0 of 2,322 BUILD files** — the whole change is headers
  and routed review sections. Tool commit `a0162a2` in the kbuild-intree
  worktree; invariants OK (suites green, vocabulary clean, corpus 37
  converged before and after).
- **The per-object KBUILD_* defines splinter is resolved** (tool change,
  generic — this run's main item). Kbuild derives
  `-DKBUILD_MODFILE/BASENAME/MODNAME/__KBUILD_MODNAME` from each file's
  own name, so no two TUs of a kernel library share an argv: the
  previous layer split ~108 of them into one cc_library per file, each
  spelling its full line plus defines, and raised ~111 "different
  flags" review asks (arch/x86/kernel alone had 65 pieces and 65 asks).
  The emitter now merges the flag groups that differ only in these
  defines: the common line is spelled once, the defines ride the
  per-source map of `cc_per_source_library` (the layer's rule computes
  them from the sources — `kbuild` / `kbuild_modules`; this mechanism
  and the rule shipped in the 2026-10-17 layer), and `_kbuild_refine`
  reduces the map to the arithmetic whenever the reference's defines are
  exactly what it computes (verbatim otherwise — parity-safe). A group
  whose defines the arithmetic cannot express is its own per-source
  piece of the same kind. On the layer: **cc_libraries 2133 → 2026,
  cc_per_source_library 19 → 26, review TODOs 135 → 23**; arch/x86/kernel
  BUILD.bazel **13,683 → 3,152 lines** (one kbuild="built-in" library of
  63 C sources + three small pieces); fs/9p's module defines left the
  copts for `kbuild = "9p"`. Suite coverage: the merge into one library,
  the separate assembly-regime piece, the group piece carrying the map
  when the main line cannot (127/127 emit_build tests).
- **`toolchain/bazel-probe.json` stays in the layer** — I deleted it
  mid-run suspecting a machine-specific artifact; it is the emitter's
  supply record (the conventions' `toolchain_probe`) and checked in
  since 2026-10-13. Without it the emit silently spelled the whole
  kernel compile line into every piece's copts (107 BUILD files
  ballooned; parity would not have caught it — the differ compares the
  emitted layer, not a re-emit). Restored from HEAD; lesson recorded in
  the journal.
- Two bugs found mid-run were **mine, not the tool's**:
  1. I installed an emit tree without `EMIT=`, so the installer used a
     stale 557-file tree and the deletion pass removed 1,765 good
     BUILDs — a transient parity RED, fully explained and recovered.
  2. After installing, one parity run stayed RED with "missing input
     file" on host compiles although the producers built fine alone —
     **stale Bazel server state** from the broken-tree build; a fresh
     `bazel build //... --keep_going` went green with no layer change.
- My first boot tests this run failed because I passed a nonexistent
  key path; the harness's real key is `$ROOT/keys/id_ed25519`. With it:
  **BOOT-SSH OK after 3s: Linux 7.2.0**.
- **A merge that reorders the link is a parity break — fixed with
  runs.** The first kb-merge emit (emit52) came back with 2
  `generated_content_diff` errors (zoffset.h +0x30, vdso64-image.c).
  Not compile flags: every TU object is byte-identical to the reference
  (1,104 ref .o's compared; the four realmode/rm stragglers differ only
  in DWARF path strings, pre-existing and downstream-irrelevant). The
  break was **link order**: the reference links vdso64.so as
  `note.o, vclock_gettime.o, vgetcpu.o, vgetrandom.o,
  vgetrandom-chacha.o`, the merge bucketed `note.S` and
  `vgetrandom-chacha.S` together (same argv minus the defines) into one
  library, and a library hands its objects to the link together —
  chacha.o moved next to note.o. Downstream: vdso2c → vdso64-image.o →
  (thin built-in.a — the archive bytes don't hold their members, which
  is why all 555 `.a` files compared identical) → vmlinux.o → xz (+56)
  → piggy.o → compressed vmlinux (+0x30) → zoffset.h. One root cause
  behind both errors. Fix (generic): `_merge_kbuild_groups` splits each
  merged bucket into maximal `_ld_runs` — members the reference's link
  keeps adjacent; a split-off run of one keeps its full argv verbatim.
  On the fixed layer (emit53): cc_libraries 2025 → 2026,
  cc_per_source_library 27 → 26, review TODOs 28 → 23; only 3 BUILD
  files changed vs emit52 outside comments. Suite coverage: new
  test_kbuild_merge_keeps_the_links_object_order; 128/128 emit_build,
  engine 150/150, extract 181/181, idiom, cargo/vcpkg green.

### The boot-port flake (what the shared script should do differently)

Unchanged diagnosis: `bin/boot-ssh-test.sh` hard-codes hostfwd to the
default port 2222 unless a port arg is passed, and a host-port collision
kills qemu before the guest starts ("Could not set up host forwarding
rule"). The harness's call (`loop.sh:149`) passes no port, so
project.env cannot help — `$BOOT_ARGS` precedes the key/timeout/port.
Recommendation for the shared script (generic, and the freebsd loop hit
it too): when qemu dies immediately with "Could not set up host
forwarding rule", retry on a free port (or bind hostfwd with port 0 and
read back the chosen port). Nothing on 2222 held as of this run's start;
the gate failed on 2026-10-17 purely from the occupied port.

## Verdict

**publish: release.** The layer installs the emit53 tree: upstream v7.2
plus the Bazel layer, parity converged with 0 errors against the
reference build (IDIOM 0.2, threshold 5.2; rules 2930, tus 1236), the
bzImage boots under QEMU/KVM and accepts SSH (3s), and the image target
builds hermetically in a clean ubuntu-24.04 container. The two tool
commits this run — `a0162a2` (provenance header per file; review TODOs
beside their rule) and `7f39c7e` (Kbuild's per-object defines merged
into per-source libraries, in runs the link keeps adjacent) — are in
the kbuild-intree worktree with every suite green, the vocabulary
clean and the corpus 37/37.

Two finds worth carrying:

1. **The merge-vs-link-order invariant is now part of the emitter**:
   any grouping of TUs into one library is only sound when the
   reference's link keeps those objects adjacent (`_ld_runs`); a thin
   archive hides member changes from byte-comparing the archives.
2. **`toolchain/bazel-probe.json` is load-bearing at emit time** (the
   conventions' `toolchain_probe`); deleting it silently spells whole
   compile lines into copts and parity does not catch a re-emit
   regression — verify emitter changes by re-emit + diff, not parity.

The boot gate's 2026-10-17 failure was environmental (port 2222 held);
the shared `boot-ssh-test.sh` should retry on a free port when qemu
dies immediately with "Could not set up host forwarding rule" — the
freebsd loop hit the same flake.
