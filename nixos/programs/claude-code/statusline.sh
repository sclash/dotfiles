# claude-statusline: Claude Code's two-line status bar.
#
#   dotfiles  quickshell  ⎇ native-vpn
#   ctx ▓▓▓░░░░░░░ 31%  5h 23%  7d 41%  ⏱ 1h12m  $0.84
#
# Input is the status JSON Claude Code writes to stdin
# (https://code.claude.com/docs/en/statusline). Every segment is optional:
# missing data drops that segment, never the whole bar, and the script always
# exits 0 so a bad payload can't blank the line.
#
# Money is the session's *estimated* cost at list price (cost.total_cost_usd).
# Claude Code does not expose the extra-usage credit balance; spend_limit is
# shown only when an org gateway provides it.
#
# Packaged by claude-code.nix with writeShellApplication (adds jq/git to PATH
# and shellchecks at build time).

set -euo pipefail
export LC_ALL=C # printf %f must parse "0.84" regardless of locale

readonly RESET=$'\e[0m' BOLD=$'\e[1m' DIM=$'\e[2m'
readonly GREEN=$'\e[32m' YELLOW=$'\e[33m' RED=$'\e[31m' CYAN=$'\e[36m' MAGENTA=$'\e[35m'
readonly BAR_WIDTH=10

# Print the ANSI colour for a usage percentage (integer, may exceed 100).
# Used for the context bar and the 5h/7d/spend limits.
# 80% is where context starts to degrade answers and where a 5h/7d window is
# close enough to plan around; over 100 (spend limits can exceed it) shouts.
pct_color() {
  local pct=$1
  if ((pct >= 100)); then printf '%s' "$BOLD$RED"
  elif ((pct >= 80)); then printf '%s' "$RED"
  elif ((pct >= 50)); then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"
  fi
}

# "1h12m", "7m", "42s" from milliseconds.
fmt_duration() {
  local s=$(($1 / 1000))
  if ((s >= 3600)); then
    printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
  elif ((s >= 60)); then
    printf '%dm' $((s / 60))
  else
    printf '%ds' "$s"
  fi
}

# "23" from "23.5"; jq numbers may be floats.
int() { printf '%s' "${1%%.*}"; }

# Coloured "label NN%" segment.
pct_segment() {
  local label=$1 pct
  pct=$(int "$2")
  printf '%s%s %s%%%s' "$(pct_color "$pct")" "$label" "$pct" "$RESET"
}

context_bar() {
  local pct filled
  pct=$(int "$1")
  filled=$((pct * BAR_WIDTH / 100))
  ((filled > BAR_WIDTH)) && filled=$BAR_WIDTH
  ((filled < 0)) && filled=0
  local bar="" i
  for ((i = 0; i < BAR_WIDTH; i++)); do
    if ((i < filled)); then bar+="▓"; else bar+="░"; fi
  done
  printf '%sctx%s %s%s %s%%%s' "$DIM" "$RESET" "$(pct_color "$pct")" "$bar" "$pct" "$RESET"
}

input=$(cat)

# One jq pass. Fields are joined with \x1f (not tabs): with a whitespace IFS,
# `read` would collapse empty fields and shift every value after them.
cwd="" repo="" worktree="" wt_branch="" ctx="" five="" seven=""
dur_ms="" cost="" spend_pct="" spend_used="" spend_limit=""
IFS=$'\x1f' read -r cwd repo worktree wt_branch ctx five seven \
  dur_ms cost spend_pct spend_used spend_limit < <(
    jq -r '[
      (.workspace.current_dir // .cwd),
      .workspace.repo.name,
      (.workspace.git_worktree // .worktree.name),
      .worktree.branch,
      .context_window.used_percentage,
      .rate_limits.five_hour.used_percentage,
      .rate_limits.seven_day.used_percentage,
      .cost.total_duration_ms,
      .cost.total_cost_usd,
      .rate_limits.spend_limit.used_percentage,
      .rate_limits.spend_limit.used_usd,
      .rate_limits.spend_limit.limit_usd
    ] | map(. // "" | tostring) | join("\u001f")' <<<"$input" 2>/dev/null
  ) || true

[[ -d $cwd ]] || cwd=$PWD

# --- line 1: repo · branch · worktree --------------------------------------
git_() { git --no-optional-locks -C "$cwd" "$@" 2>/dev/null; }

branch=$wt_branch
[[ -n $branch ]] || branch=$(git_ branch --show-current || true)
[[ -n $branch ]] || branch=$(git_ rev-parse --short HEAD || true) # detached

if [[ -z $repo ]]; then
  # --git-common-dir points at the main repo's .git even from a linked
  # worktree, so a worktree still shows the repo's name, not its own dir.
  common=$(git_ rev-parse --path-format=absolute --git-common-dir || true)
  if [[ -n $common ]]; then
    repo=$(basename "$(dirname "$common")")
  else
    repo=$(basename "$cwd")
  fi
fi

line1="${BOLD}${CYAN}${repo}${RESET}"
[[ -n $branch ]] && line1+="  ${MAGENTA}${branch}${RESET}"
[[ -n $worktree ]] && line1+="  ${YELLOW}⎇ ${worktree}${RESET}"

# --- line 2: context · limits · time · money -------------------------------
segs=()
[[ -n $ctx ]] && segs+=("$(context_bar "$ctx")")
[[ -n $five ]] && segs+=("$(pct_segment 5h "$five")")
[[ -n $seven ]] && segs+=("$(pct_segment 7d "$seven")")
if [[ -n $spend_used && -n $spend_limit ]]; then
  segs+=("$(printf '%sspend $%.2f/$%.2f%s' "$(pct_color "$(int "${spend_pct:-0}")")" \
    "$spend_used" "$spend_limit" "$RESET")")
elif [[ -n $spend_pct ]]; then
  segs+=("$(pct_segment spend "$spend_pct")")
fi
[[ -n $dur_ms ]] && segs+=("⏱ $(fmt_duration "$(int "$dur_ms")")")
[[ -n $cost ]] && segs+=("$(printf '%s$%.2f%s' "$GREEN" "$cost" "$RESET")")

printf '%s\n' "$line1"
if ((${#segs[@]})); then
  line2=${segs[0]}
  for s in "${segs[@]:1}"; do line2+="  $s"; done
  printf '%s\n' "$line2"
fi
exit 0
