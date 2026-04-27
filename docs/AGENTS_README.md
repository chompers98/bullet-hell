# AGENTS_README.md — How the four-agent system works

This project uses four specialized Claude Code subagents to write, review, and test Verilog-2001 RTL for the EE354 bullet hell game. The architecture has a deliberate **information barrier** between spec, implementation, and review — the qc-agent must never see the rtl-agent's reasoning.

Routing is **manual** — Beaux drives every handoff. There is no coordinator agent.

---

## The four agents

| Agent | Role | Tools | Reads | Writes |
|-------|------|-------|-------|--------|
| **spec-agent** | The Oracle. Single source of truth for "what should this do?" | Read, Glob, Grep | SPEC.md, GOTCHAS.md, CONVENTIONS.md, source files (read-only) | nothing |
| **rtl-agent** | The Implementer. Writes Verilog-2001 RTL. | Read, Write, Edit, Bash, Glob, Grep | SPEC.md, CONVENTIONS.md, GOTCHAS.md, existing source | `src/*.v`, `provided/*.v` |
| **qc-agent** | The Adversary. Audits RTL against SPEC. | Read, Glob, Grep | SPEC.md, GOTCHAS.md, the file under review | nothing — read-only by design |
| **verification-agent** | The Tester. Writes self-checking testbenches. | Read, Write, Edit, Bash, Glob, Grep | SPEC.md, GOTCHAS.md, **only port lists** of RTL under test | `sim/*_tb.v` |

Agent definitions live in `.claude/agents/{spec,rtl,qc,verification}-agent.md`.

---

## The information barrier

Three barriers — each load-bearing:

1. **qc-agent never sees rtl-agent's chat history or reasoning.** A fresh qc-agent session starts from zero context. It reads SPEC.md and the file under review. If the code is only correct *given context that isn't in the spec or the file*, that's a finding. This forces the spec to be self-contained.

2. **qc-agent never proposes fixes.** Findings are descriptive ("reset for `state` is missing per SPEC §4.7"), not prescriptive ("add `state <= S_WAIT_VBL;`"). Proposed fixes would bias the rtl-agent toward the qc-agent's solution rather than letting it re-read the spec.

3. **verification-agent never derives expected values from the RTL under test.** Tests compute expected values from SPEC.md alone. Reading the RTL's internal logic and asserting "output equals what RTL computes" makes the test rubber-stamp bugs instead of catching them.

---

## Routing (Beaux runs this manually)

Standard flow for a new module M:

1. **Spec check.** Ask `spec-agent` to summarize the contract for module M. Beaux reviews — is SPEC.md §M complete? Are any ⚠ UNDECIDED items load-bearing? Resolve them (or accept the in-force defaults from SPEC §0) before proceeding.

2. **Implement.** Ask `rtl-agent` to implement module M. It produces `src/M.v` with a top-of-file `IMPL DECISIONS:` block and any `⚠ UNCERTAINTY:` comments inline.

3. **Audit.** **Start a fresh `qc-agent` session** — no carry-over from steps 1–2. Hand it the file path (e.g., `src/M.v`) and tell it to audit. It returns a findings table + verdict (PASS / REVISE / REJECT).

4. **Triage.**
   - **PASS** → proceed to step 5.
   - **REVISE** → bounce findings back to `rtl-agent`. Critically, **don't tell rtl-agent the qc-agent's identity** — give it the findings table and let it re-read SPEC and fix. Loop steps 2–4 until PASS.
   - **REJECT** → architectural mismatch. Beaux re-reads SPEC §M, possibly updates SPEC, and restarts at step 2.

5. **Test.** Ask `verification-agent` (fresh session) to write tests for module M. Run them locally with `iverilog`. Pass → done. Fail → bug report routes back to `rtl-agent` (treat as a step-4 REVISE with the failing test as the finding).

6. **Move on.** Only after tests pass, start the next module.

---

## How to invoke each agent from Claude Code

In Claude Code, use the `Agent` tool with `subagent_type` set to the agent name (no leading slash, no path):

| Agent | `subagent_type` |
|-------|-----------------|
| Spec oracle | `spec-agent` |
| RTL implementer | `rtl-agent` |
| QC reviewer | `qc-agent` |
| Verification | `verification-agent` |

Example prompts (paste into the `prompt` field):

**spec-agent:**
> Summarize the contract for `renderer.v`. List every input/output, every behavioral requirement, and every ⚠ UNDECIDED item that affects this module. Cite SPEC sections.

**rtl-agent:**
> Implement `src/sprite_rom_player.v` per SPEC §7. Use the file template from CONVENTIONS §2. Run the 7-step self-check before handing off.

**qc-agent (fresh session — open a new conversation, paste only):**
> Audit `ee354_bullet_hell/src/renderer.v` against SPEC.md and GOTCHAS.md. Run the 7-step audit. Produce the findings table. Issue PASS / REVISE / REJECT. Do not propose fixes.

**verification-agent (fresh session):**
> Write `sim/sprite_rom_player_tb.v` for `src/sprite_rom_player.v`. Derive every expected value from SPEC §7 alone. Self-check; print TEST PASSED or TEST FAILED at the end. Run it with iverilog and report the result.

### Why "fresh session"

Claude Code's subagents inherit the parent conversation's tool history but get their own instructions and a clean context window. For qc-agent and verification-agent specifically, **don't run them inside a session that just had the rtl-agent write the file** — start a new conversation, or at minimum a new agent invocation that doesn't see the rtl-agent's draft commentary. The barrier matters.

If you're worried the subagent boundary leaks too much context, you can run qc-agent from a separate terminal session against the same working directory — same effect, even cleaner separation.

---

## What each doc owns

| File | Owner | Purpose |
|------|-------|---------|
| `docs/SPEC.md`        | Beaux + spec-agent | Canonical "what should this do?" Modify with care; every agent's behavior is anchored to it. |
| `docs/GOTCHAS.md`     | Beaux + qc-agent | Project-specific traps and their fixes. Append as new traps surface. |
| `docs/CONVENTIONS.md` | Beaux | Verilog-2001 coding conventions for rtl-agent. Stable; update only on language/tooling change. |
| `docs/AGENTS_README.md` | Beaux | This file. The routing manual. |
| `.claude/agents/*.md` | Beaux | Agent system prompts. The agents are defined by these. |

The rtl-agent **must not modify SPEC.md, GOTCHAS.md, or CONVENTIONS.md**. If it discovers a gap, it stops and writes a note to Beaux. Same rule for the qc-agent and verification-agent.

---

## When things go sideways

- **rtl-agent silently filled in a spec gap with a guess.** That's a violation; bounce with a hard-rule reminder. Easier to prevent: ensure ⚠ UNCERTAINTY markers are familiar to the agent (they're in the prompt and CONVENTIONS).
- **qc-agent passed something that fails synth.** Either GOTCHAS.md is missing the trap (add it), or the qc-agent skipped step 6. Re-run the audit; if it passes again, GOTCHAS needs a new entry.
- **verification-agent's test passes but hardware doesn't work.** The test derived an expected value from the RTL by accident. Read its testbench critically; look for assertions whose "expected" value cites no SPEC section. Strip those tests, re-derive from SPEC.
- **All four agents disagree about a port name.** SPEC §1.7 is wrong or ambiguous. Beaux fixes SPEC; agents re-converge.

---

## Concrete first invocation (suggested)

The cleanest first run, to validate the agent setup before relying on it:

1. Spawn `spec-agent` and ask:
   > List every ⚠ UNDECIDED item in SPEC.md, the decision owner for each, and what's currently the in-force default.

2. Spawn `qc-agent` (fresh session) and ask:
   > Audit the existing `ee354_bullet_hell/src/renderer.v` against SPEC.md. Run the 7-step audit. This file was written before the agent system existed, so expect findings — that's a useful baseline.

If both produce well-formed outputs (clean lists from spec-agent, a properly cited findings table from qc-agent), the system is working. Then start using rtl-agent for new modules.
