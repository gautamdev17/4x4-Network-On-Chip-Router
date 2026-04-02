# Switch Allocator (SA)

## WHY
Multiple input ports may request the *same* output port in the same cycle.  
A router cannot connect more than one input to a single output.  
The SA resolves these conflicts by choosing **exactly one winning input** for each output port.

Without the SA, the router would not know which flit gets access to which output link, causing data corruption or starvation.

---

## WHAT
The SA takes the **Request Matrix** (5 inputs × 5 outputs) and performs:

1. **Per-output arbitration**  
   Each output port (N, S, E, W, L) runs its own arbiter.

2. **Winner selection**  
   One input port is chosen for each output port.

3. **Grant generation**  
   A one-hot grant signal is produced to indicate the selected input.

4. **SEL signaling for the crossbar**  
   Grants are encoded so the crossbar knows which input connects to which output.

5. **FIFO pop**  
   Only the winning inputs are popped (their flits advance).

---

## HOW
The SA processes the Request Matrix *column-wise*:

- Column "NORTH" contains all inputs requesting NORTH  
- Column "EAST" contains all inputs requesting EAST  
- etc.

Each column feeds into its own arbiter.

Example:
```
EAST requests = [in0, in1, in2, in3, in4]
```

The arbiter picks exactly one based on a scheduling policy (round-robin).

This happens **independently for all 5 outputs**, in parallel.

---

# Round-Robin Arbiter (RRA)

## WHY RRA?
If multiple inputs repeatedly request the same output, a fixed-priority scheme could starve lower-priority inputs.  
Round-robin guarantees **fairness** across cycles and prevents starvation.

---

## HOW RRA Works
Each output port has a **pointer** that indicates which input has the highest priority *for this cycle*.

Steps per arbitration cycle:

1. **Start checking from the pointer index**  
2. **Walk through all inputs in circular order**  
   Example order when pointer = 2:
   ```
   2 → 3 → 4 → 0 → 1
   ```
3. **Pick the first input whose request bit = 1**  
4. **Grant that input**  
5. **Move the pointer to (winner + 1)** for the next cycle

Example:
```
Requests on EAST: in0=1, in3=1
Pointer = in1
Check: in1(no) → in2(no) → in3(yes) → winner = in3
Next pointer = in4
```

This ensures every active input will eventually win.

---

# Other Arbiter Types

### 1. Fixed Priority Arbiter
- Inputs have permanent priority order (in0 > in1 > in2 > in3 > in4).
- Simple and fast.
- **Problem:** starvation of lower-priority inputs.

### 2. Random Arbiter
- Picks a random winner among contenders.
- Rarely used.
- **Problem:** unfair, unpredictable performance.

### 3. Matrix Arbiter (Parallel Priority)  
- Complex but very fast.
- Guarantee fairness without pointer rotation.
- Used in large crossbars or high-performance NoCs.
- Overkill for a 5-port router.

### 4. Age-Based Arbiter  
- Chooses the oldest packet.
- Gives excellent fairness.
- Needs timestamps → costlier hardware.

---

# Why Round-Robin is the Best Choice Here

1. **Fair (no starvation)**  
2. **Simple hardware** (just a pointer + priority logic)  
3. **Low area and timing cost**  
4. **Widely used in commercial NoCs**  
5. **Matches the scale of a 5-port router** perfectly  
6. **Provides deterministic performance** without over-engineering

In short:  
Round-Robin gives the best balance of **fairness**, **simplicity**, and **hardware cost**.

---

# Summary
The Switch Allocator ensures that each output port receives exactly one input per cycle by performing per-output arbitration. Using a Round-Robin arbiter guarantees fair and starvation-free access to the switch fabric. The SA is the key control component that resolves contention created by the Request Matrix and drives the crossbar and FIFO pops.
