# Session 3 — spec-agent baseline output

**Invoked:** 2026-04-16, session 3, step 1.
**Agent:** `spec-agent` (system prompt inlined into `general-purpose` runner — see session summary for why).
**Inputs:** `docs/SPEC.md`, `docs/GOTCHAS.md`.
**Prompt shape:** two-question batch — enumerate ⚠ UNDECIDED + classify Week 2 blockers.

---

# EE354 Bullet Hell — Spec-Agent Report

## Q1 — Undecided items

Scanning the entirety of `SPEC.md`, the following ⚠ UNDECIDED items exist. §0 is the canonical table; §10.2, §10.3, and §10.5 introduce additional markers that reference §0 items or add new ones.

| ID | SPEC ref | Owner | In-force default | One-sentence summary |
|----|----------|-------|------------------|----------------------|
| Q1 | `SPEC.md §0` (row Q1) | Puvvada | Verilog-2001 (flat buses, no packed arrays) | Whether SystemVerilog is permitted or the project is strictly Verilog-2001 (`SPEC.md §0` L34). |
| Q2 | `SPEC.md §0` (row Q2) | Leyaa | Palette in §1.5 stands; stub `.mem` files are index-aligned | Whether Leyaa's sprite art matches the 16-color palette indices defined in `SPEC.md §1.5` (`SPEC.md §0` L35). |
| Q3 | `SPEC.md §0` (row Q3), cross-ref `SPEC.md §1.2` L59 | Beaux | `BtnC` as active-high synchronous reset | Reset-button choice for the integrated `top.v`; `BtnC` vs. `CPU_RESETN`, revisit when `player_controller` defines its reset semantics (`SPEC.md §0` L36). |
| Q4 | `SPEC.md §0` (row Q4), cross-ref `SPEC.md §1.1` L54 | Beaux | Rising edge of `vCount == 480` (start of vblank) | **FLAG FOR BEAUX:** Canonical definition of the game-tick pulse, selected from three candidates all within microseconds of each other (`SPEC.md §0` L37). **Beaux has not given explicit sign-off on the `vCount == 480` pin — the default is in force but unconfirmed per the caller's note.** |
| Q5 | `SPEC.md §0` (row Q5), cross-ref `SPEC.md §10.3` L548 | Leyaa | `boss_hp ≤ 50` (HP scale 0–99) | Two-phase boss-pattern toggle threshold — confirm ≤50% HP (`SPEC.md §0` L38). |
| Q6 | `SPEC.md §0` (row Q6), cross-ref `SPEC.md §10.5` L560 | Beaux | 120 ticks (~2 s) | Exact i-frame count after a player hit (`SPEC.md §0` L39). |
| U-PB-SPEED | `SPEC.md §10.2` L543 | Beaux (§10.2 is Beaux-owned) | None stated — marked `N (TBD ⚠)` | Player-bullet per-tick Y-advance speed `N` is explicitly undecided in the `player_bullet` sketch (`SPEC.md §10.2` L543: "Advance Y up by N (TBD ⚠) per tick"). |
| U-IFRAME-LOC | `SPEC.md §10.5` L560 | Beaux (explicitly "Beaux to decide when starting Week 2") | None — structural question | Whether the 120-tick i-frame counter lives in `collision` or in `top.v` is explicitly ⚠ UNDECIDED (`SPEC.md §10.5` L560). |

Notes on scope:
- `SPEC.md §0` L41 states: "If an agent encounters a question not listed here, it must add a row marked ⚠ UNDECIDED rather than guess." U-PB-SPEED and U-IFRAME-LOC are encoded in their module sections but are not mirrored in the §0 table. Per spec rules they should be, but I only report what the document says; I am not editing.
- `SPEC.md §10.6` (hud) lists an owner of "TBD" in the `SPEC.md §2` module index (L178: "`hud` | … | TBD | 3"). That is an ownership TBD, not a ⚠ UNDECIDED marker per the spec's own convention, so it is not included above.

### Explicit flag on Q4 (per caller's instruction)

`SPEC.md §0` L37 lists three candidate definitions of `game_tick`: (a) rising edge of `vSync`, (b) rising edge of `vCount == 480`, (c) the `S_DONE → S_WAIT_VBL` transition. The default "Rising edge of `vCount == 480`" is already propagated into `SPEC.md §1.1` L54, `SPEC.md §1.7` L128, and `GOTCHAS.md §G15` L164–170 as the in-force contract. The caller reports this was pinned in session 2 **without Beaux's explicit sign-off**. Q4 is Beaux-owned (`SPEC.md §0` L37). **Surfacing for Beaux: confirm or overturn the `vCount == 480` pin before Week 2 game-logic modules subscribe to `game_tick` as their timebase.**

## Q2 — Week 2 blocker analysis

Target modules:
- `player_bullet` — `SPEC.md §10.2` L541–545.
- `boss_controller` — `SPEC.md §10.3` L546–550.

| UNDECIDED | Blocks `player_bullet` (§10.2)? | Blocks `boss_controller` (§10.3)? | Justification |
|-----------|--------------------------------|-----------------------------------|---------------|
| Q1 (SV vs. V-2001) | No | No | Default "Verilog-2001" is in force (`SPEC.md §0` L34) and §1.8 L136–147 pins flat-bus packing. Both §10.2 outputs (`pb_x_flat`, `pb_y_flat`, `pb_active` per `SPEC.md §1.7` L123–124) and §10.3 outputs (`boss_x`, `boss_y`, `boss_hp`, etc. per `SPEC.md §1.7` L122, L129) are expressible in V-2001. A later flip to SV would be a refactor, not a blocker. |
| Q2 (palette / sprite art) | No | No | Neither §10.2 nor §10.3 produces pixels. Palette indices are consumed by the renderer's scanout (`SPEC.md §4.3` L296) and by sprite ROMs (`SPEC.md §7`), not by game-logic modules. Both target modules only emit coordinates / active masks / HP. |
| Q3 (reset source `BtnC` vs `CPU_RESETN`) | No | No | Default "`BtnC` active-high sync" is in force (`SPEC.md §0` L36, `SPEC.md §1.2` L57–60). Every module port is named `reset` per `SPEC.md §1.7` L114 regardless of which button drives it at `top.v`. `SPEC.md §0` L36 explicitly says revisit "when `player_controller` defines its reset semantics" — that is a `player_controller` concern, not §10.2 or §10.3. |
| Q4 (game-tick definition) | **Yes** | **Yes** | Both modules are tick-driven. `SPEC.md §10.2` L543 says "Advance Y up by N … per tick"; `SPEC.md §10.3` L547–548 says "HP register 0..99, decrement on hit pulse" and defines phase via `hp`, and per `SPEC.md §1.7` L128 `game_tick` is the canonical timebase for game-logic modules ("game logic modules will subscribe in Week 2"). While a default is in force, the caller states Beaux's sign-off is not recorded. If the definition changes (e.g., to `vSync` rising edge or to renderer FSM `S_DONE → S_WAIT_VBL`), `top.v`'s `game_tick` generator (`SPEC.md §1.1` L54, `GOTCHAS.md §G15` L164–170) changes, and every consumer's notion of "one tick" shifts. Soft blocker: work can start against the default, but Beaux should sign off before the default propagates into committed RTL. |
| Q5 (phase threshold `hp ≤ 50`) | No | **Yes** | §10.3 directly emits `phase`, and `SPEC.md §10.3` L548 reads: "Phase = `(hp <= 50)` ? 1 : 0 (⚠ Q5)" — the comparator threshold is literally the undecided quantity. `player_bullet` (`SPEC.md §10.2`) does not reference phase, so it is unaffected. |
| Q6 (i-frame count = 120 ticks) | No | No | I-frames are owned by `collision` and/or `top.v` per `SPEC.md §10.5` L557–560. `SPEC.md §10.2` never references i-frames; `SPEC.md §10.3` never references i-frames. Boss hit-pulses still decrement `boss_hp` regardless of player i-frame count. |
| U-PB-SPEED (player-bullet per-tick Y speed `N`) | **Yes** | No | `SPEC.md §10.2` L543 marks `N` explicitly `(TBD ⚠)` and N directly parameterises §10.2's behavior. `boss_controller` (`SPEC.md §10.3`) is independent of player-bullet velocity. |
| U-IFRAME-LOC (i-frame counter location) | No | No | `SPEC.md §10.5` L560 scopes this to `collision`/`top.v`. Neither §10.2's port list nor §10.3's port list mentions i-frames, so neither module is blocked by the structural choice. |

### Summary of Week 2 blockers

- **`player_bullet` (`SPEC.md §10.2`):** blocked by **Q4** (soft — default in force, Beaux sign-off pending) and **U-PB-SPEED** (hard — `N` is literally `TBD ⚠` in the module's own sketch).
- **`boss_controller` (`SPEC.md §10.3`):** blocked by **Q4** (same soft status as above) and **Q5** (the phase-threshold comparator constant is the undecided value).

```
⚠ UNDECIDED: Has Beaux signed off on defining game_tick as the rising edge of vCount == 480 (vs. rising edge of vSync vs. renderer S_DONE→S_WAIT_VBL)?
Decision owner: Beaux

⚠ UNDECIDED: Player-bullet per-tick Y velocity N (SPEC.md §10.2)
Decision owner: Beaux

⚠ UNDECIDED: Location of the 120-tick player i-frame counter — inside `collision` or inside `top.v` (SPEC.md §10.5)
Decision owner: Beaux
```

---

## Caller-side evaluation of spec-agent behavior

- **Citation discipline:** clean. Every factual claim carries a `§` cite with a line range. Zero implementation speculation. ✓
- **Scope discipline:** refused to pick values for U-PB-SPEED, Q4 sign-off, or U-IFRAME-LOC. Did not propose fixes. ✓
- **Gap discovery:** surfaced two ⚠ items that exist in module sections but are not mirrored in §0's canonical table (`U-PB-SPEED`, `U-IFRAME-LOC`). Noted the §0 L41 rule that any new question must be added to §0 — correctly flagged as an edit for Beaux rather than making the edit itself. ✓
- **Q4 flag:** rendered with emphasis as instructed. ✓
- **Prompt-bug signals:** none observed. The only operational concern is discovery, not behavior — see session summary.
