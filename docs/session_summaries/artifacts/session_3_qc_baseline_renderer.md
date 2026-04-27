# Session 3 — qc-agent baseline audit of renderer.v

**Invoked:** 2026-04-16, session 3, step 2.
**Agent:** `qc-agent` (system prompt inlined into `general-purpose` runner — subagent registry discovery issue documented in session summary).
**Barrier preserved:** agent did not receive rtl-agent chat context, git history, or prior session notes — only `docs/SPEC.md`, `docs/GOTCHAS.md`, and the RTL file.
**Inputs:** `ee354_bullet_hell/src/renderer.v`, `docs/SPEC.md`, `docs/GOTCHAS.md`, `docs/CONVENTIONS.md` (plus dependent `framebuffer.v`, `palette_lut.v`, `sprite_rom_*.v` for interface cross-check).

---

# QC Review — renderer

## Audit notes (brief, by step)
1. **Interface:** All §4.1 ports present with matching names/widths/directions. No extras.
2. **Behavioral:** FSM states all present; scanout pipeline correct; border fill uses index 1 as specified; output-blanking gate on `bright_r` present. One reset-behavior omission (`vbl_prev` not reset per §4.7). S_DRAW_BOSS uses `tgt_x_ps`/`tgt_y_ps` (semantically correct since `cur_sx/sy` carries boss position — naming overload only).
3. **Gotchas:** G1 honored (vga_r/g/b gated on bright_r). G2 delegated to framebuffer.v (verified). G3 naive strategy + TODO comment present. G7/G8 downstream. G10 transparency skip present in all four draw states. G11 divide form used. G12 single clock domain. G13 clean (no SV syntax). G14 no initials for state. G15 edge-detect (vbl_rise) used. G16 9-bit adds + bounds check present. G17 correct slicing widths.
4. **Reset:** Reset branch covers `state, fb_we, clear_addr, spr_row, spr_col, spr_idx, cur_sx, cur_sy`. **Missing: `vbl_prev`** — SPEC §4.7 explicitly lists it.
5. **Timing:** Single clock domain (`posedge pixel_clk`); no combinational loops; no `always @*` in this file, so no latch risk. No async reset.
6. **Synthesis-safety:** No SV syntax. No `initial` for state. BRAM/ROM inference delegated to dependent modules, which match their patterns.
7. **Uncertainty:** No `⚠ UNCERTAINTY` comments present in the file. **IMPL DECISIONS block mandated by CONVENTIONS §2 is absent** — only a plain descriptive header exists.

## Findings

| # | Severity | File:Line(s) | Finding | SPEC/GOTCHA citation |
|---|----------|--------------|---------|----------------------|
| 1 | CRITICAL | renderer.v:169-180 | `vbl_prev` is not assigned in the `if (reset)` branch. Line 170 (`vbl_prev <= vbl_now;`) sits before the reset check, so on reset `vbl_prev` samples current `vbl_now` instead of being cleared to 0. If reset is released while `vCount >= 480`, the first `vbl_rise` is missed and S_WAIT_VBL stalls for a full frame. | SPEC §4.7: "`vbl_prev ← 0` (so the first vblank rising edge is detected normally one frame after reset)"; CONVENTIONS §5: every state reg in SPEC reset list must be assigned in reset branch. |
| 2 | CRITICAL | renderer.v:1-8 | Module header lacks the mandatory `IMPL DECISIONS:` block. CONVENTIONS §2 states "The IMPL DECISIONS block at top of file is mandatory." The qc-agent cannot verify whether deliberate decisions (e.g., `vbl_now` using raw `vCount` vs `vCount_r`, no reset on `fb_wr_addr`/`fb_wr_data`) were knowing or accidental. | CONVENTIONS §2; §11. |
| 3 | WARNING | renderer.v:136 | `vbl_now = (vCount >= 10'd480)` uses the raw `vCount`, but the scanout pipeline syncs to `vCount_r`. The FSM therefore advances one cycle ahead of the scanout's view of the same count. Same clock domain so no CDC bug, but the mismatch is undocumented and not in the spec. | SPEC §4.3 (sync hCount/vCount/bright into pixel_clk domain); §4.4 (FSM trigger on vblank). |
| 4 | WARNING | renderer.v:227-232 | S_DRAW_BOSS reuses `tgt_x_ps` / `tgt_y_ps` / `wr_addr_ps` which are declared "player / boss (ps = position sprite)" on line 158. The naming is overloaded — correct behavior depends on `cur_sx`/`cur_sy` having been reloaded with `boss_x`/`boss_y` at the PL→BOSS transition (line 216-217). A future refactor that adds intermediate states or breaks that invariant silently breaks boss draw. | SPEC §4.6 (sprite-blit per-pixel rule). |
| 5 | WARNING | renderer.v:51-57 | `hCount_r`, `vCount_r`, `bright_r` are not reset. After reset, they carry the upstream values one cycle later. Because `display_controller` has no reset (SPEC §3.6) and the RGB output gate depends on `bright_r`, during the first cycle after reset `vga_r/g/b` may briefly reflect old `bright_r` before the upstream becomes known. Arguably fine (SPEC §4.7 says "VGA outputs go to 0 on the next clock as bright_r is registered"), but the sync regs themselves are unreset and this is not called out. | SPEC §4.7; CONVENTIONS §5. |
| 6 | STYLE | renderer.v:150-151, 152-153 | GOTCHAS §G17 suggests "Add a one-liner comment" explaining the `spr_idx[2:0]` vs. full-`spr_idx` slicing choice. The code does it correctly but without the comment. | GOTCHAS §G17. |
| 7 | STYLE | renderer.v:165-167 | `wr_addr_ps/pb/bb` use `{6'b0, tgt_y_ps} * 15'd200 + {6'b0, tgt_x_ps}` with 9-bit y (max 149 fits), which yields a 15-bit result — correct, but a brief comment on width intent would match CONVENTIONS §9. | CONVENTIONS §9. |
| 8 | STYLE | renderer.v:67-68 | `H_FB_START[9:0]` / `V_FB_START[9:0]` part-selects on integer `localparam`s are unnecessary — the `localparam`s are already sized by context. Harmless, slightly unusual idiom. | CONVENTIONS §1 (Verilog-2001 permitted forms). |

## Verdict
VERDICT: REVISE
Critical: 2  Warning: 3  Style: 3
Anti-gaming downgrade applied: no (every row has a file:line and a SPEC/GOTCHA or CONVENTIONS citation)

---

## Caller-side evaluation of qc-agent behavior

- **Citation discipline:** every row carries a file:line and a SPEC/GOTCHAS/CONVENTIONS cite. Anti-gaming rule did not fire. ✓
- **Information barrier held:** the agent never invoked git or session-summary context. Its reasoning cites only SPEC/GOTCHAS/CONVENTIONS + the code. ✓
- **No fixes proposed:** findings are descriptive, not prescriptive. ✓
- **Verdict justification:** REVISE, matching 2 CRITICAL. Correct per the verdict rule. ✓
- **Anti-gaming rule triggered?** No. All rows cited. If it had fired on a first real review, that would have been calibration data; it didn't, so the agent is behaving at spec.
- **Signal check on the CRITICAL findings:** the renderer passes iverilog sim + the six framebuffer spot-checks per session 1. If the agent's Finding #1 is real, it implies either (a) the bug only manifests with a specific reset-release timing that `renderer_tb` doesn't exercise, or (b) the spec is over-strict and the code's behavior is functionally equivalent. Triage in step 3 will decide.
- **CONVENTIONS-vs-SPEC severity calibration:** Finding #2 (missing IMPL DECISIONS block) is tagged CRITICAL. That may be over-firing — CONVENTIONS §2 says the block is mandatory, but a missing process-metadata block does not produce incorrect hardware. Triage in step 3 will decide.
