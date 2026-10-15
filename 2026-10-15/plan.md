# plan — 2026-10-15

State at start: PARITY build=GREEN errors=6 warnings=12 (accepted release
baseline), artifacts converged, IDIOM 5.2 == threshold, HERMETIC OK carried,
BOOT carried but the harness's own re-measurement of 2026-10-13 recorded
boot=0 — cause found before planning: the boot log is
`Could not set up host forwarding rule 'tcp:127.0.0.1:2222'` — host port
2222 was busy when the harness ran boot-ssh-test.sh, not a layer defect
(the run's own boot test had passed minutes earlier). Reproduce the boot
this run and note the flake in the report.

## Attack order

1. **Boot sanity first** (the harness measured boot=0 last run): rebuild the
   image, run boot-ssh-test.sh. Done = OK on a free port; the report says
   plainly that 2026-10-13's boot=0 was the port collision.

2. **The 21 `manual` tags (the 5.0 of the 5.2)** — the actual score floor.
   They split by ground truth (authoritative list: `bazel query
   'attr(tags, manual, //...)'`):
   - 15 host-tool `cc_binary` (objtool, mkcpustr, modpost, vdso2c, fixdep x2,
     mkpiggy, relocs, conmakehash, gen_crc32table, sorttable, conf,
     mk_elfconfig, gen_init_cpio) + `//:subcmd` (the lib only objtool links):
     the tag is load-bearing — it keeps `//...` from building them in the
     target (kernel) configuration, which would fail. A person writes the
     same tag. Expect: keep, and say why in the report.
   - 5 sink deliverables (`//:modules_builtin`, `//arch/x86/boot:bzImage`,
     `arch_x86_boot_vmlinux_bin`, `setup_bin`, `//usr:initramfs_data_cpio`):
     tagged because the emitter cannot see a consumer in the build it
     analyses — but the workspace wires them (the layer's `//bazel/image`
     consumes the bzImage chain) or they are just the reference's tail.
     Honest move: a conventions channel that says "this workspace's
     deliverable target consumes the sink outputs" so the emitter stops
     tagging them; then re-measure parity (the aquery grows by those
     actions — they are reference actions too, so expect equal-or-better).
   - The `manual_rules` t formula (`len(manual)/max(1,len(genrules))*2`)
     saturates to 1.0 whenever one manual rule and one genrule exist —
     inconsistent with the file's own docstring ("every detector is a rate
     against its natural denominator") and with every sibling detector
     (rate = count/n_targets is already computed). With the 15 load-bearing
     host tools the floor stays 5.0 forever no matter what the layer does.
     Decide after the deliverables work: if the honest layer work cannot
     move it, this is a metric bug to fix in the tool with the corpus as
     the check — reported as such, with the delta it causes, never as a
     "score win".

3. **The remaining 29 `tree_recipe` instances → purpose-built rules** (owner
   item 1's residue; the two readability questions are the guide):
   - the cmp-stamp trio (`cpufeaturemasks_h`, `compile_h`, `timeconst_h`):
     one `stamp` rule class — generator writes `.tmp_<out>`, `cmp -s` stamps;
     the impl must derive the reference's exact `.tmp` spelling.
   - the vmlinux chain, `bzImage`'s sibling steps, utsrelease,
     voffset/zoffset: multi-tool recipes; a `kernel_link`-family rule only if
     the shapes genuinely repeat, else hand-written genrules with a cmd a
     person would write.
   - voffset/zoffset stay `tree_recipe` by nature (recipe lives in a `.cmd`
     file the reference recorded as `sh -c .voffset.h.cmd`): needs a new
     mechanism — design it this run or record why not.
   Done = fewer `tree_recipe` calls, parity at baseline, smoke cmp of outputs.

4. **todo 135 (0.2)**: resolve the TODOs the emitter leaves that are now
   expressible; the rest are annotated variants the honest layer keeps.

## Guard rails

Every step ends with a full gate: `parity.sh linux` == the accepted baseline
(errors=6, warnings=12, artifacts converged 0 errors) and IDIOM ≤ 5.2.
Tool commits small, suites green before each; layer amended as the single
commit. Hermetic + boot at the end, CORPUS=1 invariants if the tool changed.

## Done

Boot OK re-verified; the manual-tag question answered with evidence; the
tree_recipe classes the shapes genuinely support converted; report + journal
current; verdict at the end.
