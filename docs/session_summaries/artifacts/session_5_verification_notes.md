# Session 5 — Verification Notes: `player_bullet` Testbench

**File produced:** `ee354_bullet_hell/sim/player_bullet_tb.v`
**Module under test:** `player_bullet` (RTL not yet written at authoring time)
**Contract source of truth:** `docs/SPEC.md` §10.2 (all subsections)
**Auxiliary references:** `docs/SPEC.md` §1.1 (game_tick), §1.7 (names), §1.8 (bullet-bus packing); `docs/GOTCHAS.md` §G9, §G14, §G15.

All expected values were derived from SPEC text — not from any implementation (none exists yet).

---

## Coverage matrix

| # | Test name | What it drives | Expected output | SPEC cite(s) |
|---|-----------|---------------|-----------------|--------------|
| T1.a | Reset — pb_active | reset high 3 cycles then low | `pb_active === 8'd0` | §10.2.6 |
| T1.b | Reset — pb_x_flat | same | `pb_x_flat === 64'd0` | §10.2.6 |
| T1.c | Reset — pb_y_flat | same | `pb_y_flat === 64'd0` | §10.2.6 |
| T1.d | Reset — shoot_latch | bare `game_tick`, no prior `shoot_pulse` | no spawn (`pb_active === 8'd0`) | §10.2.6, §10.2.2 step 3 |
| T2.a | Spawn basic — active | `shoot_pulse`, then `game_tick`; `player_x=100`, `player_y=140` | `pb_active === 8'b0000_0001` | §10.2.5 (lowest-index-first) |
| T2.b | Spawn basic — x | same | `pb_x0 === 8'd100` | §10.2.2 step 3 |
| T2.c | Spawn basic — y | same | `pb_y0 === 8'd124` (140 − 16) | §10.2.2 step 3 |
| T2.d | Spawn basic — others idle | same | `pb_active[7:1] === 7'b000_0000` | §10.2.5 |
| T3.a | Priority setup | 3 × fire_and_tick at `player_y=140` | `pb_active === 8'b0000_0111` | §10.2.5 |
| T3.b | Priority — slot 1 cleared | `hit_mask = 8'b0000_0010` on a `game_tick` | `pb_active === 8'b0000_0101` | §10.2.2 step 2 |
| T3.c | Priority — fill slot 1 | `shoot_pulse` + `game_tick` | `pb_active === 8'b0000_0111` | §10.2.5 |
| T3.d | Priority — slot 1 x | same | `pb_x1 === 8'd50` | §10.2.2 step 3 |
| T3.e | Priority — slot 1 y | same | `pb_y1 === 8'd124` | §10.2.2 step 3 |
| T4.a | Overflow — pool full | 8 × fire_and_tick | `pb_active === 8'b1111_1111` | §10.2.5 |
| T4.b | Overflow — drop | 9th fire_and_tick | `pb_active` unchanged (`8'b1111_1111`) | §10.2.5 ("drop silently") |
| T5.a | Multi-pulse collapse | 3 × `shoot_pulse` between ticks, 1 `game_tick` | `pb_active === 8'b0000_0001` | §10.2.3 |
| T6.a | Advance — pre-condition | spawn with `player_y=116` → spawn y=100 | `pb_y0 === 8'd100` | §10.2.2 step 3 |
| T6.b | Advance — N=2 | one `game_tick`, no shoot | `pb_y0 === 8'd98` | §10.2.2 step 1; Q7 |
| T6.c | Advance — still active | same | `pb_active === 8'b0000_0001` | §10.2.2 step 2 |
| T7.a | Top-exit — precondition | spawn with `player_y=17` → spawn y=1 | `pb_y0 === 8'd1` | §10.2.2 step 3 |
| T7.b | Top-exit — active | same | `pb_active === 8'b0000_0001` | §10.2.2 step 3 |
| T7.c | Top-exit — despawn | next `game_tick` (1 − 2 = 8'd255; 255 ≥ 150) | `pb_active[0] === 1'b0` | §10.2.2 step 2 |
| T7.d | Top-exit — others clean | same | `pb_active === 8'b0000_0000` | §10.2.2 step 2 |
| T8.a | hit_mask — precondition | 3 × fire_and_tick | `pb_active === 8'b0000_0111` | §10.2.5 |
| T8.b | hit_mask — slot 2 cleared | `hit_mask = 8'b0000_0100` on one `game_tick` | `pb_active === 8'b0000_0011` | §10.2.2 step 2, §10.2.1 |
| T9.a | Spawn underflow — y | `player_y=10`, spawn (10 − 16) mod 256 = 250 | `pb_y0 === 8'd250` | §10.2.2 step 3 |
| T9.b | Spawn underflow — active one tick | same | `pb_active === 8'b0000_0001` | §10.2.2 step 3 |
| T9.c | Spawn underflow — despawn next tick | one more `game_tick`, no shoot (250 − 2 = 248; 248 ≥ 150) | `pb_active === 8'b0000_0000` | §10.2.2 step 2 |
| T10.a | Latch-clear — pool full | 8 × fire_and_tick | `pb_active === 8'b1111_1111` | §10.2.5 |
| T10.b | Latch-clear — drop | 9th fire_and_tick (pool full) | `pb_active === 8'b1111_1111` | §10.2.5 |
| T10.c | Latch-clear — behavioral proof | one `game_tick` with `hit_mask = 8'b0000_0001` and **no** `shoot_pulse` | `pb_active[0] === 1'b0` (not refilled — proves latch cleared) | §10.2.5 + §10.2.3 |
| T10.d | Latch-clear — no collateral | same | `pb_active[7:1] === 7'b111_1111` | §10.2.2 |
| T10.e | Latch-clear — refill works | subsequent fire_and_tick | `pb_active[0] === 1'b1` | §10.2.2 step 3 |

Total: 33 assertions over 10 SPEC-driven scenarios.

---

## Design choices

- **Assertion style.** A Verilog-2001 `task check(name, cond, spec_cite)` that increments either a `passes` or `errors` counter and prints a one-line FAIL message with the SPEC cite. SPEC §0 (Q1) bars `assert` and SystemVerilog constructs.
- **Clock.** 25 MHz (40 ns period) per SPEC §1.1. Single `always #20 pixel_clk = ~pixel_clk;`.
- **Pulse modeling.** `game_tick` and `shoot_pulse` are driven from `negedge pixel_clk` so the DUT's `posedge pixel_clk` logic sees a stable one-cycle pulse. Matches GOTCHAS §G15 edge-detect discipline.
- **shoot_pulse vs game_tick ordering.** §10.2.3's `always @(posedge pixel_clk)` chain writes `shoot_latch` with `else if (game_tick) ... else if (shoot_pulse)`. If both were asserted on the same cycle, `game_tick` wins and the pulse is lost. The `fire_and_tick` helper separates them onto distinct cycles.
- **Reset sequencing.** `reset` asserted high for 3 negedges (≥2 full `posedge` cycles of high), then released; 2 further negedges before observing DUT outputs. This ensures synchronous reset takes effect and the post-reset register values are valid to read.
- **Slot accessors.** Named `pb_x0..pb_x7`, `pb_y0..pb_y7` wires derived from the flat buses per SPEC §1.8 (`bits[i*8 +: 8]`, slot 0 at LSB).
- **T10 observation technique.** Per task brief: `shoot_latch` is an internal reg and we must not add a debug port (and must not modify RTL). Instead, the pool-full tick's latch-clear behavior is proved negatively: after the pool-full tick, a `game_tick` with a `hit_mask` freeing slot 0 and *no* fresh `shoot_pulse` must **not** re-fill slot 0. If the latch had leaked set, the spawn logic in §10.2.2 step 3 would observe `shoot_latch == 1`, find slot 0 free, and refill it. Slot 0 remaining empty is the required outcome. T10.e then confirms the spawn path itself is healthy by issuing a fresh `shoot_pulse` and observing the refill.
- **Self-check output.** Final `$display` prints `TEST PASSED` or `TEST FAILED: N error(s)`. A 200 µs simulation timeout sits in a separate `initial` block to catch a wedged DUT.

---

## Pending tests

None. SPEC §10.2 has no remaining ⚠ UNDECIDED items blocking verification:

- **Q7** (N bullet speed) is pinned at N=2 in §10.2.5, so T6 uses N=2.
- **Q9** (collision-hit signal semantics) has its default pinned in §10.2.1 ("bit i = despawn slot i this tick") — T3.b and T8.b exercise exactly that semantics. If Q9 later changes (e.g., to a pulse-event semantic), those two checks will need to be updated.

No test had to be left as a `// PENDING:` stub.

---

## Potential bug surfaces exposed by these tests

The checks collectively pin down the following implementation pitfalls the RTL author must avoid:

1. **Using pre-step-2 `pb_y` in the despawn comparator** instead of `pb_y_next` — caught by T7.c and T9.c, which require despawn on the tick where the advance *produces* a ≥150 value.
2. **Registering outputs with a cycle of extra latency** — `pb_active`, `pb_x_flat`, `pb_y_flat` must be combinational functions of the underlying state regs (§10.2.7). If the DUT pipes them through another register, T2.a would still pass (we wait an extra negedge), but T7.c would see a delayed despawn and fail.
3. **`shoot_latch` not clearing on overflow tick** — T10.c catches this directly.
4. **Latching `shoot_pulse` only on `game_tick`** (instead of every `pixel_clk`) — T5.a would fail because only the last of three pulses would be observed.
5. **Priority encoder that prefers highest (not lowest) free index** — T2.a and T3.c both catch this.
6. **8-bit advance/underflow handled with signed comparison** — T7.c specifically demands the `>= 150` check on the unsigned underflowed value (255), which is the SPEC-sanctioned way to catch exit-via-top.

---

## Run instructions (for rtl-agent's next session)

Once `src/player_bullet.v` exists:

```
iverilog -Wall -g2001 -o /tmp/player_bullet_tb \
    ee354_bullet_hell/src/player_bullet.v \
    ee354_bullet_hell/sim/player_bullet_tb.v
vvp /tmp/player_bullet_tb
```

Expected terminal output ends with `TEST PASSED`. Any `FAIL:` line cites the SPEC subsection to consult.
