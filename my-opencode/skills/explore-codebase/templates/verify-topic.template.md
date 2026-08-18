---
description: >-
  Verify a completed study topic before it is logged: dispatch the adversarial
  verifier subagent against an artifact section and its example files, then gate the
  session-log entry on the findings.
---

Verify the artifact section named in `$ARGUMENTS` (if empty, ask which section — or
infer the section currently being worked on from the conversation and confirm).

1. **Gather the inputs.** Locate in `study/understanding-{{name}}.md`:
   - the target Layer 1 section (and/or Layer 2 concept sections it introduced),
   - every example/counter-example file those sections reference under
     `study/examples/` and `study/counter/`.

2. **Dispatch the verifier.** Spawn the `verifier` subagent (defined in
   `.opencode/agent/verifier.md`) with the Task tool (`subagent_type: verifier`),
   passing:
   - the section text (or its exact location),
   - the list of referenced example/counter-example files,
   - the studied source files the section cites.
   The verifier runs its four audits (claim audit, empirical probes, anti-cheating,
   reference spot-check) in a fresh context — do not summarize or pre-interpret the
   section for it; anchoring it on your reading defeats its purpose.

3. **Triage the findings** with the user:
   - `[CRITICAL]` / `[HIGH]` — must be fixed now. Apply fixes (researcher decides how;
     the verifier only reports), then re-dispatch the verifier on the affected parts.
     Repeat until none remain.
   - `[LOW]` — note them; fix if trivial, otherwise record under the section's Open
     questions.

4. **Gate the log.** Only after zero outstanding `[CRITICAL]`/`[HIGH]` findings:
   report the topic as verified and include it in the session-log entry's `Verified:`
   line. If verification cannot be completed (e.g. an example won't build), the topic
   stays unverified and is logged as an open question — never silently logged as done.
