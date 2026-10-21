---
name: strategic-compact
description: Suggests manual context compaction at logical intervals to preserve context through task phases rather than arbitrary auto-compaction.
metadata:
  origin: ECC
---

# Strategic Compact Skill

Suggests a manual `/compact` at strategic points in your workflow rather than relying on arbitrary auto-compaction.

## When to Activate

- Running long sessions that approach context limits
- Working on multi-phase tasks (research → plan → implement → test)
- Switching between unrelated tasks within the same session
- After completing a major milestone and starting new work
- When responses slow down or become less coherent (context pressure)

## Why Strategic Compaction?

Auto-compaction triggers at arbitrary points:
- Often mid-task, losing important context
- No awareness of logical task boundaries
- Can interrupt complex multi-step operations

Strategic compaction at logical boundaries:
- **After exploration, before execution** — Compact research context, keep implementation plan
- **After completing a milestone** — Fresh start for next phase
- **Before major context shifts** — Clear exploration context before different task

## How It Works

The `strategic-compact` opencode plugin does this. It lives in `~/.config/opencode/plugins/strategic-compact.js` and is deployed from `my-opencode/plugins/` in the dotfiles repo, so it loads automatically — there is nothing to install and no hook config to edit.

1. **Counts tool calls per session** via the `tool.execute.before` hook
2. **Detects the threshold** and queues a suggestion once the count passes it
3. **Reminds periodically** every `interval` calls after that, so the suggestion stays visible across a long stretch of work
4. **Delivers the nudge** through `experimental.chat.system.transform`, so it reaches you as part of the system prompt rather than as noise in a tool result
5. **Resets the counter** when compaction runs, since the context pressure that triggered the suggestion is gone

This replaces an earlier version of this skill that ran as a Claude Code `PreToolUse` hook configured in `~/.claude/settings.json`. opencode has no equivalent declarative hook configuration, so the logic lives in a plugin instead. If you previously followed that skill's setup instructions, you can remove them — nothing reads that file.

## Configuration

Environment variables, read when the plugin loads:

- `STRATEGIC_COMPACT=off` — disable the plugin entirely
- `STRATEGIC_COMPACT_THRESHOLD=N` — tool calls before the first suggestion (default: 50)
- `STRATEGIC_COMPACT_INTERVAL=N` — calls between reminders after the threshold (default: 25)

## Compaction Decision Guide

Use this table to decide when to compact:

| Phase Transition | Compact? | Why |
|-----------------|----------|-----|
| Research → Planning | Yes | Research context is bulky; plan is the distilled output |
| Planning → Implementation | Yes | Plan is in the todo list or a file; free up context for code |
| Implementation → Testing | Maybe | Keep if tests reference recent code; compact if switching focus |
| Debugging → Next feature | Yes | Debug traces pollute context for unrelated work |
| Mid-implementation | No | Losing variable names, file paths, and partial state is costly |
| After a failed approach | Yes | Clear the dead-end reasoning before trying a new approach |

## What Survives Compaction

Understanding what persists helps you compact with confidence:

| Persists | Lost |
|----------|------|
| `AGENTS.md` / `CLAUDE.md` instructions | Intermediate reasoning and analysis |
| Todo list (`todowrite`) | File contents you previously read |
| Files on disk | Multi-step conversation context |
| Git state (commits, branches) | Nuanced user preferences stated verbally |
| Loaded skills | Tool call history and counts |

## Best Practices

1. **Compact after planning** — Once the plan is finalized, compact to start fresh
2. **Compact after debugging** — Clear error-resolution context before continuing
3. **Don't compact mid-implementation** — Preserve context for related changes
4. **Read the suggestion** — The plugin tells you *when*, you decide *if*
5. **Write before compacting** — Save important context to files before compacting
6. **Use `/compact` with a summary** — Add a custom message: `/compact Focus on implementing auth middleware next`

## Token Optimization Patterns

### Trigger-Table Lazy Loading
Instead of loading full skill content at session start, use a trigger table that maps keywords to skill paths. Skills load only when triggered, reducing baseline context by 50%+:

| Trigger | Skill | Load When |
|---------|-------|-----------|
| "test", "tdd", "coverage" | tdd-workflow | User mentions testing |
| "security", "auth", "xss" | security-review | Security-related work |
| "deploy", "ci/cd" | deployment-patterns | Deployment context |
### Context Composition Awareness
Monitor what's consuming your context window:
- **`AGENTS.md` / `CLAUDE.md` files** — Always loaded, keep lean
- **Loaded skills** — Each skill adds 1-5K tokens
- **Conversation history** — Grows with each exchange
- **Tool results** — File reads, search results add bulk

### Duplicate Instruction Detection
Common sources of duplicate context:

- Skills that repeat `AGENTS.md` instructions
- Multiple skills covering overlapping domains

### Context Optimization Tools
- `context-mode` MCP — Context virtualization, configured in `~/.config/opencode/opencode.json` (currently disabled; enable it to use)

## Related

- [The Longform Guide](https://x.com/affaanmustafa/status/2014040193557471352) — Token optimization section
- `verification-loop` skill — run a full quality pass after compacting
