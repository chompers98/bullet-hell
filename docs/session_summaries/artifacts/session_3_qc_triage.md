# Session 3 — QC findings triage

**Source:** `session_3_qc_baseline_renderer.md` (qc-agent verdict REVISE — 2 CRITICAL, 3 WARNING, 3 STYLE, anti-gaming rule did not fire).
**Policy for this session:** classify each finding; edit SPEC only for class (b); do not touch RTL or agent prompts.

## Classification legend
- **(a) Real bug in `renderer.v`** — code violates SPEC/CONVENTIONS. Log; fix in a later session.
- **(b) SPEC bug** — code is correct; SPEC was ambiguous or wrong. Edit SPEC this session.
- **(c) Agent over-firing** — finding is noise. Log but do not touch the agent prompt yet (user policy: batch prompt fixes after 2–3 real cycles).
- **(d) Legitimately undecided** — something SPEC never covered. Add to §0 as ⚠ UNDECIDED.

## Triage table

| # | Finding (abridged) | Severity | Class | Rationale | Action taken this session |
|---|--------------------|----------|-------|-----------|---------------------------|
| 1 | `vbl_prev` not assigned in `if (reset)` branch — line 170 is outside the reset structure. | CRITICAL | **(a) Real bug** | Verified: `renderer.v:170` reads `vbl_prev <= vbl_now;` before `if (reset)`. SPEC §4.7 explicitly lists `vbl_prev ← 0` in the reset set. Existing sim (reset released while `vCount<480`) doesn't exercise the bug. Hardware-visible path: reset released mid-vblank → first frame's sprite draw skipped. Low likelihood, but it's a documented spec deviation. | None. Logged for a future rtl-agent REVISE cycle. |
| 2 | No IMPL DECISIONS block at file header. | CRITICAL | **(a) Real bug — pre-existing compliance gap** | CONVENTIONS §2 L75 says the block is mandatory. `renderer.v` was written in session 1, before CONVENTIONS.md existed, so the violation is retroactive rather than a fresh error. Agent severity of CRITICAL matches the CONVENTIONS rule's "mandatory" wording but is arguably miscalibrated for a process-metadata rule. Leaving the severity alone — the rule is clear and agent enforces it as written. | None. Add to the future renderer-refresh session's task list. |
| 3 | `vbl_now` samples raw `vCount`, scanout pipeline samples `vCount_r` — one-cycle phase mismatch, undocumented in SPEC. | WARNING | **(b) SPEC bug (ambiguity)** | Both forms work (same clock domain). SPEC §4.3 mandates the sync for the scanout pipeline but says nothing about the FSM side. SPEC §4.4 just says "rising edge of `(vCount >= 10'd480)`" without specifying which version. Agent correctly flagged the silent mixing. Fix at the SPEC side: clarify that either is permitted. | **SPEC §4.4 edited** — added one-paragraph clarification that FSM may sample either `vCount` or `vCount_r` since both are in the `pixel_clk` domain, with a "pick one and stick with it" rule so the qc-agent has something concrete to flag on mixing. |
| 4 | `tgt_x_ps`/`tgt_y_ps`/`wr_addr_ps` names reused across S_DRAW_PL and S_DRAW_BOSS; correctness depends on `cur_sx`/`cur_sy` carrying the right position at the PL→BOSS transition. | WARNING | **(c) Agent over-firing** | Code is correct as written. The agent's concern is purely about future-refactor robustness. "A future refactor could break it" is speculation — STYLE at most, not WARNING. Not a current-code bug; not prohibited by SPEC or CONVENTIONS. | None. Calibration datum — when we batch prompt adjustments, consider tightening the WARNING definition to "affects present correctness, not hypothetical future refactors." |
| 5 | `hCount_r`, `vCount_r`, `bright_r` not in reset branch. | WARNING | **(c) Agent over-firing** | SPEC §4.7 lists the regs requiring reset, and the sync regs are not in that list. CONVENTIONS §5 L119 says only "every state register listed in the SPEC's reset-behavior section … must be assigned in the reset branch" — by construction the sync regs are exempt. The agent even hedged ("arguably fine") but still rated it WARNING. | None. Same calibration bucket as #4. |
| 6 | GOTCHAS §G17 recommends a one-line comment on `spr_idx[2:0]` vs. full-`spr_idx` slicing; comment is absent. | STYLE | **(a) Real style issue** | The code is correct; the comment is genuinely missing. STYLE is the right severity. | None. Low-priority cleanup for a later session. |
| 7 | No width-intent comment on the 15-bit multiply-add for write addresses. | STYLE | **(a) Real style issue** | CONVENTIONS §9 asks for width-trick comments. The code is correct; the comment is missing. STYLE is the right severity. | None. Same bucket as #6. |
| 8 | `H_FB_START[9:0]` / `V_FB_START[9:0]` part-selects on `localparam`s are "unnecessary." | STYLE | **(c) Agent over-firing** | Defensive explicit sizing is idiomatic Verilog-2001, not a style violation. Nothing in CONVENTIONS flags this pattern. | None. Calibration datum. |

## Rollup

- **(a) Real bugs / compliance gaps:** #1, #2, #6, #7 → four items queued for the next renderer-refresh session (not this one).
- **(b) SPEC edits made this session:** #3 → SPEC §4.4 clarified.
- **(c) Agent over-firing:** #4, #5, #8 → three items. All are WARNING/STYLE rather than CRITICAL, and all are sign of the agent being cautious rather than careless. Not enough signal to patch the prompt yet; reconsider after 2–3 real cycles.
- **(d) Legitimately undecided:** none from this review. (Undecided items surfaced by the spec-agent baseline — U-PB-SPEED, U-IFRAME-LOC — are handled in `session_3_proposed_resolutions.md`, not here.)

## Signal analysis (what the baseline tells us about the agent system)

- **Anti-gaming rule did not fire.** Every finding carries a file:line and a SPEC/GOTCHAS/CONVENTIONS citation. The rule is working as an implicit floor; the agent never tested it.
- **The one genuine hardware-affecting bug** (Finding #1) was caught by the agent despite the existing testbench passing. This is the strongest positive data point for the barrier-based review architecture: the agent found a bug that sim didn't, because it was reading SPEC §4.7 line by line rather than trusting that "it works in sim."
- **Severity calibration lean:** the agent is slightly over-severe on hypothetical-future-refactor concerns (#4) and on "unreset state regs that SPEC doesn't require reset for" (#5). Not bad — the "start skeptical" default is working — but worth watching.
- **SPEC-drift evidence:** one genuine ambiguity surfaced (#3 → §4.4 edit). For a 660-line SPEC vs. a 305-line RTL written before the SPEC existed, one ambiguity is low. The session-2 claim that "spot checks during writing showed alignment" holds up.

## Handoff correction log (for session summary)

- `docs/SPEC.md §4.4` — added one paragraph clarifying that the vblank-detect FSM may sample either `vCount` or `vCount_r` since both are in the `pixel_clk` domain. Driver: qc-agent Finding #3. Reversibility: trivial (single paragraph). Stickiness: reversible — if a future decision pins "always use `vCount_r` for consistency," remove the paragraph.
