# Global CLAUDE.md

These global-level instructions you should always abide by.
If there are any conflicts in a project, what follows should always have precedence.

---

## Philosophy

### Zero Technical Debt
**Do the hard thing today to make tomorrow easy.**
Code, like steel, is easier to change while it's hot. Do it right the first time, the best you know how, because you may not get another chance, and because quality builds momentum. This is the only way to make steady progress, knowing that the foundations are solid.

Design systems like hardware engineers — deterministic, bounded, and performance-aware.
Write code like a surgeon — precise incisions, minimal collateral impact, verified outcomes.

**Key Principles:**
1. **Agent-First**: Delegate to specialized agents for complex work
2. **Parallel Execution**: Use Task tool with multiple agents when possible
3. **Plan Before Execute**: Use Plan Mode for complex operations
4. **Test-Driven**: Write tests before implementation
5. **Security-First**: Never compromise on security

---

## Core Reasoning Tenets

| Tenet | What It Prevents |
|---|---|
| **Think Before Coding** | Wrong assumptions, missed tradeoffs |
| **Simplicity First** | Over-engineering, bloated abstractions |
| **Surgical Changes** | Touching code nobody asked to touch |
| **Goal-Driven Execution** | Untested work, unverified success criteria |

---

## Communication & Workflow

- **Be concise.** No filler. Say what matters.
- **Explain tradeoffs before implementing.** If there are meaningful alternatives, surface them briefly.
- **Ask before making large structural changes.** A one-line question beats a 500-line wrong turn.
- **Flag deviations explicitly.** If a principle below must be relaxed (prototypes, scripts, spikes), say so and say why.

---

## SAFETY

***Correctness is necessary but not sufficient for safety.***

To be safe, a program must not only run correctly. It must apply defense-in-depth and verify itself while running — to run correctly, or else shut down if it detects that it has violated expectations.

### Error Handling Philosophy

- **Fail fast, fail loud.** Surface errors at the point of detection, not three layers up.
- **Assertions in debug, graceful shutdown in production.** Never silently swallow failures.
- **No undefined behavior.** Every code path must be accounted for — including the ones you think "can't happen."
- **Errors are values, not surprises.** Design error paths as deliberately as happy paths.

### Logical Interfaces

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

## Anti-Patterns — Never Do These

- ❌ **No lazy initialization** — know your resources at startup
- ❌ **No unbounded queues** — every queue needs a size, a backpressure strategy, and a shed policy
- ❌ **No hidden allocations** — if it allocates, it should be visible and intentional
- ❌ **No stringly-typed interfaces** — use the type system, not string parsing, for structure
- ❌ **No silent fallbacks** — if a fallback path exists, log it, metric it, alert on it
- ❌ **No "temporary" hacks without a TODO and a ticket** — debt without a name is debt without a plan

---

## When to Relax These Rules

These principles target **production systems, libraries, and long-lived code**. For the following, they may be relaxed — but deviations must be **flagged explicitly**:

- Throwaway prototypes and spikes
- One-off scripts and tooling
- Exploratory / investigative code

Even then, prefer the spirit of these principles. A prototype that respects boundaries is a prototype that teaches you something true.
