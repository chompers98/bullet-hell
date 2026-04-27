# Session 2 — 2026-04-16

## Goal
Stand up a four-agent system (spec / rtl / qc / verification) to drive Week 1+ RTL development with a deliberate information barrier between spec, implementation, and review. Two prep docs first (canonical SPEC, GOTCHAS), then the agent definitions, then a routing manual. **No RTL written this session** — only docs and agent prompts.

## What was reviewed / read
- `handoff_doc.md` — full re-read; consolidated into `docs/SPEC.md`.
- `docs/session_summaries/session_1.md` — caught the five handoff corrections and the verification baseline.
- `ee354_bullet_hell/provided/display_controller.v` — verified the `clk25_out` patch and exact port list ended up in SPEC §3 verbatim.
- `ee354_bullet_hell/src/renderer.v` (305 lines) — used as ground truth when writing SPEC §4 (interface, FSM states, scanout math, ⚠ UNCERTAINTY pattern examples).
- `.claude/settings.local.json` — confirmed iverilog and existing build commands are pre-allowed; agents can use them.
- File listings of `_refs/`, `_extracted/`, `mem/`, `sim/`, `src/` — confirmed scaffold matches handoff §7.

## Decisions made, with the why

**Sticky (architectural) decisions**

- **Four agents, no coordinator, manual routing by Beaux.** User-specified. Routing is documented in `docs/AGENTS_README.md`. Cost: every handoff is a manual step. Benefit: total transparency on which agent saw what.
- **Information barrier is enforced via three rules** (spec/qc/verification each have one). Implementation: the qc-agent's prompt forbids reading rtl-agent's reasoning; the verification-agent's prompt forbids deriving expected values from the RTL under test; the spec-agent's prompt forbids implementation talk. The barrier is policy, not technical — agents can't be sandboxed from each other in Claude Code, but the prompts make the rule unambiguous.
- **qc-agent and spec-agent are read-only at the tool level** (only Read, Glob, Grep). Load-bearing — the qc-agent specifically *cannot* "helpfully fix" what it finds even if it wanted to. Tool restriction matches user spec.
- **Four canonical docs:** SPEC.md (contracts), GOTCHAS.md (traps), CONVENTIONS.md (style), AGENTS_README.md (routing). Every agent reads SPEC + GOTCHAS; rtl-agent additionally reads CONVENTIONS. This split keeps SPEC focused on "what should this do?" and avoids style noise crowding out semantics.

**Reversible decisions (defaults that can flip on instructor input)**

- **Verilog-2001 only** until SPEC Q1 resolves. Refactor cost to packed arrays is ~30 minutes of mechanical interface change; it's safe to defer.
- **Active-high sync reset on `BtnC`** — SPEC Q3 default. Documented in SPEC §1.2 + GOTCHAS §G5.
- **Game tick = rising edge of `vCount == 480`** — newly pinned (SPEC Q4). Three reasonable definitions exist (`vSync` rising edge, `vCount==480` rising edge, renderer FSM `S_DONE→S_WAIT_VBL`). Picked the middle one because it's earliest and unambiguous; flagged as ⚠ UNDECIDED for Beaux to confirm.

**QC-process decisions**

- **7-step QC audit** (interface / behavioral / gotcha / reset / timing / synthesis / uncertainty) baked into `qc-agent.md` exactly per user spec.
- **Anti-gaming rule:** >3 uncited findings → auto-downgrade to REVISE. Prevents shallow rubber-stamps. Hard-coded into the qc-agent prompt; the agent must report whether the downgrade was applied.
- **PASS threshold:** 0 CRITICAL + ≤2 WARNING. Style findings don't block PASS. Tighter than typical "looks fine to me" but loose enough that style nits don't stall progress.

**Verification-agent decisions**

- **Expected values from SPEC alone** is the single rule the agent prompt repeats three times. Cost: tests for ⚠ UNDECIDED items get stubbed as `// PENDING:` rather than written against guessed expected values. Benefit: tests catch real bugs instead of confirming the implementation matches itself.
- **`check` task pattern** (display + counter, end with `TEST PASSED`/`TEST FAILED: N error(s)`) prescribed because Verilog-2001 has no `assert` keyword. The pattern is shown in the agent prompt verbatim so all testbenches look the same.

## Code scaffolded / modified

Created (all under `/Users/bcable/ee354finalproject/`):

- `docs/SPEC.md` — canonical reference, ~660 lines. §0 open questions → §1 system contracts → §2 module index → §3–§9 per-module specs → §10 Week 2/3 sketches → §11 file layout → §12 resource budget.
- `docs/GOTCHAS.md` — 20 entries (G1–G20). Each entry: trap → fix → SPEC pointer.
- `docs/CONVENTIONS.md` — Verilog-2001 style guide. File template, naming, reset style, BRAM patterns, `⚠ UNCERTAINTY` marker format.
- `docs/AGENTS_README.md` — routing manual + invocation examples.
- `.claude/agents/spec-agent.md` — Read/Glob/Grep only. Citation-or-nothing rule. Refuses implementation questions.
- `.claude/agents/rtl-agent.md` — Read/Write/Edit/Bash/Glob/Grep. 7-item self-check list. ⚠ UNCERTAINTY discipline. No tests, no spec edits.
- `.claude/agents/qc-agent.md` — Read/Glob/Grep only. 7-step audit. Findings table + verdict format. Anti-gaming rule. Forbids fix proposals.
- `.claude/agents/verification-agent.md` — Read/Write/Edit/Bash/Glob/Grep. Expected-from-SPEC-only rule. `check` task template. Cannot modify RTL or SPEC.

Modified: nothing in `ee354_bullet_hell/`. RTL untouched this session by design.

## Verification

- Confirmed all 8 deliverables exist on disk (`ls` of `docs/` and `.claude/agents/`).
- **Not verified:** no agent has been invoked yet. The system prompts have not been exercised. First real test is the suggested concrete invocation in `docs/AGENTS_README.md` ("List every ⚠ UNDECIDED…" + "Audit existing renderer.v" baseline run).
- **Not verified:** SPEC.md has not been cross-checked line-by-line against `src/renderer.v` for drift. Spot checks during writing showed alignment, but the qc-agent's first baseline audit will be the real test of whether the SPEC is consistent with the existing code.

## Open questions / blockers

Carried in `docs/SPEC.md §0` (the canonical list — agents read from there). Highlights:

- **Q1 — SystemVerilog vs Verilog-2001.** Owner: Puvvada. Beaux is emailing.
- **Q2 — Palette agreement.** Owner: Leyaa. Stub `.mem` files already match SPEC §1.5.
- **Q3 — Reset button.** Owner: Beaux. `BtnC` active-high sync in force.
- **Q4 — Game-tick precise definition.** Owner: Beaux. New this session — three reasonable interpretations existed in the handoff; pinned the rising edge of `vCount == 480` as the default.
- **Q5 — Phase-2 boss HP threshold.** Owner: Leyaa.
- **Q6 — Player i-frame count.** Owner: Beaux.

No blockers for the first agent run — the suggested baseline invocations in AGENTS_README don't depend on any open Q resolving.

## Handoff corrections

None to `handoff_doc.md` itself this session — SPEC.md supersedes it for agent consumption. Handoff still readable as historical context. New ground-truth ordering for future sessions:

1. `docs/SPEC.md` is authoritative.
2. `docs/GOTCHAS.md` for traps.
3. `handoff_doc.md` is now legacy / narrative — reference only.

If SPEC and handoff disagree, SPEC wins.

## Gotchas (from this session, beyond what's in GOTCHAS.md)

- **Agent prompts are not version-controlled separately from the docs they reference.** If SPEC §X.Y gets renumbered, the agent prompts that cite "SPEC §1.7" go stale silently. Mitigation: keep SPEC section numbers stable; if a new section is added, append rather than insert.
- **Claude Code subagents inherit the parent session's tool history but get their own instructions.** Documented in AGENTS_README — for qc-agent specifically, prefer a fresh top-level conversation rather than spawning from a session that just had the rtl-agent write the file. The barrier is policy, not technical isolation.
- **The handoff doc still says "hvsync_generator" in a few legacy places.** Captured in GOTCHAS §G6 (and §G19 for the `evangabe` reference correction) so it can't get re-introduced via a mis-paste.

## Next steps

1. **Baseline qc-agent run** against existing `ee354_bullet_hell/src/renderer.v`. The file was written before the agent system existed — expect findings. This validates the audit format and surfaces any SPEC-vs-code drift.
2. **Baseline spec-agent run:** ask it to enumerate every ⚠ UNDECIDED item with owner. Validates the citation discipline.
3. Resolve as many ⚠ UNDECIDED items as possible (Q1 / Q2 await external input; Q3–Q6 are Beaux's calls).
4. First production cycle: pick a Week 2 module (`player_bullet` or `boss_controller`), run spec → rtl → qc → verification end-to-end, capture friction points.
5. Update agent prompts after the first real cycle if any rule turned out to be too loose or too strict.
6. Open Vivado, synth `vga_test_top`, program board (still pending from session 1 — unblocks the renderer hardware test).
