# Global CLAUDE.md

These global-level instructions you should always abide by.
If there are any conflicts in a project, what follows should always have precedence.

---

## Philosophy

### Zero Technical Debt
**Do the hard thing today to make tomorrow easy.**
Code, like steel, is easier to change while it's hot. Do it right the first time, the best you know how, because you may not get another chance, and because quality builds momentum. This is the only way to make steady progress, knowing that the foundations are solid.

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
- **Don't be afraid to ask** If you have any doubts about the instrutcions you receive, ask for clarifications before proceeding.
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

---

## Anti-Patterns — Never Do These

- ❌ **No stringly-typed interfaces** — use the type system, not string parsing, for structure
- ❌ **No silent fallbacks** — if a fallback path exists, log it, metric it, alert on it
- ❌ **No "temporary" hacks without a TODO and a ticket** — debt without a name is debt without a plan

---

## Agent Orchestration

**Available subagents** (all configured in `~/.config/opencode/opencode.json`):

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `planner` | Implementation planning | Complex features, refactoring |
| `architect` | System design and scalability | Architectural decisions |
| `tdd-guide` | Test-driven development | New features, bug fixes |
| `code-reviewer` | Code quality review | After writing/modifying code |
| `security-reviewer` | Vulnerability detection | Sensitive code, pre-commit |
| `build-error-resolver` | Fix build/type errors | When build fails |
| `e2e-runner` | End-to-end Playwright testing | Critical user flows |
| `refactor-cleaner` | Dead code cleanup | Code maintenance |
| `doc-updater` | Documentation and codemaps | Documentation updates |
| `go-reviewer` | Go code review | Go projects |
| `go-build-resolver` | Go build errors | Go build failures |
| `database-reviewer` | PostgreSQL/Supabase specialist | Schema design, query optimization |
| `python-reviewer` | Python code review | Python projects |
| `java-reviewer` | Java/Spring Boot code review | Java/Spring Boot projects |
| `rust-reviewer` | Rust code review | Rust projects |

**Use parallel execution for independent operations** — launch multiple agents simultaneously.

## Common Workflows

**Starting a new feature:**
```
/plan "Add user authentication with OAuth" → planner creates implementation blueprint
/tdd                                     → tdd-guide enforces write-tests-first
/code-review                             → code-reviewer checks your work
```

**Fixing a bug:**
```
/tdd     → write a failing test that reproduces the bug
         → implement the fix, verify test passes
/code-review → catch regressions
```

**Preparing for production:**
```
/security    → security-reviewer runs OWASP Top 10 audit
/e2e         → e2e-runner tests critical user flows
/test-coverage → verify 80%+ coverage
```

## Workflow Surface Policy

- `skills/` is the canonical workflow surface.
- New workflow contributions should land in `skills/` first.
- `commands/` is a legacy slash-entry compatibility surface.
- Use the `strategic-compact` skill to manage context cleverly in a project

## Specialized Skills

For performance-critical or systems engineering work (hot paths, embedded code, databases, kernels, latency/throughput-bound systems), invoke the **`high-perf-systems`** skill. It provides static allocation, control/data plane separation, the primary colors of performance framework, systems-specific anti-patterns, and the "When to Relax These Rules" guidance for prototypes and one-off scripts.
