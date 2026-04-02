# Request Matrix (ReqMat)

## WHY
Multiple input ports may request the same output direction in the same cycle.  
A router cannot let more than one input drive a single output.  
The Request Matrix provides a clear input→output request map so the Switch Allocator can perform arbitration.

---

## WHAT
ReqMat is a 2D table:

- Rows represent input ports  
- Columns represent output directions (N, S, E, W, L)  
- A '1' means the input is requesting that output  
- A '0' means no request  

Example:

| Input \ Output | N | S | E | W | L |
|----------------|---|---|---|---|---|
| In0            | 0 | 0 | 1 | 0 | 0 |
| In1            | 0 | 0 | 1 | 0 | 0 |
| In2            | 1 | 0 | 0 | 0 | 0 |
| In3            | 0 | 0 | 0 | 1 | 0 |

---

## HOW
1. Each RC unit outputs a one-hot direction for its corresponding input FIFO.  
2. The Request Matrix collects these one-hot outputs into a 2D input-vs-output table.  
3. This matrix is passed to the Switch Allocator.  
4. The allocator examines each column (each output direction) and selects exactly one input per output using an arbitration policy.

---

## Summary
The Request Matrix organizes per-input routing decisions into a structured table that enables clean and correct arbitration in the Switch Allocator.
# Request Matrix (ReqMat)

## Correct Architecture
A single router has:
- 5 input ports  
- 5 RC units (one per input port)  
- **One** Request Matrix collecting all 5 RC outputs  

So the structure is:

```
[5 × RC outputs] ---> [Request Matrix] ---> [Switch Allocator]
```

---

## What the Request Matrix Does
The Request Matrix does **not** compute anything itself.  
Its only job is to **arrange** the 5 one-hot RC outputs into a consistent 2D matrix.

If each RC outputs a 5-bit one-hot direction:
- Bit order: **N S E W L** (example)
- Then the ReqMat forms a **5×5 table**:

| Input \ Output | N | S | E | W | L |
|----------------|---|---|---|---|---|
| In0            | rc0_N | rc0_S | rc0_E | rc0_W | rc0_L |
| In1            | rc1_N | rc1_S | rc1_E | rc1_W | rc1_L |
| In2            | rc2_N | rc2_S | rc2_E | rc2_W | rc2_L |
| In3            | rc3_N | rc3_S | rc3_E | rc3_W | rc3_L |
| In4            | rc4_N | rc4_S | rc4_E | rc4_W | rc4_L |

This is the **exact structure** the Switch Allocator needs.

---

## Why Only One ReqMat Per Router
- A router makes switching decisions **globally**, not per input.  
- The SA needs to compare **all input requests at once**.  
- Therefore, one combined 2D matrix is required.  

Multiple ReqMats would break arbitration — the allocator must see **the whole picture**.

---

## How ReqMat Works (simple)
1. RC0 produces a 5-bit one-hot → fill row 0  
2. RC1 produces a 5-bit one-hot → fill row 1  
3. RC2 → row 2  
4. RC3 → row 3  
5. RC4 → row 4  

ReqMat does **zero logic**.  
It is **just wiring + arranging signals**.

---

## Summary
- **5 RCs → 1 ReqMat → Switch Allocator.**  
- ReqMat is a simple, structured container.  
- It creates the 2D contention map the allocator needs.  
