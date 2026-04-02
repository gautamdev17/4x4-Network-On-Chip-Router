# Route Compute (RC)

## Why RC exists
Packets arriving at a router carry a destination in the header.  
RC decides **which output port** (N, S, E, W, Local) the packet must take next — the essential first step for forwarding.

## What RC does
- Monitors the **header flit** at the head of the input FIFO.  
- Extracts destination (coords / ID) from that header.  
- Compares destination with the router's own coordinates/ID.  
- Emits a **single routing decision** (one-hot direction) and holds it for the packet lifetime.  
- Produces a request entry for the Request Matrix (input → desired output).

## How RC works (conceptual steps)
1. **Header ready** — when FIFO presents the header flit, RC reads its destination field.  
2. **Compare** — evaluate destination vs. local coordinates:  
   - if `dest_x > curr_x` → `EAST`  
   - else if `dest_x < curr_x` → `WEST`  
   - else if `dest_y > curr_y` → `NORTH`  
   - else if `dest_y < curr_y` → `SOUTH`  
   - else → `LOCAL`  
3. **Request** — assert `req[input][direction] = 1` (one-hot) and keep it asserted until the packet's tail passes.  
4. **Hold** — RC’s decision must persist for all body/tail flits of the same packet so allocator/crossbar use the same path.

## Notes / design constraints
- RC is **combinational**/fast: it outputs direction when header is visible (no global FSM needed).  
- RC must be gated by FIFO `valid`/`not empty` — don’t run on empty FIFO.  
- For wormhole routing, RC runs only on header; subsequent flits follow the chosen route.  
- RC output feeds the Request Matrix, which the Switch Allocator reads to resolve conflicts.

## Why Route Compute (RC) compares destination vs router ID

A router sits inside a grid of many routers.  
When a packet arrives, the router must decide whether:

1. **This router is the packet’s final destination**, or  
2. **The packet must be forwarded**, and if so, **in which direction**.

The only way to make that decision is to **compare**:

- The packet’s destination address (from the header flit)  
- The router’s own address (hardwired as its ID or (x,y) coordinate)

### Why comparison is essential
- If the destination equals the router’s ID → deliver to LOCAL port.  
- If the destination is to the right → forward EAST.  
- If the destination is to the left → forward WEST.  
- If the destination is above → forward NORTH.  
- If the destination is below → forward SOUTH.

Without comparing, the router has **no idea** whether the packet:
- has reached its final node, or  
- must continue traveling in the mesh, and  
- what direction it must travel.

### Summary
The comparison step is the core decision-making action of RC.  
It turns the destination address inside the packet into a **directional routing choice**, enabling the router to forward packets through the network correctly.
