---
name: explore-codebase
description: >-
  One-shot initializer for a codebase-study project. Run it from inside any repo the
  user wants to *study* (not build): it interviews the user (purpose, depth, tooling),
  then generates a project-specific AGENTS.md study contract, an adversarial verifier
  agent, a /verify-topic command, and a study/ scaffold. Use whenever the user says
  they want to explore, study, deep-dive, or understand a codebase, learn from source
  code ("how does X implement Y?", "study this librarary concurrency"), or asks to set up a
  study project / learning harness for a repository — even if they don't name this
  skill. Do NOT use for building features, fixing bugs, or general code review.
---

# explore-codebase — study-project initializer

You are initializing a **study project**: the user wants to deeply understand an
existing codebase, not modify it. This skill runs **once** per codebase. After it
finishes, the generated files (`AGENTS.md`, verifier agent, `/verify-topic`) carry the
entire day-to-day workflow — you will not need this skill again for this repo.

The design descends from a codebase study that worked. It justifies the one non-obvious
choice here: the generated project is **adversarial about its own claims** rather than
trusting a review pass. That choice earned its place from an observed failure — the model
stated a plausible-but-false causal claim and believed it. (The original instance was in
C — "packed structs are necessary for pointer arithmetic" — but the shape is
language-independent: a confident causal claim that reads as textbook fact and is wrong.)
Text review by the same model does not catch this class; it finds the claim plausible too.
**Empirical verification does.** So the two mechanisms you must preserve faithfully when
instantiating the templates are the claim discipline and the verifier agent — the rest
(interview, scaffold, artifact format) is ordinary machinery around those two.

## Step 0 — Preflight (do this before asking anything)

1. Confirm you are inside the target repo (or ask for the path). The user typically
   runs this from a fresh clone of the codebase they want to study. If the study
   target is a *feature* rather than a repo (e.g. "the GIL", "Go's scheduler"), the
   repo is that feature's reference implementation (CPython, golang/go) — point the
   user there if they haven't cloned it, and record the feature focus in the scope
   statement so the study stays question-driven around it.
2. **Re-run safety:** if `AGENTS.md`, `study/`, `.opencode/agent/verifier.md`, or
   `.opencode/command/verify-topic.md` already exist here, STOP and ask before touching
   anything. Never silently overwrite — the user may have an ongoing study.
3. Detect the stack yourself (don't ask): look at file extensions, build files
   (`Makefile`, `Cargo.toml`, `package.json`, `pyproject.toml`, ...), and repo size
   (rough file/LOC count). You need: primary language(s), whether the project is
   compiled, and whether it looks small (studiable whole) or large (question-driven).

## Step 1 — Interview

Ask with the `question` tool (batch multiple questions in one call where sensible).
Skip anything already answered by the user's request or by preflight detection.

1. **Purpose** — what lens drives the study?
   - `performance` — why is it fast? data structures, algorithms, memory behavior
   - `logic` — how does it work? correctness, invariants, control flow
   - `architecture` — how is it organized? boundaries, layering, dependency choices
   - `general` — all of the above, follow curiosity
   Purpose controls whether the Performance-lens section and perf tooling go into the
   generated AGENTS.md (include for `performance` and `general`; omit for `logic` and
   `architecture` unless the user asks).
2. **Depth** — study the whole codebase (small repos) or question-driven
   slices ("which part implements X?" → focus there)? Recommend based on detected size;
   let the user decide.
3. **Tooling reality** — can the project itself be compiled/run cheaply? Are its tests
   runnable? This does NOT gate the study (examples are standalone), but it sets which
   probe kinds the verifier is told to use (in-tree probes vs copied-definition probes
   only).
4. **Verifier model** — default: inherit the session model (omit `model` in
   `.opencode/agent/verifier.md`). Mention it's a one-line edit there later; only ask
   if the user cares.
5. **Prerequisites** — what working knowledge should the study assume? Propose a
   default from the detected stack (e.g. C → pointers, structs, memory management) and
   let the user adjust.

## Step 2 — Generate

Read each template in `templates/` and instantiate it. Conventions:

- `{{NAME}}` markers are slots — replace with content derived from preflight +
  interview.
- `<!-- GEN: ... -->` comments are instructions to YOU, the generator — follow them,
  then delete them. The generated files must contain no leftover markers or GEN
  comments.
- Where a template says a section is conditional (e.g. Performance lens), include or
  omit the whole section per the interview answers.

Write into the target repo:

| Template | Output | Notes |
|---|---|---|
| `templates/AGENTS.template.md` | `./AGENTS.md` | The study contract |
| `templates/verifier.template.md` | `./.opencode/agent/verifier.md` | Adversarial verifier agent |
| `templates/verify-topic.template.md` | `./.opencode/command/verify-topic.md` | Per-topic verification gate |

Then scaffold `study/`:

```
study/
  understanding-{{name}}.md   # artifact skeleton: pandoc YAML block, intro stub,
                              # empty "## Index" with the two-part structure
  SESSION_LOG.md              # header + entry-format comment, no entries
  examples/                   # empty (with .gitkeep)
  counter/                    # empty (with .gitkeep)
  Makefile                    # compiled languages: build/run for examples/ and
                              # counter/ (sanitizers on counter), pinned OPT flag
  run.sh                      # non-compiled languages instead of Makefile: run all
                              # examples, run counter-examples expecting failure
```

Adapt the build file to the detected language — the contract is behavioral, not
technological: `examples must run clean; counter-examples must fail exactly as
declared`. For C/C++ use a Makefile with an OPT variable and `-fsanitize` on the
counter builds. For interpreted languages a simple runner script suffices.

Add generated-artifact entries to `.gitignore` if one exists (`study/build/`, etc.),
but never modify the studied source files themselves.

## Step 3 — Hand off

Tell the user, briefly:
- What was generated and where.
- That the study runs in normal sessions from now on — open the repo, ask the first
  question; `AGENTS.md` governs everything.
- That `/verify-topic <section>` must pass before a topic is logged as done.
- Where to flip the verifier model if they want a different one (add a `model:` line
  to `.opencode/agent/verifier.md`).

Do not start studying in the same breath unless the user asks — init and study are
separate sessions by design (the study session should start clean under the generated
AGENTS.md).
