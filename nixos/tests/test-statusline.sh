#!/usr/bin/env bash
# Tests for nixos/programs/claude-code/statusline.sh: feeds sample Claude Code
# status JSON and checks the rendered lines (ANSI colours stripped).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/nixos/programs/claude-code/statusline.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n     got: %q\n' "$1" "$2"; fail=1; }

run() { bash "$SCRIPT" <<<"$1" | sed $'s/\e\\[[0-9;]*m//g'; }

expect_line() { # name, output, line number, exact expected text
  local got
  got=$(sed -n "${3}p" <<<"$2")
  [[ $got == "$4" ]] && pass "$1" || bad "$1" "$got"
}

# A throwaway repo on branch feat-x, plus a linked worktree "wt1".
repo="$TMP/myproj"
git init -q -b feat-x "$repo"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$repo" worktree add -q -b wt-branch "$TMP/wt1"

# 1. Full payload: every segment, repo name from JSON.
out=$(run '{
  "workspace": {"current_dir": "'"$repo"'", "repo": {"name": "dotfiles"}},
  "context_window": {"used_percentage": 31.4},
  "rate_limits": {"five_hour": {"used_percentage": 23.5},
                  "seven_day": {"used_percentage": 41.2}},
  "cost": {"total_duration_ms": 4320000, "total_cost_usd": 0.8412}
}')
expect_line "full: line 1" "$out" 1 "dotfiles  feat-x"
expect_line "full: line 2" "$out" 2 "ctx ▓▓▓░░░░░░░ 31%  5h 23%  7d 41%  ⏱ 1h12m  \$0.84"

# 2. Minimal payload: repo from git, no line 2, no "null" anywhere.
out=$(run '{"workspace": {"current_dir": "'"$repo"'"}}')
expect_line "minimal: line 1" "$out" 1 "myproj  feat-x"
[[ $(wc -l <<<"$out") -eq 1 ]] && pass "minimal: single line" || bad "minimal: single line" "$out"

# 3. Nulls early in a session are dropped, not printed.
out=$(run '{"workspace": {"current_dir": "'"$repo"'"},
  "context_window": {"used_percentage": null}, "cost": {"total_duration_ms": 42000}}')
expect_line "nulls: line 2" "$out" 2 "⏱ 42s"
[[ $out != *null* ]] && pass "nulls: no literal null" || bad "nulls: no literal null" "$out"

# 4. Linked worktree: main repo name, worktree branch, worktree marker.
out=$(run '{"workspace": {"current_dir": "'"$TMP/wt1"'", "git_worktree": "wt1"}}')
expect_line "worktree: line 1" "$out" 1 "myproj  wt-branch  ⎇ wt1"

# 5. Gateway spend limit with dollar amounts.
out=$(run '{"workspace": {"current_dir": "'"$repo"'"},
  "rate_limits": {"spend_limit": {"used_percentage": 25, "used_usd": 12.5, "limit_usd": 50}}}')
expect_line "spend: line 2" "$out" 2 "spend \$12.50/\$50.00"

# 6. Garbage input still renders and exits 0.
if out=$(cd "$repo" && bash "$SCRIPT" <<<"not json" | sed $'s/\e\\[[0-9;]*m//g'); then
  expect_line "garbage: falls back to \$PWD" "$out" 1 "myproj  feat-x"
else
  bad "garbage: exit 0" "$out"
fi

# 7. Context over 100% clamps the bar.
out=$(run '{"workspace": {"current_dir": "'"$repo"'"}, "context_window": {"used_percentage": 140}}')
expect_line "clamp: line 2" "$out" 2 "ctx ▓▓▓▓▓▓▓▓▓▓ 140%"

exit "$fail"
