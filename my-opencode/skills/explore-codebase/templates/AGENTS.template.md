# {{CODEBASE_NAME}} — study project

<!-- GEN: one-paragraph description of the codebase: what it is, upstream URL,
     which files/directories hold the code under study. -->
{{CODEBASE_DESCRIPTION}}

**Prerequisites:** {{PREREQUISITES}}

## Project goal

***In this project we're NOT building anything.***

The goal is to gain a deep understanding of this codebase.
<!-- GEN: expand per the interview `purpose`:
     - performance: "…its design and why it is implemented this way. What are the
       trade-offs (performance/maintenance/memory) versus other possible
       implementations."
     - logic: "…how it works: its invariants, control flow, and why the logic is
       structured this way."
     - architecture: "…how it is organized: module boundaries, layering, dependency
       choices, and the reasons behind them."
     - general: combine the above. -->
{{PURPOSE_STATEMENT}}

**Scope:** {{SCOPE_STATEMENT}}
<!-- GEN: per interview `depth`:
     - whole-codebase: "The codebase is small enough to study file-by-file without
       loss of context."
     - question-driven: "The codebase is large; the study is question-driven. Each
       topic starts by locating the code that implements the concept in question,
       then focuses on that slice. We never attempt to cover the whole repo." -->

### Points of emphasis

<!-- GEN: pick per purpose; keep the "why + alternatives" framing for each bullet. -->
- ***Data structures:*** What data structures are used and why. Are there better
  solutions? Was performance sacrificed for readability/maintainability — or vice versa?
- ***Algorithms:*** What algorithms are used and why. If an asymptotically better
  alternative exists, why was it not chosen? (Constant factors, locality, small-n,
  simplicity are all legitimate answers — but they must be *demonstrated*, not assumed.)
{{EXTRA_EMPHASIS_POINTS}}

## In practice

- Me and you are both students and teachers at the same time.
- ***DO NOT EVER BE SYCOPHANTIC:*** if I am misunderstanding concepts or building wrong
  intuitions, don't be condescending, but correct me and show the way by citing code or
  measurement.
- As the conversation progresses, keep building the artifact
  `study/understanding-{{name}}.md` (already scaffolded). It is organized in **two
  layers** (see [Artifact](#artifact)): a **code walkthrough** that follows the source
  unit by unit, and a **concept reference** that treats each concept in its generality.

## Claim discipline

This is the core rule of the project. It exists because of a real failure class: a
**confident causal claim that sounds like textbook knowledge, reads as plausible to
any text reviewer, and is false** — only an empirical check catches it. (One real
instance, from a C study: "packed structs are necessary for pointer arithmetic" —
plausible, confidently phrased, wrong. The domain is incidental; the shape is what
recurs.) {{STACK_LOCAL_FAILURE_EXAMPLE}}
<!-- GEN: replace {{STACK_LOCAL_FAILURE_EXAMPLE}} with one sentence giving a
     hypothetical instance of the same failure shape phrased in THIS codebase's
     stack, introduced as hypothetical. E.g. Rust: 'Here it would look like: "this
     block needs `unsafe` because the borrow checker cannot prove X."' Python:
     'Here it would look like: "this uses a list because dict lookup would be
     slower here."' One sentence only. -->

Every factual claim that enters the artifact is one of two kinds, and each kind has its
own evidence requirement:

- **Concept claim** — a general statement about a technique, independent of this
  codebase ("cache locality can beat asymptotic complexity for small n").
  *Evidence:* a standalone example (`study/examples/`) that runs clean, and — when the
  claim has a failure mode worth demonstrating — a counter-example (`study/counter/`)
  that fails exactly as declared.
- **Codebase-causal claim** — a statement about why *this* code is the way it is
  ({{CAUSAL_CLAIM_EXAMPLE}}).
  <!-- GEN: one short quoted example of a causal claim phrased in this codebase's
       stack, e.g. C: '"this struct is packed *because* the header walk requires
       exact offsets"'. -->

  *Evidence:* source-pinned — one or more of:
  - exact file:line citations,
  - a probe against the *actual* definitions (copy them into a scratch file if the
    project doesn't build cheaply: `sizeof`/`offsetof` checks, remove-the-attribute-
    and-observe, etc.),
  - commit history or author comments stating the reason.

  A concept demo **never** counts as evidence for a codebase-causal claim — showing
  that a technique works in general says nothing about whether it is the operative
  reason here.

Mark every codebase-causal reason as **`documented`** (authors said so — cite where) or
**`inferred`** (our reasoning — state the evidence). If a claim cannot be checked at
all, it enters the artifact marked **`[unverified]`** and is phrased as a hypothesis,
never as fact.

## Verification workflow

Before a topic/section is considered done and logged, run **`/verify-topic <section>`**.
It dispatches the adversarial verifier subagent (`.opencode/agent/verifier.md`) via the
Task tool against the section and its example files. `[CRITICAL]` and `[HIGH]` findings
must be fixed and re-verified before the session-log entry is written. Welcome verifier
findings as corrections, not attacks.

## Current focus

*(Derive this at the start of each session from the most recent `study/SESSION_LOG.md`
entry — do not hand-maintain a separate copy, so it can't drift.)*

- **Current topic:** what we're studying right now
- **Next topic:** what we plan to cover after
- **Completed:** quick list of topics already covered (from the log)

## Session log

Each session starts by reviewing `study/SESSION_LOG.md` to avoid re-covering old
ground. Append a new entry after each session:

```
## Session YYYY-MM-DD
- Covered: [list of key topics]
- Verified: [sections that passed /verify-topic]
- Artifact additions: [sections updated in study/understanding-{{name}}.md]
- Files touched: [path — created|modified — why (which concept/example)]
- Open questions: [anything left unresolved]
```

## Study directory

All study output lives under `study/`; the studied source files are **read-only, never
modified**.

```
study/
  understanding-{{name}}.md   # the artifact (lecture notes)
  SESSION_LOG.md              # session log
  {{BUILD_FILE}}              # builds/runs examples + counter-examples
  examples/                   # NN-concept.{{ext}}      — run clean
  counter/                    # NN-concept-bad.{{ext}}  — fail as documented
```

- **Naming:** runnable code is anchored to the **concept** it demonstrates.
  `NN-concept.{{ext}}` mirrors each `## Concept: [Name]` (Layer 2) section 1:1, where
  `NN` is the concept id. A code-walkthrough (Layer 1) section cites examples through
  the concept link rather than owning its own files.
- **Single source of truth:** the canonical, runnable code is the file under
  `examples/` or `counter/`. Inline snippets in the artifact are excerpts quoted from
  it — never diverge them.
- **Build/run contract:** {{BUILD_INSTRUCTIONS}}
  <!-- GEN: concrete instructions for this stack. Behavioral contract (invariant):
       every example must run clean; every counter-example must declare its expected
       failure mode (crash / sanitizer trip / exception / wrong output) and be
       verified to fail exactly that way. For compiled languages: pinned optimization
       flag (OPT variable), sanitizers on counter builds, note how to regenerate any
       LSP compilation database. For interpreted: the runner script and interpreter
       version. -->
- **Nondeterministic demonstrations:** a claim that is inherently timing- or
  scheduling-dependent (concurrency, GC, network, scheduler behavior) still falls
  under the contract. Its example must either force determinism where the stack
  allows it {{DETERMINISM_NOTE}} or assert on **invariants rather than timings**, and
  must state its platform assumptions (core count, OS, runtime version) in a header
  comment. A demo that shows the effect only "usually" is a contract violation, not
  an acceptable example.
  <!-- GEN: replace {{DETERMINISM_NOTE}} with a parenthetical of stack-specific
       forcing knobs, e.g. Python: '(e.g. `sys.setswitchinterval`, threading
       barriers, fixed seeds)'; C: '(e.g. pinned CPU affinity, barriers, fixed
       seeds)'. Include this bullet only if the study's purpose or detected stack
       makes such claims plausible; otherwise omit the whole bullet. -->

## Artifact

Think of the artifact as detailed lecture notes a CS lecturer uses to both teach and
aid students. It should explain what the code does and how it works — but concepts are
extracted and kept **in their generality**:

- Why is this concept/data structure/algorithm used?
- Are there alternatives?
- Is the decision due to performance or design purposes?

(Do not limit yourself to these questions — propose other meaningful insights and ask
more questions yourself.)

### Two-layer organization

The artifact is a single file (`study/understanding-{{name}}.md`, compiled to one PDF)
split into **two layers**. This mirrors how we actually study — one region of the
source per session — while still treating each concept once, in its generality.

- **Layer 1 — Code walkthrough (primary axis).** One section per **source unit** (a
  function, a family of types, a module, a code path). Sections follow the source /
  natural reading order. This layer holds all **codebase-specific** detail: the actual
  annotated code, exact offsets/layouts where relevant. It shows how one real code unit
  **braids several concepts together**. Each section's frontmatter lists the concepts
  it uses and *why*, linking to Layer 2 — it does **not** re-explain them.
- **Layer 2 — Concept reference (generality).** One section per **concept**. Each
  concept is explained **once**, standalone and generalizable: the problem, general
  principles, alternatives, trade-offs. No codebase-specific walkthroughs here —
  instead back-links to the Layer 1 sections that rely on it. This is the reusable,
  transferable material.

**Anchors.** Every section carries a **stable pandoc anchor id** so links survive edits
and resolve in the PDF: concepts get `{#cN}` (`## Concept: Struct packing {#c1}`), code
units get `{#code-<slug>}`. All cross-references are **real markdown links** to these
ids, never bare text.

**Three navigation aids, kept in sync as sections are added:**

1. **Index** (top of the artifact, right after the intro) — a two-axis map: each code
   unit → the concept ids it uses; each concept → the code units that use it.
   Regenerate whenever a section is added.
2. **Frontmatter** (top of every section, immediately under the heading) — a code unit
   lists the concepts it uses (linked, one-line *why*); a concept lists the code units
   that use it (linked, with the role it plays) plus related concepts. This is the
   single home for that section's cross-reference list.
3. **Inline links** — wherever a concept is named in prose, link it by id.

Explain each concept in exactly one place (its Layer 2 section) and link to it
everywhere else — never duplicate the explanation.

**Order of work.** When studying a code unit: write/extend its Layer 1 section (heading
+ anchor + frontmatter first), then for every concept it touches either add a new
Layer 2 concept or extend the existing one and add the back-link. Regenerate the Index.
Then run `/verify-topic` before logging.

### Layer 1 section outline

```markdown
## Code: [unit name] {#code-<slug>}

`Source: <file>:<lines>`

> **Concepts used**
>
> | id | concept | why it's used here |
> |----|---------|--------------------|
> | [C1](#c1) | ... | ... |

### What this code does
- Plain-language narration: inputs, steps, output.

### Walkthrough
- The actual code, annotated block by block. All codebase-specific detail lives here.
  Every codebase-causal claim carries its evidence tag (documented/inferred) and
  citation, per the Claim discipline.

### Open questions
- Things worth exploring further.
```

### Layer 2 section outline

```markdown
## Concept: [Name] {#cN}

> **Used by**
>
> | code unit | role of this concept there |
> |-----------|----------------------------|
> | [Code: ...](#code-...) | ... |
>
> **Related concepts:** [C2](#c2)

### What is it? (Problem statement)
- What problem does this concept solve? (general, not codebase-specific)

### General principles
- Why is this useful beyond this codebase? Where else does the pattern show up?

### Alternatives & trade-offs
- What other approaches exist? What makes the chosen approach better or worse?

### Open questions

### References (preferable)
- External sources to study the concept in its generality.

### Code
- examples/NN-concept.{{ext}}      — runnable example (runs clean)
- counter/NN-concept-bad.{{ext}}   — counter-example (declares expected failure mode)
```

### Styling (PDF rendering)

The artifact opens with a pandoc YAML metadata block (already scaffolded — keep it in
sync with future rendering tweaks):

```yaml
---
colorlinks: true
linkcolor: blue
urlcolor: blue
geometry: margin=3cm
---
```

Compile check: `pandoc understanding-{{name}}.md -o understanding-{{name}}.pdf
--pdf-engine=xelatex` from `study/`.

## Tooling

<!-- GEN: propose the concrete inspection/measurement toolbox for the detected stack
     and the interview's tooling-reality answer. Examples of the kind of content:
     - C/C++: gdb, valgrind, perf, hyperfine, objdump, sanitizers; note the pinned
       OPT flag and that perf counters may need kernel.perf_event_paranoid lowered.
     - Python: dis, cProfile, tracemalloc, pytest for probes.
     - Rust: cargo asm/expand, criterion, miri.
     - Go: pprof, benchstat, go test -bench.
     State whether the project itself builds cheaply (in-tree probes allowed) or not
     (copied-definition probes only), per the interview. -->
{{TOOLING_SECTION}}

<!-- GEN: include the entire section below ONLY when purpose is `performance` or
     `general`. Omit it otherwise. -->
## Performance lens

When a concept has performance stakes, evaluate it along these dimensions. State
tools/measurements in the general — do **not** pre-name this codebase's internals;
discovering those is the point of the study.

- **Causality first:** every performance statement must trace mechanism → effect →
  metric. No number without the cause that produced it.
- **Memory footprint** — per-object overhead vs payload, layout, allocator rounding.
- **Allocations & system calls** — counts, and any growth/preallocation strategy.
- **Cache / memory access** — locality, alignment.
- **Branches** — dispatch cost of runtime type/tag selection.
- **Time / cycles** — wall-clock A/B comparisons on warm runs, pinned flags.

{{PERF_TOOLING_NOTES}}
<!-- GEN: fill with the stack-appropriate measurement commands (the C list from the
     SDS study: sizeof/malloc_usable_size/massif; ltrace/strace; perf stat events;
     hyperfine — or equivalents for the stack). Include benchmark hygiene notes. -->

## Success looks like

- `study/understanding-{{name}}.md` is a self-contained reference — someone unfamiliar
  with the codebase can understand {{SUCCESS_SCOPE}} without reading the source.
  <!-- GEN: whole-codebase depth → "the library's internals";
       question-driven depth → "every studied topic". -->
- It compiles to PDF with pandoc.
- Every example runs clean; every counter-example fails in its declared way.
- Every claim satisfies the Claim discipline; every logged section passed
  `/verify-topic`.
- Concepts are explained in their generality, not just as codebase specifics.
- `study/SESSION_LOG.md` records what was studied, in what order, and which files were
  created/modified along the way.

## Behavioral notes

- Whenever anything is not clear, ask.
- Challenge everything I say.
- ***DO NOT BE SYCOPHANTIC:*** I'd rather be told I've had a terrible idea and abort it
  than pursue it.
