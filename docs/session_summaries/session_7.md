# Session 7 — 2026-04-23

## Goal

Two parallel threads completed in one session:
1. **Hardware bring-up**, finally — get `vga_test_top` and `top.v` programmed on a real Nexys A7 and visually signed off. Outstanding from session 1.
2. **Integrate partner-contributed `player_controller.v`** (Leyaa) end-to-end: move into `src/`, run the full four-agent pipeline (spec → test → RTL → qc), wire into `top.v`, make the player actually move on the board. Post-landing revision: swap toggle-to-move for hold-to-move per Beaux playtest feedback.

## What was reviewed / read

- `docs/session_summaries/GUIDELINES.md`, `session_1.md`, `session_6.md` — entry conditions, open Vivado-bring-up item, Q9/NEW-3 status.
- `docs/SPEC.md` §0, §1.1–1.3, §1.7, §10.1, §10.2.3 — canonical contracts for `player_controller` and `shoot_pulse`.
- `docs/GOTCHAS.md` §G5, §G12, §G13, §G14, §G15, §G19.
- `docs/CONVENTIONS.md` — full pass.
- `ee354_bullet_hell/src/top.v`, `src/vga_test_top.v`, `provided/display_controller.v`, `constraints/nexys_a7.xdc` — integration surface.
- `_refs/EE354FinalProj/ee201_debounce_DPB_SCEN_CCEN_MCEN.v` — Puvvada's standard debouncer; copied into `provided/`.
- Leyaa's dropped `player_controller.v` (initial draft at repo root).

## Decisions made, with the why

### Hardware bring-up

- **Moved the Vivado project off the network share to `C:\ee354\` on the lab VM's local disk.** Vivado 12-385 rejects any path containing `$`, and the USC lab home mount is `\\labfs.vlab.usc.edu\home$\...`. **Sticky** — `C:\` will be the working root for every future lab session. Files must be copied back to the network share or git before log-off because lab `C:\` does not persist.
- **`vga_test_top` signed off on real hardware.** SMPTE color bars render correctly; 20×20 square bounces. Confirms `display_controller` timing, `.xdc` pinout, and VGA cable path all work. (Photo artifact exists but is not committed to the repo; lives in Beaux's lab-session screenshots.)
- **`top.v` static scene signed off on real hardware.** All six expected elements rendered at the correct positions (dark blue bg; red boss top-center; white player bottom-center; cyan PB mid-left; yellow + magenta BB mid-right). Sprites render as solid-color blocks because Q2 placeholder `.mem` files are solid-color; renderer is correct. No motion was expected at this stage.

### Partner RTL integration

- **Ran the full four-agent pipeline on `player_controller.v`.** spec-agent extracted the canonical contract from SPEC §10.1; orchestrator listed 13 defects against Leyaa's draft (syntax error on L18, async reset, wrong port names, missing `game_tick`/`shoot_pulse`/`BtnCenter`, invented `Y_MIN=52` "keep below boss", `SPEED=2` vs SPEC's 1, `Y_INIT=134` vs SPEC's 126); rtl-agent rewrote the module in place, preserving Leyaa's attribution in the header; verification-agent wrote `sim/player_controller_tb.v` from SPEC alone (information barrier held); qc-agent audited the rewrite. Both verdicts: **PASS**. verification 42/42; qc 0 Critical, 2 Warning, 2 Style. All four agents invoked native per session-6 methodology — no workarounds needed.
- **Resolved Q3 (reset button choice).** `BtnC` (N17) was the Week-1 default reset but SPEC §10.1 L541 claims that same physical button as `BtnCenter`=shoot. Picked **SW0 (J15), active-high synchronous** over CPU_RESETN (which is active-low and would require polarity inversion) and over a hold-combo hack. SW0 keeps reset visible as a switch state. **Sticky** — closes Q3. `top.v` IMPL DECISIONS block documents the rationale.
- **Added `ee201_debouncer` to `provided/`** rather than authoring a new one. SPEC §10.1 L540 annotates buttons as "debounced" and GOTCHAS §G19 points to `_refs/` for reference debouncer code. Clocked all 5 debouncers on `pixel_clk` (25 MHz) rather than the 100 MHz board clock — keeps the project single-clock-domain per GOTCHAS §G12; the `N_dc=25` default gives ~0.335 s debounce at 25 MHz, which feels fine in gameplay. **Reversible** — if the feel is sluggish in real gameplay, drop `N_dc` to 23.
- **`game_tick` derivation.** Single `pixel_clk` pulse when `(vCount, hCount) == (516, 0)` — first pixel of vblank line 516. One pulse per frame = 60 Hz at 25 MHz pixel_clk. Pulse is re-computed in a sync block gated by `reset` so it can't falsely fire during reset.
- **Left `shoot_pulse` unconnected in `top.v`** (`.shoot_pulse(shoot_pulse_unused)`). `player_bullet.v` is not yet wired; connection lands in Week 2-B. Synthesis will prune `prev_center` in the meantime; not a concern.

### Post-bring-up revision: toggle → hold-to-move

- **SPEC §10.1 L542 revised** from "toggle (press to start, press to stop)" to "hold-to-move (button-level-driven advance, release stops motion)" per Beaux request after playing the toggle version on hardware. Felt unnatural for a bullet-hell game. Dated note left in SPEC so the change is traceable.
- **RTL simplified, not extended.** The hold-to-move version removes four `move_*` toggle flags and four `prev_*` edge-detect regs; directional movement now reads the debounced button levels directly. `shoot_pulse` path (BtnCenter rising-edge detect) is unchanged — SPEC still wants a single pulse there, not a level.
- **Stale `⚠ UNCERTAINTY` marker from the qc findings was cleaned up** in the same edit pass. SPEC §10.2.3 L587-602 disambiguates shoot_pulse as a `pixel_clk`-domain pulse; the comment now cites that cross-ref.
- **Testbench refactored to hold-to-move semantics.** 41 SPEC-sourced assertions (was 42; one toggle-specific assertion collapsed). All pass.

## Code scaffolded / modified

| File | Change |
|------|--------|
| `ee354_bullet_hell/src/player_controller.v` | **New** (moved from repo root). Rewritten twice this session: first to SPEC §10.1 toggle semantics, then to hold-to-move after L542 revision. |
| `ee354_bullet_hell/sim/player_controller_tb.v` | **New**. 41-assertion self-checking TB, SPEC-sourced. |
| `ee354_bullet_hell/src/top.v` | Replaced hardcoded `player_x/y` wires with `player_controller` instantiation; added 5 `ee201_debouncer` instances; added `game_tick` generator; swapped reset source from `BtnC` → `SW0`; added IMPL DECISIONS block. |
| `ee354_bullet_hell/provided/ee201_debouncer.v` | **New** (copied from `_refs/EE354FinalProj/`). Unmodified. |
| `ee354_bullet_hell/constraints/nexys_a7.xdc` | Uncommented BtnU/D/L/R pins; added SW0 @ J15. BtnC mapping kept — it now means shoot in `top.v`, reset in `vga_test_top.v`. |
| `docs/SPEC.md` §10.1 L542 | Toggle → hold-to-move revision, dated 2026-04-23. |
| `ee354_bullet_hell.zip` | Regenerated twice for VM import. Not part of the project tree; build artifact. |

Untouched: `docs/GOTCHAS.md`, `docs/CONVENTIONS.md`, all other RTL modules, `.mem` files.

## Verification

| Step | What | Result |
|------|------|--------|
| 1 | `vga_test_top` on Nexys A7 | PASS — color bars + bouncing square, BtnC reset works |
| 2 | `top.v` static scene on Nexys A7 | PASS — all six sprite placements correct at expected FB coords |
| 3 | spec-agent extraction of `player_controller` contract | PASS — 9-section report, all cites valid |
| 4 | rtl-agent rewrite (toggle version) | written, compile-clean |
| 5 | verification-agent — toggle version | 42/42 PASS, iverilog build 0 warnings |
| 6 | qc-agent adversarial audit | **PASS** — 0 Critical, 2 Warning (stale UNCERTAINTY marker, addressed), 2 Style |
| 7 | `iverilog -Wall -g2001` compile of full `top.v` + all deps | PASS — only cosmetic "timescale inherited" warnings |
| 8 | rtl rewrite (hold-to-move version) + TB refactor | compile-clean |
| 9 | verification-agent TB, hold-to-move | 41/41 PASS |

**Not yet verified:** the hold-to-move version on real hardware. `top.v` compiles and the SPEC-sourced TB passes, but the last bitstream programmed on the board was the toggle version. Beaux needs one more Vivado re-synth to see hold-to-move behavior on the monitor. Flagged under open questions.

## Open questions / blockers

| ID | Status entering session 8 | Owner |
|----|---------------------------|-------|
| Q1 | Open. Still no reply from Puvvada on SV vs Verilog-2001. | Puvvada |
| Q2 | Open. Awaiting real sprite export from Leyaa. Placeholder `.mem` solids visible on real hardware are the expected stand-in. | Leyaa |
| Q3 | **Closed.** Reset is SW0 (J15), active-high sync. BtnC belongs to `BtnCenter`=shoot. | — |
| Q4 | Closed (session 4). | — |
| Q5 | Open. Two-phase boss-pattern threshold. | Leyaa |
| Q6 | Default in force (120 ticks). | Beaux |
| Q7 | Closed (session 4). | — |
| Q8 | Closed (session 4). | — |
| Q9 | Default in force. Unchanged by session 7. | Leyaa |
| NEW-1 | Fully closed (session 6). | — |
| NEW-2 | Closed for player_controller. Mostly closed for player_bullet. Open items unchanged. | Leyaa |
| NEW-3 | Still open as a Beaux-at-convenience item. Session 7 did not touch §10.2.4 / §10.2.2 wording. | Beaux |
| NEW-4 | **New.** The hold-to-move revision has not been re-programmed to the Nexys A7 yet. Sim-verified only. | Beaux |

## Next steps

1. **(Beaux, next lab visit)** Re-synthesize the new `top.v` / `player_controller` / debouncer bundle on the VM and program the board. Confirm hold-to-move feels right and the SW0 reset works. Closes NEW-4.
2. **(Claude, session 8 — fresh session)** Wire `player_bullet` into `top.v` — connect `shoot_pulse` from `player_controller` to `player_bullet`, replace hardcoded PB arrays with the live bullet-pool outputs. Player bullets should actually fire when BtnC is pressed. First dynamic-bullet bitstream.
3. **(Claude, later session)** Implement `boss_controller` (Beaux-owned, Week-2 item still pending).
4. **(Beaux, when Leyaa delivers)** Drop real sprite `.mem` files into `mem/` and re-synth. Closes Q2.
5. **(Beaux, at convenience)** NEW-3 SPEC wording cleanup at §10.2.4 L613 and §10.2.2 step 3 L585.

## Handoff corrections

- **`docs/SPEC.md` §10.1 L542** revised 2026-04-23: `toggle` → `hold-to-move`. Rationale dated inline in the SPEC. Reversible cheaply if gameplay feedback flips again, but RTL + TB would both need to roll back together.

## Gotchas (new to this session)

- **Vivado 12-385 on lab VMs.** Any project path containing `$` fails project creation. USC lab home is `\\labfs.vlab.usc.edu\home$\...` — always create Vivado projects under `C:\ee354\`. Copy artifacts back to the network share before log-off; local disk does not persist.
- **xdc ports referenced-but-not-in-top.** If the xdc `get_ports SW0` line is present while `vga_test_top` is the top (which has no SW0 port), Vivado emits a critical warning but does not fail. Safe to ignore when rebuilding `vga_test_top` with the Week-2-A xdc.
- **Debouncer on pixel_clk vs board clock.** `ee201_debouncer.v` was written for 100 MHz (`N_dc=25` → 0.084 s). Running it on 25 MHz with the same `N_dc` gives ~0.335 s — still within "feels responsive" range, avoids crossing into a second clock domain. If gameplay feels mushy, lower `N_dc` rather than moving the debouncer to `ClkPort`.
- **Four-agent pipeline is now the canonical cadence for partner-contributed RTL.** spec-agent → rtl-agent → verification-agent → qc-agent, with the orchestrator holding the information barrier (no reading the DUT before verification-agent writes the TB). The first non-Claude-authored module (Leyaa's draft) went through this pipeline in session 7 and produced a PASS verdict on the first try, matching the session-6 experience on Claude-authored code.
