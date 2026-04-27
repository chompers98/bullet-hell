# Session 5 — 2026-04-18

## Goal

First production cycle on `player_bullet`: spec-through-rtl only. Validate the four-agent routing end-to-end on a real module. qc-agent explicitly out of scope — it runs in a fresh top-level session (session 6) to preserve the information barrier.

## What was reviewed / read

- `docs/session_summaries/GUIDELINES.md`
- `docs/session_summaries/session_4.md` — entry conditions, closed questions (Q4, Q7, Q8), Q9 default pinned.
- `docs/SPEC.md` — full pass, with focus on §10.2 (all subsections) and §1.1/§1.2/§1.7/§1.8.
- `docs/GOTCHAS.md` — full pass.
- `docs/CONVENTIONS.md` — full pass.
- `docs/AGENTS_README.md` — full pass.

No RTL reads by the orchestrator. Each subagent read what its prompt told it to read.

## Decisions made, with the why

### Session-level routing decisions

- **Verification-agent ran BEFORE rtl-agent**, not after. Rationale: writing the testbench from SPEC alone before any RTL exists is the only way to guarantee the tests aren't biased by the implementation. Waiting until after rtl-agent would have let the RTL's shape bleed into the test's expected values. This inverts the order shown in `AGENTS_README.md` §"Routing" (which lists Test at step 5) — intentional, and reported here as a procedural decision Beaux should ratify or revert for future sessions.
- **Native subagent invocation, not inlining.** `Agent(subagent_type: "spec-agent" | "rtl-agent" | "verification-agent")` worked cleanly for all three. No fallback to the inline-system-prompt workaround that session 3 required. NEW-1 (the blocker entering session 5) is now **closed**.
- **Orchestrator verified rtl-agent's self-check independently.** Re-ran the exact `iverilog -g2001 -Wall` and `vvp` commands and confirmed identical output (clean compile, 33/33 pass, `TEST PASSED`). Also checked testbench mtime < RTL mtime to confirm the rtl-agent did not mutate the testbench to force a green. The rule "rtl-agent must not edit the testbench" is load-bearing to the whole methodology; spot-checked here, not just trusted.

### spec-agent verdict

- **Clean PASS.** §10.2 is complete enough for rtl-agent. No gaps that produce ⚠ UNCERTAINTY beyond the Q9 default at `hit_mask`.
- Two informational wording frictions surfaced, **non-blocking**:
  - §10.2.4 line 613 says "`pb_active` is already a flat 8-bit reg; drive directly" while the port at line 567 is `output wire [7:0] pb_active`. Intent is unambiguous (internal reg + continuous assign), wording is loose.
  - §10.2.2 step 3 line 585 says "Clear `shoot_latch_next` unconditionally" in next-state-reg phrasing; §10.2.3 uses direct-latch phrasing. Both produce identical behavior.
- spec-agent's full "per-tick behavioral invariants I1–I20" canonical summary saved verbatim to `docs/session_summaries/artifacts/session_5_spec_check.md`.

### verification-agent decisions

- All 10 orchestrator-specified scenarios covered. 33 self-checking `check(...)` assertions total; every one cites a SPEC subsection.
- **Test 10 (shoot_latch clears on spawn failure)** implemented as the *contrapositive* the orchestrator prompt suggested — no debug port added to the DUT. After a pool-full tick, a bare `game_tick` + `hit_mask` freeing slot 0 (with NO intervening `shoot_pulse`) must leave slot 0 empty; a leaked `shoot_latch` would visibly refill it.
- Final summary: `TEST PASSED` or `TEST FAILED: N error(s)` based on counter.
- Verilog-2001 strict. No SV assertions; `task check(...)` with an error counter.

### rtl-agent IMPL DECISIONS block (verbatim, from `src/player_bullet.v` lines 4–26)

```
- Per-tick order: advance -> despawn -> spawn (SPEC §10.2.2). Step 3
  reads post-step-2 state so a slot despawned this tick is immediately
  reusable. Implemented in a single combinational always @* block that
  produces *_next signals; a separate sequential always @(posedge clk)
  commits them. Blocking assigns in combinational block only; non-blocking
  in sequential block only (CONVENTIONS §7).
- Priority encoder: LSB-first scan over pb_active_next (SPEC §10.2.5
  "lowest-index-first"). Unrolled if/else-if chain with a `found` guard,
  8 slots.
- game_tick sampling: single-cycle clock enable on pixel_clk (GOTCHAS
  §G15). State holds when game_tick is low (combinational block
  reproduces current state so the non-blocking commit is a no-op).
- shoot_pulse sampling: latched into shoot_latch every pixel_clk per the
  SPEC §10.2.3 boilerplate (reset / game_tick / shoot_pulse priority
  chain). Multi-pulse collapse and pool-full clear both follow from the
  latch resetting on every game_tick.
- Internal state: pb_x/pb_y as 8 separate 8-bit regs rather than an
  unpacked array — keeps the reset branch and output packing explicit
  and avoids any risk of synthesis tool array-handling quirks.
- hit_mask semantics: bit i high on the game_tick cycle forces
  pb_active_next[i] = 0 in step 2 (SPEC §10.2.1 Q9 default; Leyaa-owned,
  flagged inline at the port).
```

Every SPEC-cited clause in the block points to a real subsection. No inline ⚠ UNCERTAINTY markers beyond the named Q9 annotation at the `hit_mask` port (exactly as the orchestrator prompt expected).

## Code scaffolded / modified

### Created
| File | Purpose | Lines |
|------|---------|-------|
| `ee354_bullet_hell/src/player_bullet.v` | `player_bullet` RTL per SPEC §10.2 | 190 |
| `ee354_bullet_hell/sim/player_bullet_tb.v` | Self-checking testbench, 33 assertions across 10 SPEC-derived scenarios | 526 |

### Artifacts (not RTL, but session output)
| File | Purpose |
|------|---------|
| `docs/session_summaries/artifacts/session_5_spec_check.md` | spec-agent verdict + I1–I20 invariant summary |
| `docs/session_summaries/artifacts/session_5_verification_notes.md` | verification-agent coverage table |

### Untouched
- `docs/SPEC.md`, `docs/GOTCHAS.md`, `docs/CONVENTIONS.md`, `docs/AGENTS_README.md`.
- All other RTL (`renderer.v`, `framebuffer.v`, `top.v`, etc.).
- `.claude/agents/*.md` — native invocation now confirmed working; no inlining retrofit needed.

## Verification

Three subagent invocations + one iverilog compile + one vvp run.

| Step | Agent | Verdict |
|------|-------|---------|
| 1 | `spec-agent` | **PASS** — §10.2 contract complete; no gaps beyond Q9 default. |
| 2 | `verification-agent` | **PASS** — testbench written, 10 scenarios / 33 assertions, all cite SPEC. No compile run this step (RTL didn't exist yet). |
| 3 | `rtl-agent` | **SELF-CHECK PASS** — clean `iverilog -g2001 -Wall`, 33/33 `vvp` checks. |

### Orchestrator-side independent re-verification

`iverilog -g2001 -Wall -o /tmp/pb_build ee354_bullet_hell/src/player_bullet.v ee354_bullet_hell/sim/player_bullet_tb.v` — **no output, clean compile, no warnings**.

`vvp /tmp/pb_build`:

```
--------------------------------------------------
Checks passed: 33
Checks failed: 0
TEST PASSED
/Users/bcable/ee354finalproject/ee354_bullet_hell/sim/player_bullet_tb.v:523: $finish called at 9200000 (1ps)
```

**Not verified this session:** Vivado synthesis, place-and-route, timing, bitstream hardware test. Only Icarus Verilog simulation. The testbench covers behavioral correctness, not synthesis-inference behavior (BRAM/LUT/latch checks are qc-agent's job in session 6 plus Vivado in a later session).

**Not run this session (deliberately):** qc-agent. Per the information-barrier rule in `AGENTS_README.md`, qc-agent audits `player_bullet.v` in a **fresh top-level Claude Code session** (session 6), never inside this session or a continuation of it.

## Open questions / blockers

| ID | Status entering session 6 | Owner |
|----|---------------------------|-------|
| Q1 | Open. SystemVerilog vs. Verilog-2001. Still no reply from Puvvada. | Puvvada |
| Q2 | Open. Awaiting sprite export. | Leyaa |
| Q3 | Default in force (`BtnC` active-high sync). | Beaux |
| Q4 | Closed session 4. | — |
| Q5 | Open. Phase-2 boss-pattern threshold. | Leyaa |
| Q6 | Default in force (120 ticks). | Beaux |
| Q7 | Closed session 4 (N=2). | — |
| Q8 | Closed session 4 (counter in `collision`). | — |
| Q9 | **Default in force** (`hit_mask [7:0]`). Now embedded in `src/player_bullet.v` port list and inline comment — rtl-agent flagged it exactly where the SPEC told it to. If Leyaa overrides with scalar+index, the port list changes by ~3 lines. | Leyaa |
| NEW-1 | **Closed this session.** Native subagent invocation worked for spec-, rtl-, verification-agent. qc-agent native invocation still untested — session 6 will exercise it. | — |
| NEW-2 | Mostly closed for `player_bullet`. Remaining Leyaa-owned items unchanged from session 4. | Leyaa |
| NEW-3 | **Minor SPEC wording frictions** surfaced by spec-agent. Non-blocking for session 6 (rtl-agent did the correct thing anyway). Beaux may tighten §10.2.4 line 613 and §10.2.2 step 3 line 585 at convenience. | Beaux |

## Next steps

1. **(Claude, session 6 — FRESH top-level session)** Invoke `qc-agent` to audit `ee354_bullet_hell/src/player_bullet.v` against `docs/SPEC.md` §10.2 and `docs/GOTCHAS.md`. Verdict: PASS / REVISE / REJECT. qc-agent must not see session 5's rtl-agent reasoning.
2. **(Claude, on REVISE or REJECT)** Bounce findings table back to `rtl-agent`; loop until PASS. On REJECT, Beaux re-reads SPEC §10.2 first.
3. **(Claude, after qc PASS)** Wire `player_bullet` into `top.v`. Still holds Q3 unresolved → `player_controller` still pending → `shoot_pulse` and `player_x/player_y` inputs are stub-driven (hardcoded test values) for an intermediate `top.v` build. Alternatively, defer integration until `player_controller` lands.
4. **(Beaux, parallel)** Vivado bring-up for `vga_test_top` and `top.v` — still pending from session 1.
5. **(Beaux, eventually)** Renderer refresh batch (qc findings 1, 2, 6, 7 from session 3).

## Handoff corrections

None — no SPEC/GOTCHAS/CONVENTIONS edits this session.

## Gotchas (new to this session)

- **Verification-agent can compile-verify its own testbench only after RTL exists.** Session 5's verification-agent intentionally did **not** compile-check — RTL did not yet exist and introducing a stub module would have been a subtle bias vector (stub port widths leak). The rtl-agent's self-check gate absorbed the compile step. Future sessions running verification-agent FIRST should keep this pattern: the testbench gets written against SPEC only; compile-as-partner happens in the following rtl-agent step.
- **Adjacent string-literal concatenation is not Verilog-2001 portable.** verification-agent's advisor flagged this: `"abc" "def"` as a single token works in some simulators but is not guaranteed. Keep assertion names as single string literals. (Generic Verilog-2001 pitfall worth adding to GOTCHAS if it bites again.)
- **Native subagent invocation confirmed working 2026-04-18** for spec-, rtl-, verification-agent. No inlining workaround needed. NEW-1 from session 3/4 is closed. qc-agent native invocation still untested — session 6 exercises it.
