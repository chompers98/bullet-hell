# Session 6 — QC findings triage

**Source:** `session_6_qc_audit.md` (qc-agent verdict PASS — 0 CRITICAL, 0 WARNING, 4 STYLE, anti-gaming rule did not fire).
**Policy for this session:** classify each finding; no RTL, SPEC, or agent-prompt edits this session (PASS verdict → no REVISE queue).

## Classification legend

- **(a) Real bug in `player_bullet.v`** — code violates SPEC/CONVENTIONS. Log; fix in a later session.
- **(b) SPEC bug** — code is correct; SPEC was ambiguous or wrong. Propose SPEC edit in Handoff Corrections.
- **(c) Agent over-firing** — finding is noise. Log but do not touch the agent prompt yet (policy: batch prompt fixes after 2–3 real cycles).
- **(d) Legitimately undecided** — something SPEC never covered. Add to §0 as ⚠ UNDECIDED.
- **(e) Blocked on external input** — Leyaa / Puvvada / other owner.

## Triage table

| # | Finding (abridged) | Severity | Class | Rationale | Action taken this session |
|---|--------------------|----------|-------|-----------|---------------------------|
| 1 | Magic `8'd2` (bullet Y-advance, Q7) repeated 8× — no `localparam BULLET_DY`. | STYLE | **(a) Real style issue — low priority** | Code is correct. Q7 default is N=2; SPEC §10.2.5 explicitly calls it "tunable post-playtest." A named localparam would localize the tuning knob. The repetition is 8 identical lines (unrolled 8-slot advance). CONVENTIONS doesn't mandate `localparam` for numeric constants but §9 asks for comments when "WHY is non-obvious" — here the WHY (Q7 default) lives in the IMPL DECISIONS block and would naturally migrate to a localparam name. | None. Low-priority cleanup queued for a later `player_bullet` refresh or the eventual Q7 playtest tune. |
| 2 | Magic `8'd150` (FB height / despawn threshold) repeated 8×. | STYLE | **(a) Real style issue — low priority** | Code is correct. SPEC §1.3 defines `fb_y ∈ [0, 149]`, so 150 is the exclusive upper bound. A `localparam FB_H = 8'd150;` would make the link to §1.3 explicit. Same repetition pattern as #1. | None. Same bucket as #1. |
| 3 | Magic `8'd16` (sprite height / spawn offset) repeated 8×. | STYLE | **(a) Real style issue — low priority** | Code is correct. §10.2.5 rationale: "Bullet sprite (16×16) sits immediately above player sprite (16×16)." A `localparam SPRITE_H = 8'd16;` would document the tie to §1.6 (sprite ROM format) and §10.2.5 (spawn offset rationale). | None. Same bucket as #1. |
| 4 | Q9 forward-flag duplicated across IMPL DECISIONS block (L24-26) and port comment (L37-40). | STYLE | **(c) Agent over-firing — mild** | Duplication is deliberate. SPEC §10.2.1 L563 explicitly annotates the `hit_mask` port with "⚠ Q9 — Leyaa-owned; default semantics pinned here." The rtl-agent put the same annotation at the port in the RTL, which is exactly what SPEC asks for. The IMPL DECISIONS entry is a higher-level restatement. Calling this "restates rather than points" is the agent being tidy; it's not a CONVENTIONS violation. CONVENTIONS §11 even says the `⚠ UNCERTAINTY` marker *should* appear in both the IMPL DECISIONS block and at the decision point. | None. Calibration datum — when we batch prompt adjustments, consider noting that SPEC-mandated ⚠ forward-flags should not be flagged as "duplication." |

## Rollup

- **(a) Real style issues / low-priority cleanup:** #1, #2, #3 → three named-constant cleanups queued for a later session. None block integration.
- **(b) SPEC edits proposed this session:** none. (NEW-3 wording frictions at §10.2.4 L613 and §10.2.2 step 3 L585 were explicitly pre-flagged as non-blocking for this audit; qc-agent did not independently raise them, so no SPEC edit is driven by this audit. NEW-3 remains a Beaux-at-convenience item from session 5.)
- **(c) Agent over-firing:** #4 → one calibration datum. Not enough signal to patch the prompt yet; batch with session-3 findings #4, #5, #8 and whatever future cycles produce.
- **(d) Legitimately undecided:** none.
- **(e) Blocked on external input:** none in this audit. Q9 is pre-existing and tracked at SPEC §0 + §10.2.1.

## Signal analysis (what this audit tells us about the agent system)

- **qc-agent native invocation works.** `Agent(subagent_type: "qc-agent")` succeeded on first try. NEW-1 (the multi-session blocker on native invocation for all four agents) is now **fully closed** — all four agents are native-invocable as of session 6.
- **Anti-gaming rule again did not fire.** Every finding has a file:line and a SPEC or CONVENTIONS citation. Consistent with the session-3 baseline observation that the rule functions as an implicit floor the agent never tests.
- **First PASS verdict in the project.** Session-3 renderer audit was REVISE (2 CRITICAL + 3 WARNING + 3 STYLE). Session 6 `player_bullet` is PASS (0/0/4). Differences that likely explain this:
  - `player_bullet` was written *after* CONVENTIONS.md existed, so the IMPL DECISIONS block and reset enumeration were present from the start.
  - spec-agent ran first (session 5 step 1) to validate §10.2 was unambiguous enough to implement; that gate caught nothing blocking but would have surfaced ambiguity early.
  - verification-agent wrote the testbench from SPEC before rtl-agent saw any implementation, so "green sim" was not a biased signal.
  - The four-agent methodology is producing the intended outcome: cleaner first-pass code that reaches PASS without a REVISE round.
- **STYLE-only findings are expected.** Named-constant cleanups are cosmetic; they do not affect behavior, synthesis, or integration. Deferring them is correct.
- **No CRITICAL deviations from SPEC.** All 7 audit steps clean. This is a stronger-than-expected result given that §10.2 is a newer subsection of SPEC.md (added late session 4, fleshed out session 5). The SPEC itself is validated as implementable.

## Action items generated this session

- None blocking. Three low-priority `localparam` cleanups (#1–#3) and one calibration datum (#4) logged for future batching.

## Handoff correction log (for session summary)

- None. No SPEC/GOTCHAS/CONVENTIONS edits this session. NEW-3 wording frictions from session 5 remain at Beaux's convenience; this audit did not re-raise them.
