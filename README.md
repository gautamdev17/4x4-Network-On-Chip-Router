# 4×4 NoC Router (Verilog)

## Overview
A 4×4 Network-on-Chip (NoC) router is a synchronous digital design block with four input ports and four output ports. It forwards fixed-width data units (flits) from any input to any output based on a destination field inside each flit.  
This router structure is commonly used inside CPUs, GPUs, DSPs, and accelerator SoCs.

---

## Flit Format (32-bit)
- **Bits 31–28:** Destination port (XY) system
- **Bits 27–0:** Payload data

Destination mapping:
- N - 10000
- S - 01000
- E - 00100
- W - 00010
- L - 00001

---

## Architecture Stages

### 1. Input FIFOs
Each input port has a FIFO buffer that stores flits and handles congestion when multiple inputs target the same output.

### 2. Route Computation
Extracts the 4-bit destination field from each FIFO’s head flit to determine the output port it requests.

### 3. Request Matrix (4×4)
Generates a matrix `req[i][j]` where:
- `i` = input port (0–4)
- `j` = output port (0–4)
- `req[i][j] = 1` if input *i* requests output *j*

### 4. Switch Allocator
Each output port has its own arbiter.  
It inspects the requests for that output and selects one input (fixed-priority or round-robin).  
Outputs a one-hot `grant` signal.

### 5. Crossbar
Uses grant signals to connect the winning input to its corresponding output.  
Acts as a set of multiplexers forwarding flits to NSEWL.

---

## Data Flow Summary
1. Flits arrive at IN0–IN4 and enter their FIFOs.  
2. Route computation extracts destination bits.  
3. A request matrix is generated.  
4. Each output arbiter selects one requesting input.  
5. The crossbar forwards the selected flits to NSEWL.

---

