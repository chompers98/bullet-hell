# CONVENTIONS.md — Coding conventions for `rtl-agent`

The rtl-agent reads this before every module. These conventions are mandatory unless SPEC.md explicitly overrides them for a specific module. The qc-agent enforces them.

---

## 1. Language

**Verilog-2001 only.** Until the open question Q1 (SPEC.md §0) resolves otherwise. Forbidden constructs:

- `logic` — use `wire` or `reg`.
- `always_ff`, `always_comb`, `always_latch` — use `always @(posedge clk)` and `always @*`.
- Packed arrays in port lists — use flat buses (SPEC.md §1.8).
- Unpacked arrays in port lists — same.
- `.*` and `.name` (implicit) port connections — use named explicit `.port(net)` style.
- `enum`, `typedef`, `struct`, `package`, `interface`.
- `++`, `--`, `+=`.

Permitted Verilog-2001 features that some EE354 students avoid (use them):

- `localparam` for state encodings.
- Indexed part-select (`bus[i*W +: W]`) for bullet-bus slicing.
- `generate` blocks for repetition.
- ANSI-C-style port lists (`module foo(input wire clk, ...);`).

---

## 2. File template

```verilog
`timescale 1ns / 1ps
// <one-line description of what this module does>
//
// IMPL DECISIONS:
//   - <decision 1>: <SPEC ref or one-line rationale>
//   - <decision 2>: ...
//
// (Optional) ⚠ UNCERTAINTY:
//   - <question> — assumed <value> because <reason>. See line NN below.
module <name> (
    input  wire        pixel_clk,
    input  wire        reset,
    // ... other ports, grouped by direction (inputs first, then outputs) ...
    output reg  [3:0]  vga_r
);
    // localparams first
    localparam ...

    // wires next
    wire ...

    // regs next
    reg ...

    // submodule instantiations
    framebuffer u_fb (...);

    // combinational logic
    always @* begin
        ...
    end

    // sequential logic
    always @(posedge pixel_clk) begin
        if (reset) begin
            ...
        end else begin
            ...
        end
    end

endmodule
```

The **IMPL DECISIONS block at top of file is mandatory.** It declares every choice the rtl-agent made that wasn't fully pinned down by SPEC.md. The qc-agent uses this list to know what was deliberate.

---

## 3. Naming

- **Modules:** lowercase, underscores. `renderer`, `framebuffer`, `sprite_rom_player`.
- **Ports:** lowercase, underscores. Match SPEC.md §1.7 names *exactly* — `pixel_clk`, `reset`, `bright`, `hCount` (this one is camelCase because it inherits from the class-provided `display_controller`), `vCount`, `hSync`, `vSync`, `vga_r`, etc. Any deviation is a qc finding.
- **Internal regs:** `_r` suffix for "registered version of the wire of the same name." E.g., `bright_r` is `bright` after a 1-cycle sync.
- **State encodings:** `localparam S_NAME = N'dM;`. Matches the existing `S_WAIT_VBL`, `S_CLEAR`, etc. style in `renderer.v`.
- **Submodule instances:** `u_<role>` short prefix. `u_fb`, `u_pal`, `u_rom_pl`. Avoid `inst_` or `i_` (latter clashes with index loop variables).

---

## 4. Indentation and formatting

- **4 spaces.** No tabs.
- Open brace / `begin` on the same line as the construct. `end` on its own line, aligned with the construct.
- One blank line between logical sections (`// ---------- Section name ----------` is a permitted divider).
- Wrap port lists at one port per line; align the names in a single column.
- Long expressions: wrap after binary operators, indent 8 spaces (or align to the operand).

Example:

```verilog
wire [14:0] wr_addr_ps =
    {6'b0, tgt_y_ps} * 15'd200 + {6'b0, tgt_x_ps};
```

---

## 5. Reset style

- **Active-high synchronous reset.** Always named `reset`. Sampled inside `always @(posedge pixel_clk)`:
  ```verilog
  always @(posedge pixel_clk) begin
      if (reset) begin
          state <= S_INIT;
          counter <= 0;
      end else begin
          // normal logic
      end
  end
  ```
- Every state register listed in the SPEC's reset-behavior section for that module must be assigned in the reset branch. The qc-agent checks this.
- Combinational outputs: no reset needed — they follow their inputs.
- Do **not** use asynchronous reset (`always @(posedge clk or posedge reset)` style). Synchronous only.

---

## 6. Combinational logic

Two acceptable forms:

- **Continuous assign:** preferred for simple expressions.
  ```verilog
  assign in_fb = bright_r && in_fb_h && in_fb_v;
  ```
- **`always @*`** with **explicit defaults** to prevent latch inference (GOTCHAS §G18):
  ```verilog
  always @* begin
      next_state = state;          // default
      fb_we      = 1'b0;
      case (state)
          S_CLEAR: begin
              fb_we = 1'b1;
              if (clear_addr == FB_SIZE - 1) next_state = S_DRAW_PL;
          end
          // ...
      endcase
  end
  ```

Never write a combinational `always` block where some path leaves an output unassigned.

---

## 7. Sequential logic

- All sequential logic clocked on `posedge pixel_clk`.
- **Non-blocking assignments (`<=`)** in sequential blocks. **Blocking (`=`)** in combinational `always @*` blocks. Never mix in a single block.
- One `always @(posedge clk)` block per related state group is fine. Splitting unrelated state across multiple blocks improves readability.

---

## 8. Memory inference

- **Framebuffer (BRAM):** use the exact pattern in GOTCHAS §G2.
- **Sprite ROMs (LUT-RAM):** use the pattern in SPEC.md §7.2 — `reg [3:0] mem [0:255]; initial $readmemh("...", mem); assign data = mem[addr];`.
- **No initial blocks for state.** Initial blocks are reserved for `$readmemh` calls in ROMs.

---

## 9. Comments

- **Module-header comment (mandatory):** one-line description, then `IMPL DECISIONS:` block, then any top-of-file `⚠ UNCERTAINTY:` summary.
- **Section dividers** inside long modules: `// ---------- Section name ----------`. Used in the existing `renderer.v`; keep the style.
- **Inline comments only when the WHY is non-obvious.** Don't narrate what the next line does; do call out:
  - Constants whose origin is in SPEC (`// see SPEC §1.4 — H_FB_START = 144 + 20`).
  - Non-obvious bit-width tricks (`// 9-bit add to catch overflow before bounds check`).
  - Vblank-budget reasoning (`// 36864 vs 36000 — see GOTCHAS §G3`).
  - **`⚠ UNCERTAINTY` markers** at the exact decision point (see §11 below).
- **Don't add comments that re-state the spec.** SPEC.md is the source of truth — point to it instead of paraphrasing.

---

## 10. Port-list ordering

1. Clock(s).
2. Reset.
3. Inputs from upstream timing/control modules (`bright`, `hCount`, `vCount`).
4. Inputs from game logic (positions, bullet buses, active masks).
5. Outputs.

Within each group, line up the names. Use one port per line.

---

## 11. ⚠ UNCERTAINTY markers

When the SPEC does not pin down a decision, the rtl-agent **must not silently guess**. Instead, emit an inline comment at the decision point:

```verilog
// ⚠ UNCERTAINTY: should fb_wr_data hold its previous value when fb_we=0,
//                or be driven to 0? — assumed: hold (don't care path).
//                Reason: SPEC §5 doesn't say; holding saves a mux.
fb_wr_data <= ...;
```

Format: `⚠ UNCERTAINTY: <question> — assumed <value> because <reason>.`

The same item should appear in the IMPL DECISIONS block at the top of the file in summary form. The qc-agent's audit step 7 will check whether the SPEC actually answers the question (and flag CRITICAL if so) or genuinely doesn't (and flag upward).

---

## 12. Linting / sanity check the rtl-agent runs before declaring done

If `iverilog` is available locally:

```bash
iverilog -Wall -g2001 -o /tmp/build_<module> <list of .v files needed to compile this one standalone>
```

Compile must succeed cleanly. `-Wall` warnings about implicit nets, port-width mismatches, or redundant logic must be addressed. The 7-step self-check list in the rtl-agent prompt is the full pre-handoff gate.
