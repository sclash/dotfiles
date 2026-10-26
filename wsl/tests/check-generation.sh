#!/usr/bin/env bash
# Assertions on a built home-manager generation (the activation package).
# Usage: check-generation.sh GEN HOMEDIR
# Runs inside the flake check sandbox: only store paths are readable, so
# out-of-store links are checked by their target path, never resolved.
set -uo pipefail

GEN=${1:?usage: check-generation.sh GEN HOMEDIR}
HOMEDIR=${2:?usage: check-generation.sh GEN HOMEDIR}
failures=0
count=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

check() {
  count=$((count + 1))
  "$@"
}

has_bin() {
  for b in "$@"; do
    check test -e "$GEN/home-path/bin/$b" || fail "has_bin $b"
  done
}

lacks_bin() {
  for b in "$@"; do
    check test ! -e "$GEN/home-path/bin/$b" || fail "lacks_bin $b"
  done
}

has_path() {
  check test -e "$GEN/$1" || fail "has_path $1"
}

lacks_path() {
  check test ! -e "$GEN/$1" -a ! -L "$GEN/$1" || fail "lacks_path $1"
}

is_dir() {
  local p="$GEN/home-files/$1"
  check test -d "$p" -a ! -L "$p" || fail "is_dir $1"
}

# Follow the symlink chain while it stays inside /nix/store; the first
# target outside the store is where the out-of-store link points.
links_to() {
  local rel=$1 want=$2 p="$GEN/home-files/$1" hops=0
  count=$((count + 1))
  while [[ -L "$p" && $hops -lt 10 ]]; do
    p=$(readlink "$p")
    [[ "$p" == /nix/store/* ]] || break
    hops=$((hops + 1))
  done
  [[ "$p" == "$want" ]] || fail "links_to $rel $want (got $p)"
}

contains() {
  check grep -qF -- "$2" "$GEN/$1" || fail "contains $1 $2"
}

lacks() {
  count=$((count + 1))
  if grep -qF -- "$2" "$GEN/$1"; then fail "lacks $1 $2"; fi
}

run_contains() {
  local want=$1 bin=$2
  shift 2
  check grep -qF -- "$want" <("$GEN/home-path/bin/$bin" "$@" 2>&1) || fail "run_contains $want $bin $*"
}

# --- Task 1: base
has_bin home-manager
V=home-path/etc/profile.d/hm-session-vars.sh
contains $V 'export EDITOR="nvim"'
contains $V 'export VISUAL="nvim"'
contains $V 'export SUDO_EDITOR="nvim"'
contains $V '.local/bin'
lacks $V '.opencode/bin'
contains $V 'LANG="en_US.UTF-8"'
contains $V 'XDG_DATA_DIRS'
lacks $V 'LD_LIBRARY_PATH'
contains home-files/.config/git/config 'name = "sclash"'

# --- Task 2: program modules + links
has_bin tmux starship atuin nu uv devenv pandoc xelatex ripwire herdr \
  vtsls pyright clangd gopls zls lua-language-server texlab rust-analyzer \
  codelldb debugpy-adapter prettier black dlv
run_contains 0.6.8 ripwire --version
contains home-files/.config/tmux/tmux.conf sessionx
contains home-files/.config/tmux/tmux.conf continuum-restore
links_to .config/nvim "$HOMEDIR/dotfiles/neovimrc"
links_to .config/starship "$HOMEDIR/dotfiles/starship"
links_to .config/atuin "$HOMEDIR/dotfiles/atuin"
links_to .config/uv/uv.toml "$HOMEDIR/dotfiles/wsl/uv/uv.toml"
is_dir .config/herdr
links_to .config/herdr/config.toml "$HOMEDIR/dotfiles/herdr/config.toml"
# Build limits for the 3.6 GiB WSL VM: one derivation at a time, two compile
# threads. nix.package only validates nix.conf; it must not shadow Determinate's nix.
contains home-files/.config/nix/nix.conf 'max-jobs = 1'
contains home-files/.config/nix/nix.conf 'cores = 2'
lacks_bin nix

# --- Task 3: packages
has_bin nvim vim tree-sitter nixd nix-prefetch-git sops age age-keygen tree bat eza fd jq zoxide zip unzip wget wl-copy \
  gh lazygit lazydocker lazysql lazyssh lazycli btop htop ncdu fastfetch glow hygg \
  ffmpeg timg chafa flamegraph.pl hyperfine gcc clang lldb gdb valgrind bear make pkg-config lua \
  node npm tsc chromium orx rg fzf ctags python3 bun go rustc cargo zig agent-browser
count=$((count + 1))
[[ "$(readlink -f "$GEN/home-path/bin/cc")" == *gcc-wrapper* ]] || fail "cc resolves to gcc ($(readlink -f "$GEN/home-path/bin/cc"))"
lacks_bin firefox google-chrome ghostty docker perf rr ldd
has_path home-files/.config/fontconfig/conf.d/10-hm-fonts.conf
count=$((count + 1))
[[ -n "$(find -L "$GEN/home-path/share/fonts" -name 'NotoSans.ttf' -print -quit 2>/dev/null)" ]] || fail "noto sans font"
count=$((count + 1))
[[ -n "$(find -L "$GEN/home-path/share/fonts" -iname 'NotoColorEmoji*' -print -quit 2>/dev/null)" ]] || fail "noto emoji font"

# --- Task 4: secrets + zsh
U=home-files/.config/systemd/user/sops-nix.service
has_path $U
# The unit runs a script that passes the manifest JSON to sops-install-secrets.
M=$(grep -hoE '/nix/store/[^ "]*manifest[^ "]*\.json' "$GEN/$U" $(grep -oE '/nix/store/[^ "]+' "$GEN/$U" 2>/dev/null) 2>/dev/null | head -1)
count=$((count + 1))
[[ "$(jq -r '.secrets[].name' "$M" 2>/dev/null | sort | xargs)" == "cheaper_inference github_pat opencode openrouter" ]] || fail "sops secret names (manifest: ${M:-not found})"
count=$((count + 1))
[[ -n "$M" && -z "$(jq -r '.secrets[].path' "$M" | grep -vF -- "$HOMEDIR/.config/sops-nix/secrets/")" ]] || fail "sops secret paths"
Z=home-files/.zshrc
contains $Z 'bash ~/dotfiles/wsl/update.sh'
contains $Z "$HOMEDIR/dotfiles/scripts/tmux-sessionizer.sh"
contains $Z 'show_eza_tree'
# Secrets may not be decrypted yet (first login, missing key): guard every read.
contains $Z "if [ -f $HOMEDIR/.config/sops-nix/secrets/github_pat ]"
contains $Z "if [ -f $HOMEDIR/.config/sops-nix/secrets/openrouter ]"
contains $Z 'GITHUB_PERSONAL_ACCESS_TOKEN'
contains $Z 'OPENROUTER_API'
contains $Z 'starship init zsh'
contains $Z 'atuin init zsh'
lacks $Z '/run/secrets'
lacks $Z 'nixos-rebuild'

# --- Task 8: opencode + claude-code (v2 base + wsl/opencode overlay)
B=$HOMEDIR/dotfiles/my-opencode/v2
O=$HOMEDIR/dotfiles/wsl/opencode
C=.config/opencode
links_to $C/opencode.jsonc $O/opencode.jsonc
links_to $C/CLAUDE.md $O/CLAUDE.md
for i in AGENTS.md RIPWIRE.md agents commands instructions prompts scripts tools; do links_to $C/$i $B/$i; done
is_dir $C/plugins
links_to $C/plugins/herdr-agent-state.js $B/plugins/herdr-agent-state.js
links_to $C/plugins/strategic-compact.js $B/plugins/strategic-compact.js
lacks_path home-files/$C/plugins/nix-ld-env.js
is_dir $C/skills
links_to $C/skills/explore-codebase $B/skills/explore-codebase
links_to $C/skills/pptx/SKILL.md $O/skills/pptx/SKILL.md
links_to $C/skills/pptx/editing.md $O/skills/pptx/editing.md
links_to $C/skills/agent-browser/SKILL.md $O/skills/agent-browser/SKILL.md
links_to $C/skills/webapp-testing/examples/console_logging.py $O/skills/webapp-testing/examples/console_logging.py
links_to $C/skills/webapp-testing/scripts $B/skills/webapp-testing/scripts
for i in evals package-lock.json vastai; do lacks_path home-files/$C/$i; done
links_to .agents "$HOMEDIR/dotfiles/.agents"
contains home-path/etc/profile.d/hm-session-vars.sh 'OPENCODE_DISABLE_CLAUDE_CODE_SKILLS="true"'
for s in explore-codebase high-perf-systems download-video; do links_to .claude/skills/$s $B/skills/$s; done
links_to .claude/skills/transcribe-media/SKILL.md $O/skills/transcribe-media/SKILL.md
lacks_path home-files/.claude/settings.json
has_bin claude opencode
lacks_path home-files/.config/mcp/mcp.json # mcpservers.nix is not imported

if [[ $failures -gt 0 ]]; then
  echo "$failures of $count assertions failed"
  exit 1
fi
echo "OK ($count assertions)"
