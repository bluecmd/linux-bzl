# plan — 2026-10-17

## State at start

PARITY build=RED (new — a fetch rot, see below), diff errors=6 warnings=12
(the accepted baseline: 4 generated-content diffs + the conf→auto_conf
tool/args pair). IDIOM 0.3 (threshold 5.2). HERMETIC OK + BOOT OK from
2026-10-15's run. Layer clean at 136983ac4 ("Bazel layer (2026-10-15) on
v7.2"); any2bazel kbuild-intree at dc0f877 — which now carries everything
the freebsd loop landed in its 2026-10-16 run (emitted config_template,
codegen.tool_map, link_rule, include_surface, replay_stages waiver).

**Why build was RED:** the layer's initrd pins Alpine v3.22 main apks by
hash in MODULE.bazel; Alpine dropped `zlib-1.3.2-r0.apk` from the CDN
(replaced by `-r1` when zlib got a rebuild), so a fresh fetch 404s. All
other 7 pins still resolve. Unblock: bump the zlib pin to r1 with its
sha256 (af24e502…); verified //bazel/image:image builds green. Rot risk
recorded in the report (every pin rots when Alpine bumps; a snapshot
mirror or vendored archive is the durable fix — owner decision).

## Attack order

1. **Restore the green baseline** (parity build=GREEN errors=6 warnings=12,
   boot on port 2223, hermetic) — the guard rail before anything else.
2. **Emitted config (the freebsd 2026-10-16 mechanism, applied to linux):**
   emit `--config-out` (conventions `config_template`), replace the
   hand-written `models/kernel/any2bazel.json` with the emit product,
   verify byte-reproducible and the diff still runs at the baseline.
3. **The conf→auto_conf tool/args pair (2 of the 6 errors):** record
   `codegen.tool_map` for the intentional swap — the generic fix freebsd
   already proved, no project knowledge involved. If the remaining
   generated-content warnings then have a `tool_map`-shaped cause, apply
   the same convention.
4. **The 4 generated-content errors** (voffset_h, zoffset_h, vdso2c,
   autoconf.h): root-cause each — is the bazel-side content actually
   different from the reference's, or is the differ comparing against a
   stale/wrong oracle (e.g. the recipe-line comment header, the `../`
   output spelling)? Fix generically in the tool where the cause is
   generic; keep the layer honest. If the content genuinely differs,
   say so in the report rather than papering over it.
5. **Re-verify the full gate** after each landed step: parity, boot
   (port 2223; 2222 is busy on this host), hermetic, invariants.

## Done

- PARITY build=GREEN at the accepted baseline or better (errors ≤ 6; the
  tool_map step should remove 2).
- BOOT-SSH OK (KVM) and HERMETIC OK re-measured on the final tree.
- Any tool change committed with suites green; no deliverable vocabulary.
- Report current from the start; verdict at the end.
