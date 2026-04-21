---
name: high-perf-systems
description: Use when designing performance-critical systems, hot paths, embedded code, databases, kernels, or any work where latency, throughput, or resource bounds matter. Provides TigerStyle-inspired engineering discipline (static allocation, control/data plane separation, primary colors of performance) and the corresponding anti-patterns.
---

# High-Performance Systems Engineering

Discipline for performance-critical paths. Hardware-engineer mindset: deterministic, bounded, performance-aware.

## Logical Interfaces (Safety + Performance)

***The safety (as well as performance and experience) of a system is dominated by the quality of its interfaces.***

- Minimize surface area
- Define fault models
- Abstract physical non-deterministic interfaces with logical deterministic interfaces
- Push control flow up and data flow down

---

## PERFORMANCE

***The lack of back-of-the-envelope sketches is the root of all evil.***

Think about performance from the outset. The time to solve performance, and get the 1000x wins, is in the design phase, when you can't profile. It's hard to fix a system after implementation, and the gains are less. Have mechanical sympathy. Like a carpenter, work with the grain.

### Static Memory Allocation

Allocate all needed memory at initialization. After startup, the system should run without dynamic allocation.

- Pre-size buffers, pools, and arenas upfront
- No hidden allocations in hot paths
- If a capacity limit is reached, that's a design error — not a reason to malloc

### Control Plane / Data Plane Separation

Separate the *what to do* (control) from the *doing it* (data).

- **Control plane:** Configuration, orchestration, scheduling, policy. Can be complex, runs infrequently.
- **Data plane:** The hot path. Must be simple, predictable, and fast.
- Never let control-plane concerns leak into the data plane.

### Make the Roads Bigger

Design for throughput, not just latency. Think in batches, pipelines, and amortized costs.

- Prefer batched operations over one-at-a-time processing
- Design data structures for cache-friendly sequential access
- Plan for concurrency from the start — don't bolt it on later

### The Primary Colors of Performance

Reason about performance through **4 resources × 2 textures**:

| | Sequential | Concurrent |
|---|---|---|
| **CPU** | Instructions per task | Parallelism across cores |
| **Memory** | Footprint per unit | Cache locality / sharing |
| **Storage** | I/O per operation | Throughput / queue depth |
| **Network** | Latency per call | Bandwidth / batching |

This framework gets you roughly right and within 90% of global maxima. Use it before reaching for a profiler.

---

## Anti-Patterns — Systems-Specific

- ❌ **No lazy initialization** — know your resources at startup
- ❌ **No unbounded queues** — every queue needs a size, a backpressure strategy, and a shed policy
- ❌ **No hidden allocations** — if it allocates, it should be visible and intentional

---

## When to Relax These Rules

These principles target **production systems, libraries, and long-lived code**. For the following, they may be relaxed — but deviations must be **flagged explicitly**:

- Throwaway prototypes and spikes
- One-off scripts and tooling
- Exploratory / investigative code

Even then, prefer the spirit of these principles. A prototype that respects boundaries is a prototype that teaches you something true.
