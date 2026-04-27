# Session 3 — 2026-04-16

## Goal
Validate the four-agent system (built in session 2) by running it against existing code. Surface SPEC gaps for Week 2's first production cycle (`player_bullet`) before the cycle starts. No new RTL; no agent-prompt patches; no SV refactor.

## What was reviewed / read
- `docs/session_summaries/GUIDELINES.md`, `session_1.md`, `session_2.md` — session context.
- `docs/SPEC.md` (all §§), `docs/GOTCHAS.md`, `docs/CONVENTIONS.md`, `docs/AGENTS_README.md` — agent-system canonical docs.
- `.claude/agents/{spec,qc}-agent.md` — re-read to inline as system prompts (see Gotcha below).
- `ee354_bullet_hell/src/renderer.v` — verified qc-agent findings at source.

## Decisions made, with the why

### Sticky decisions
- **None this session.** Per mission: no RTL, no prompt patches, no SV flip. All decisions below are either reversible doc edits or proposals for Beaux.

### Reversible / working-assumption decisions
- **Route project agents through `general-purpose` with the system prompt inlined verbatim.** The project-level `.claude/agents/*.md` definitions do not register as `subagent_type` — the runtime only exposes built-in types (`claude-code-guide`, `Explore`, `general-purpose`, `Plan`, `statusline-setup`). Inlining the system prompt into a `general-purpose` invocation preserves the intent (fresh context per call, prompt content, read-only-ish behavior — general-purpose has broader tools but the prompt forbids non-Read ops). Documented per invocation in each artifact. **Sticky question for Beaux:** is this a settings/config issue, or do we need to register agents elsewhere? (See Next Steps.)
- **Edit to SPEC §4.4** — added one paragraph clarifying that the renderer FSM's vblank detect may sample either `vCount` or `vCount_r` since both are in the `pixel_clk` domain ("pick one and stick with it"). Reversible. Driver: qc-agent Finding #3 (code uses raw `vCount` while scanout uses `vCount_r`; SPEC was silent). See Handoff Corrections.
- **Q4 (game_tick) remains pinned to rising edge of `vCount == 480` in SPEC.** Session 2 defaulted it without Beaux sign-off. Spec-agent baseline flagged this prominently. No edit made; Beaux reviews the proposed resolution (R4 in the artifact) and signs off or overturns.

### What was deliberately NOT done
- **No agent-prompt edits.** Severity calibration (qc-agent over-fires WARNING on future-refactor concerns, #4 / #5) isn't patched — batch after 2–3 real cycles per session-2 handoff.
- **No RTL edits to renderer.v.** Finding #1 (`vbl_prev` reset-branch placement) is real; it queues for a future cycle after Beaux reviews the triage table.
- **No SV refactor.** Q1 still open (owner: Puvvada).

## Code scaffolded / modified

### Edited
- `docs/SPEC.md` §4.4 — one paragraph added after the FSM state table clarifying raw vs. synced `vCount` choice for the FSM trigger.

### Created (artifacts, not canonical docs)
- `docs/session_summaries/artifacts/session_3_spec_baseline.md` — spec-agent enumeration of ⚠ UNDECIDED items and Week 2 blocker analysis. Surfaces two items (U-PB-SPEED in §10.2, U-IFRAME-LOC in §10.5) that exist in module sections but aren't mirrored into §0's canonical table.
- `docs/session_summaries/artifacts/session_3_qc_baseline_renderer.md` — qc-agent audit of `renderer.v`. **Verdict: REVISE.** 2 CRITICAL, 3 WARNING, 3 STYLE. Anti-gaming rule did not fire.
- `docs/session_summaries/artifacts/session_3_qc_triage.md` — per-finding classification (a/b/c/d) and rationale. Four real bugs queued, one SPEC ambiguity fixed, three agent-over-firings logged.
- `docs/session_summaries/artifacts/session_3_proposed_resolutions.md` — proposals for items Beaux can close without Leyaa/Puvvada input: R1 (add Q7/Q8 to §0), R2 (i-frame counter → `collision`), R3 (player-bullet N=2), R4 (confirm Q4 game-tick pin). **Not applied to SPEC** — awaiting Beaux.
- `docs/session_summaries/artifacts/session_3_player_bullet_spec_dryrun.md` — spec-agent dry-run surfacing **21 gaps** in SPEC §10.2 before any rtl-agent sees it.

### Untouched
- Everything under `ee354_bullet_hell/`. No RTL written or modified.

## Verification

**Agent invocations (four in total, all via `general-purpose` with inlined system prompts):**

| # | Acting as | Input scope | Output shape | Verdict / result |
|---|-----------|-------------|--------------|------------------|
| 1 | spec-agent | SPEC.md + GOTCHAS.md | Two-question answer: enumerate undecided + classify Week 2 blockers | Clean; every claim cited; surfaced 2 extra ⚠ items beyond §0. |
| 2 | qc-agent  | renderer.v + SPEC.md + GOTCHAS.md + CONVENTIONS.md | 7-step audit, findings table, verdict | REVISE; 2 CRITICAL, 3 WARNING, 3 STYLE; anti-gaming did not fire (all cited). |
| 3 | spec-agent | SPEC.md + GOTCHAS.md (dry-run on §10.2) | Contract summary + gap enumeration | 21 gaps; every one cited; owner-tagged. |
| 4 | (triage — caller-side, not an agent run) | qc findings + renderer.v + CONVENTIONS.md | Classification table | 4 real bugs queued, 1 SPEC edit made, 3 over-firings logged. |

**What was NOT verified:**
- **No hardware verification.** Vivado bitstream + board programming for Task 1 (`vga_test_top`) and Task 2 (`top.v`) remain pending — Beaux handles those in Vivado separately. Session-1 claim (iverilog + 6 framebuffer spot-checks) still the latest evidence.
- **No RTL compile-check re-run this session.** renderer.v has not changed since session 1.
- **No confirmation that the inlined-system-prompt route fully matches native-agent behavior.** The four agents ran under the `general-purpose` tool set, which includes Write/Edit/Bash. The prompts explicitly forbade non-Read use and the agents honored that, but the tool-level guarantee (session 2's "qc-agent is read-only at the tool level — load-bearing") is softened to policy-level guarantee in this session. Relevant for next session's first real cycle.

## Open questions / blockers

Carried in `docs/SPEC.md §0` and surfaced by the session's two spec-agent runs. Deduplicated below; Q1/Q2/Q5 still await external humans.

| ID | Question | Owner | Status entering session 4 |
|----|----------|-------|---------------------------|
| Q1 | SystemVerilog permitted? | Puvvada | Open. Beaux emailed; no reply yet. |
| Q2 | Palette matches Leyaa's sprite art? | Leyaa | Open. Awaiting sprite export. |
| Q3 | Reset button choice (`BtnC` vs `CPU_RESETN`). | Beaux | Default in force (`BtnC`). Can close at Beaux's convenience. |
| Q4 | Game-tick definition (rising edge `vCount == 480` vs `vSync` vs renderer FSM edge). | Beaux | **Default pinned; awaiting explicit sign-off.** Spec-agent flagged this in step 1. Proposed resolution R4 recommends keeping the pin. |
| Q5 | Two-phase boss-pattern threshold (≤50% HP). | Leyaa | Open. |
| Q6 | Exact i-frame count (120 ticks). | Beaux | Default in force. |
| Q7 (proposed) | Player-bullet per-tick Y-advance `N`. | Beaux | Not in §0 yet; in §10.2 as `N (TBD ⚠)`. Proposed resolution R3 recommends N=2. |
| Q8 (proposed) | i-frame counter location (`collision` vs `top.v` vs `player_controller`). | Beaux | Not in §0 yet; in §10.5 as ⚠. Proposed resolution R2 recommends `collision`. |
| NEW-1 | Does project-level `.claude/agents/*.md` auto-registration work in this Claude Code install? If not, what's the workaround? | Beaux | Open. Forced inline-system-prompt routing for all four agent invocations this session. |
| NEW-2 | 18 gaps in `player_bullet` SPEC §10.2 (see dry-run artifact, §B) that Beaux owns — answer before first real rtl-agent cycle. Three additional gaps are Leyaa-owned (collision-hit signal semantics, shoot_pulse edge-alignment). | Beaux (18) + Leyaa (3) | Open. Cheapest time to close is now. |

No items block Beaux doing Vivado bring-up for Task 1 and Task 2 in parallel.

## Handoff corrections

- **`docs/SPEC.md` §4.4** — added one paragraph after the FSM state table stating that the vblank-detect sample source may be `vCount` or `vCount_r` (same clock domain; one-cycle phase offset is cosmetic). Driver: qc-agent Finding #3. Line count grows by one paragraph; existing line numbers shift by ~4. **Agent prompts cite `§4.4` generically, not by line — safe.** If a future session renumbers §4.x, sweep all prompts.

## Gotchas (new to this session)

- **Project-level subagents don't auto-register.** `.claude/agents/*.md` with `name: <agent>` frontmatter is the documented pattern, but `Agent(subagent_type: "spec-agent")` returns `Agent type 'spec-agent' not found. Available agents: claude-code-guide, Explore, general-purpose, Plan, statusline-setup`. Workaround: inline the full system prompt into a `general-purpose` agent call. Preserves fresh-context and content discipline; loses tool-level read-only enforcement. Needs investigation (settings.local.json? separate registry path? known Claude Code limitation?).
- **qc-agent's CRITICAL severity for "missing IMPL DECISIONS block"** is technically correct per CONVENTIONS §2 ("mandatory") but pragmatically over-severe for process metadata on a file that predates the conventions doc. Noted; will calibrate after 2–3 real cycles rather than patching now.
- **The dry-run pattern (spec-agent → gaps list before rtl-agent invocation)** generated 21 gaps from a 3-line SPEC sketch. This is a strong argument for making it a standard first step of every new-module cycle — not just a one-off validation exercise.

## Next steps

The goal for session 4 is the **first production cycle** on `player_bullet`, assuming Beaux resolves the player_bullet-specific blockers flagged below.

1. **(Beaux, start of session 4)** Review `session_3_proposed_resolutions.md`. Accept or overturn R1–R4. If R1 accepted, add Q7 and Q8 rows to SPEC §0.
2. **(Beaux)** Close the 18 Beaux-owned gaps in `session_3_player_bullet_spec_dryrun.md` §B. The six highest-leverage: player-bullet `N`, spawn position + offset, spawn-priority encoder direction, overflow behavior when all 8 slots active, edge-vs-level for shoot_pulse handling, and the per-slot reset enumeration. Answering these six collapses ~15 of 21 gaps.
3. **(Beaux)** Ping Leyaa for the 3 collision-interface gaps (per-slot vs scalar hit signal, edge-alignment of shoot_pulse, any player_controller reset semantics).
4. **(Beaux)** Promote SPEC §10.2 from prose sketch to a full per-module section (port block + behavioral contract + reset list), matching the shape of §4.
5. **(Beaux)** Decide on the agent-discovery issue: fix the registration (preferred) or ratify the inline-system-prompt workflow as standard and update AGENTS_README.md.
6. **(Claude, session 4)** First production cycle on `player_bullet`: spec-agent (confirm contract complete) → rtl-agent (write `src/player_bullet.v`) → qc-agent (fresh session, audit) → verification-agent (write `sim/player_bullet_tb.v`). Concrete first step: spec-agent invocation asking "given the updated SPEC §10.2, is the contract complete enough for rtl-agent today?"
7. **(Beaux, parallel track)** Vivado bring-up for `vga_test_top` and `top.v` — still pending from session 1. Unblocks renderer hardware verification.
8. **(Beaux, eventually — dedicated session)** Renderer refresh. Queued real bugs: vbl_prev reset-branch placement (qc #1), IMPL DECISIONS block retrofit (qc #2), G17 slicing comments (qc #6), width-intent comments (qc #7). Batch in one rtl-agent REVISE cycle.
