// Suggests a manual /compact at logical task boundaries instead of waiting for
// arbitrary auto-compaction.
//
// This is the opencode port of the strategic-compact skill, which originally ran
// as a Claude Code PreToolUse hook over the Edit and Write tools. opencode has no
// equivalent declarative hook config, so the counter and the nudge are implemented
// here instead.
//
// Behaviour:
//   - counts every tool call per session
//   - once the count passes the threshold, suggests /compact
//   - repeats the suggestion every `interval` calls after that, so it stays
//     visible across a long stretch of work
//
// Tuning via environment variables:
//   STRATEGIC_COMPACT=off          disable entirely
//   STRATEGIC_COMPACT_THRESHOLD=N   calls before the first suggestion (default 50)
//   STRATEGIC_COMPACT_INTERVAL=N    calls between reminders (default 25)

const DEFAULT_THRESHOLD = 50;
const DEFAULT_INTERVAL = 25;

function readNumber(name, fallback) {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

const enabled = (process.env.STRATEGIC_COMPACT ?? "").toLowerCase() !== "off";
const threshold = readNumber("STRATEGIC_COMPACT_THRESHOLD", DEFAULT_THRESHOLD);
const interval = readNumber("STRATEGIC_COMPACT_INTERVAL", DEFAULT_INTERVAL);

const callCounts = new Map();
const pendingNudge = new Set();

export default async () => {
  if (!enabled) return {};

  return {
    // Called before every tool invocation.
    "tool.execute.before": async (input) => {
      const count = (callCounts.get(input.sessionID) ?? 0) + 1;
      callCounts.set(input.sessionID, count);

      if (count === threshold) {
        pendingNudge.add(input.sessionID);
      } else if (count > threshold && (count - threshold) % interval === 0) {
        pendingNudge.add(input.sessionID);
      }
    },

    // Fires once per assistant turn. This is where the nudge is surfaced, so it
    // arrives at the model as part of the system prompt rather than as noise in
    // a tool result.
    "experimental.chat.system.transform": async (input, output) => {
      const sessionID = input.sessionID;
      if (!sessionID) return;
      if (!pendingNudge.has(sessionID)) return;

      // One nudge per crossing -- drop the flag so it does not repeat every turn.
      pendingNudge.delete(sessionID);

      const count = callCounts.get(sessionID) ?? 0;
      output.system.push(
        [
          "<system-reminder>",
          `This session has made ${count} tool calls. If you are at a logical task`,
          "boundary -- just finished a phase, just finished exploring before you",
          "start implementing, or about to switch to an unrelated task -- consider",
          "running /compact with a short summary of where things stand (for example",
          "`/compact auth middleware is next, tests still failing`). Compacting now",
          "keeps the summary you need and drops the file contents you no longer do.",
          "If you are mid-flow, ignore this and keep going.",
          "</system-reminder>",
        ].join(" "),
      );
    },

    // Context was just compacted, so the pressure that triggered the suggestion is
    // gone. Reset rather than carry the old count forward.
    "experimental.session.compacting": async (input) => {
      callCounts.delete(input.sessionID);
      pendingNudge.delete(input.sessionID);
    },
  };
};