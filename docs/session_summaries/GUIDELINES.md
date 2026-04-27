# Session summary guidelines

Session summaries exist so a future session (human or Claude) can pick up cold without re-reading the full transcript. Optimize for that reader.

## File naming
`session_N.md` where N is the next integer. One summary per working session.

## Frontmatter
First line: `# Session N — YYYY-MM-DD` (absolute date, not "yesterday"/"Thursday").

## Required sections

1. **Goal** — one or two sentences. What was this session trying to accomplish?
2. **What was reviewed / read** — files, repos, docs. Future sessions don't need to re-read these unless checking for changes.
3. **Decisions made, with the why** — the single highest-value section. Every non-trivial choice: what was picked, what was rejected, and the reason. If the reason was "user said so," say that. Future-you will question these decisions; preempt it.
4. **Code scaffolded / modified** — files created, files edited. Absolute paths or repo-relative. Note any non-obvious patches to vendored/provided files (e.g., the `clk25_out` patch to `display_controller.v`).
5. **Verification** — what was actually run (simulated / built / bench-tested) and what passed. Be honest: if you didn't hardware-verify, say so. The reader will trust stated verification; don't claim things that weren't checked.
6. **Open questions / blockers** — anything waiting on a human, external team, or later decision. Include who owns the answer.
7. **Next steps** — numbered, actionable. The next session should be able to pick step 1 and start.

## Optional sections
- **Handoff corrections** — when you modify a spec doc, log what changed and why, so the doc's evolution is traceable beyond `git blame`.
- **Gotchas** — short notes on things that bit you and would bite a future session. (e.g. "`$readmemh` needs whitespace-separated tokens" — that one non-obvious surprise saved future-us half a debugging session.)

## Style rules

- **Be concrete.** Name files, line numbers, module names, exact signal names. "Fixed the renderer" is useless; "`src/renderer.v` S_DRAW_BB now gates on `bb_active[spr_idx]`" is useful.
- **Cite, don't recap.** Don't duplicate content that lives in the handoff doc, README, or code comments. Point to them.
- **State what's unverified.** "Compiles under iverilog; not yet bitstream-tested" is valuable information.
- **Mark reversible vs. sticky decisions.** A working assumption ("going Verilog-2001 until instructor confirms") is reversible cheaply. An architectural commitment ("framebuffer approach over direct-ROM scanout") is expensive to undo. Tag accordingly so the next session knows what's safe to revisit.
- **No narrative filler.** Skip "I then went on to…" — the reader doesn't care about order of operations, just the outcome.
- **Length target: 100–300 lines.** If it's shorter, you probably skipped rationale. If it's longer, you're probably including transcript-level detail that belongs in code comments or commit messages.

## What NOT to put in a summary

- Full code listings — those live in the repo.
- Tool call traces or command outputs unless the output itself is the finding (e.g., sim results).
- Praise, self-congratulation, or running commentary ("This went well!").
- Things that are already obvious from the git log.
- Speculation about future work beyond concrete next steps.

## When to write it
End of session, before the context rolls. Writing it after-the-fact from memory loses the "why" of small decisions — and those are the reason the summary exists.
