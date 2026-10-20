# Ripwire

Reach for it BEFORE blind grep + whole-file reads. First call ~1s cold; after that warm, ~0.1s.
- Orient on a task: `ripwire <dir> --for="<task in words>"` — ranked, quality-annotated
  signatures. Paste symbol/file names from the issue verbatim; named mentions get anchored.
- One task: `--pack-task="<task>" --legend=compact`; before parallel agents: `--plan-lanes=N --task="<goal>"`, then read `lanes[].execution`.
- Have a stack trace / build error: `ripwire <dir> --from-trace=FILE --legend=compact` (`-` = stdin) —
  paste the error, don't paraphrase it into a query.
- Who calls X: `--callers=SYM --legend=compact`. "Is it safe to change X?" needs the full blast radius:
  `--impact=SYM --legend=compact` (transitive) plus `--uses=SYM --legend=compact` (every read/write/import site).
- Apply a whole-symbol edit without a whole-file Read: `--replace-symbol-body=SYM` plus `--edit-payload=FILE|-`
  (or insert-before/after); the receipt carries region, blob_sha, edit_check, tests_to_run + ONE next= — no re-read after it; `--edit-check=SYM --legend=compact` is for a contract question WITHOUT an edit in hand.
- Before writing a new fn/class/helper: `--exemplar="<what you're writing>" --legend=compact` — duplicates are born on small tasks.
- Before calling work done: `--quality-delta --legend=compact` (what you made worse), then `--test-gate --legend=compact`.
- Trust notes: counts marked counts_floor are floors, not totals; a zero means "none found", never "none exists".
- The commands above ask for the compact legend (terse definitions of only the attributes present); add `--legend=full` when a definition's reasoning is needed: a term you do not recognise, a floor or cap you need explained, a map a human will read.
Defaults to break (less context is measurably MORE accurate, not just cheaper — code-repair
accuracy fell 29% -> 3% as context grew 32K -> 256K tokens, LongCodeBench):
- Do NOT open a file you have not located first: rank with `--for`/`--grep`, then read what it names.
- Do NOT read a whole file to understand one symbol: `--expand=SYM --legend=compact` gives the body + callee sigs.
- Do NOT fan reads across several files to learn one thing: `--pack-task="<task>" --legend=compact` is one call.
