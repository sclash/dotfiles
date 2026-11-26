# fx configuration

Personal configuration for [fx](https://fx.sh), the terminal coding agent from
Vercel Labs. It lives in this directory and is deployed by Home Manager as an
out-of-store link into `~/.fx`.

Current version: **fx 0.0.18**, carried by an overlay in
`nixos/flake.nix` because nixpkgs is still on 0.0.16.

## Files

| Path | What it is |
|---|---|
| `settings.json` | Providers, models, and fx settings. The live file. |
| `mcp.overrides.json` | Per-server patches on top of the MCP servers defined in `nixos/programs/mcpservers.nix`. |
| `AGENTS.md` | Personal instructions for fx. Empty means "no extra instructions". |
| `agents/` | Agent profiles, each in its own directory with `profile.json` and optional `prompt.md`. |
| `themes/` | Custom fx themes, `<name>.json`. |

The module that deploys all of this is `nixos/programs/fx-sh.nix`, imported by
`nixos/home.nix`.

## How it is deployed

Home Manager creates:

```text
~/.config/fx/settings.json          -> ~/dotfiles/fx/settings.json
~/.config/fx/mcp.overrides.json     -> ~/dotfiles/fx/mcp.overrides.json
~/.fx/agents                        -> ~/dotfiles/fx/agents
~/.fx/themes                        -> ~/dotfiles/fx/themes
~/.fx/AGENTS.md                     -> ~/dotfiles/fx/AGENTS.md
```

The `fx` command is a wrapper installed by `home.packages`. It shadows the
system `fx-sh` package (`~/.nix-profile/bin` comes before
`/run/current-system/sw/bin`). At every launch it:

1. copies `~/.config/fx/settings.json` into a real `~/.fx/settings.json`
   (mode 600), because fx refuses symlinked settings;
2. generates `~/.fx/mcp.json` from `nixos/programs/mcpservers.nix`, merges
   `mcp.overrides.json`, and expands `envFrom` secrets;
3. gives OpenCode Go a session id in `FX_OPENCODE_SESSION`;
4. runs the real fx binary.

When fx exits, if it changed `~/.fx/settings.json` (for example via `/model` or
`fx provider`), the wrapper writes it back through the repo symlink.

### Setup on a new machine

1. These files are already in the repository.
2. `nixos/home.nix` imports `./programs/mcpservers.nix` and
   `./programs/fx-sh.nix`.
3. `nixos/configuration.nix` may still install the system `fx-sh`; the
   Home Manager wrapper shadows it on `PATH`.
4. Rebuild.
5. Start an interactive zsh (so the secret exports run) and launch `fx`.

Apply changes to the Nix module with the usual rebuild:

```bash
update
```

## Providers

Two custom OpenAI-compatible connections are configured:

| Connection | Endpoint | Key | Default model |
|---|---|---|---|
| `opencode-go` | `https://opencode.ai/inference/go/openai/v1` | `OPENCODE_API_KEY` | `deepseek-v4.1-flash` |
| `openrouter` | `https://openrouter.ai/api/v1` | `OPENROUTER_API_KEY` | `deepseek/deepseek-v4.1-flash-1017` |

`opencode-go` is the selected provider.

Both connections pin `reviewer_model` and `title_model` to the flash model, so
`auto` mode's safety reviews and session titles do not spend the selected
model's tokens.

### Switch provider

```bash
fx provider opencode-go
fx provider openrouter
```

The choice is saved in `~/.fx/settings.json`; the wrapper writes it back to
`fx/settings.json`, so `git diff` shows it. Commit it if it should be the new
default.

For one run without changing the saved default:

```bash
FX_PROVIDER=opencode-go fx
```

`/provider` inside fx only lists the **built-in** providers (Vercel AI Gateway,
Codex, Grok). Custom connections are not in that picker. There is no
mid-session switch: start a new fx process with `FX_PROVIDER`, or run
`fx provider` and start a new session. A saved session stays on the connection
it started on.

### Models

`fx/settings.json` keeps one saved model per connection under `models`.
`/model` only lists models of the current connection.

`model_metadata` gives fx the context window and output limit it needs for
automatic compaction. Keep it in sync with the real limits when changing model
IDs.

### Reasoning effort

Both models declare `low`, `medium`, and `high` under `reasoning_efforts`. Use
`/effort` inside fx or Ctrl+T to cycle through them. The saved effort is
`auto` by default, which sends no effort field; the choice is stored as a
personal preference, not in this repository.

### OpenCode Go session header

OpenCode Go rejects coding-agent requests without `x-opencode-session`. The
`opencode-go` connection declares:

```json
"headers": {
  "x-opencode-session": { "env": "FX_OPENCODE_SESSION" }
}
```

The wrapper sets a fresh UUID per launch. If you run the real binary directly
(`/run/current-system/sw/bin/fx` or the store path), you must set the variable
yourself.

## API keys

`nixos/programs/zsh.nix` exports the keys from `/run/secrets/` when an
interactive zsh starts:

```text
OPENROUTER_API_KEY
OPENCODE_API_KEY
GITHUB_PERSONAL_ACCESS_TOKEN / GH_TOKEN
HF_TOKEN
GROQ_API_KEY
```

Run fx from an interactive zsh shell so the wrapper inherits these exports.
The provider connections read their keys from the variables named in
`auth.env`. A stdio MCP server only receives the allow-listed variables plus
its own `env`, so MCP secrets go through `envFrom` (see below).

The names are declared in `nixos/secrets/template.yaml`; fill the values with
`sops edit ~/.config/sops/secrets.yaml`. See `SOPS-README.md` for the full
workflow.

Check:

```bash
test -n "$OPENCODE_API_KEY" && echo set
```

## Permissions and review

fx runs in `permission_mode: "auto"`. In that mode it sends certain actions
(unrecognised shell commands, writes outside the workspace, sensitive config
changes, MCP tool use) to the connection's `reviewer_model`. That reviewer
checks for prompt injection and harm to the machine; it is not a general code
review. Rules that already allow or deny an action skip the reviewer.

`settings.json` mirrors the intent of the OpenCode policy:

- `read`, `edit`, `glob`, and `grep` deny `.env` and
  `.env.local`/`.env.production`/`.env.development`, `.secrets*`, `secrets*`,
  `credentials*`, `id_rsa*`, `*.pem`, `*.key`, `*.p12`, and `/run/secrets*`.
- `mcp_select_tool` is `ask`, so opening an MCP server or tool through
  `toolbox` asks first.

Inspect it with:

```bash
fx permissions --json
```

To switch to explicit approval for every action, use `/permissions ask`, or set
`"permission_mode": "ask"` in `settings.json`. `full-access` disables checks
entirely, including the deny rules.

## MCP servers

The definitions come from `nixos/programs/mcpservers.nix`, the same
`programs.mcp.servers` option used by OpenCode and Claude. Every server there
is `disabled = true`, so fx starts with all of them off.

The wrapper converts the neutral shape to fx's `mcp.json`:

| Neutral | fx |
|---|---|
| `command` + `args` | `type = "stdio"`, `command = [ command ] ++ args` |
| `url` | `type = "http"`, `url` |
| `disabled = true` | `enabled = false` |
| `env` | `env` |

`headers` and `envFiles` are not mapped. Add HTTP headers for a specific server
through the override if it needs them.

### Enable a server

Edit `mcp.overrides.json` and relaunch fx:

```json
{
  "mcpServers": {
    "github": {
      "enabled": true,
      "envFrom": ["GITHUB_PERSONAL_ACCESS_TOKEN"]
    }
  }
}
```

The wrapper merges this over the generated base at launch and writes a real
`~/.fx/mcp.json`. No rebuild is needed because the override file is linked from
the repo. Overrides for a server that is not in `mcpservers.nix` are ignored.

For a temporary change inside a running session, edit `~/.fx/mcp.json` directly
and send a prompt or run `/mcp`; fx reloads MCP config then. The next launch
regenerates the file from the base plus the override, so this does not persist.

`/mcp` itself has no enable action — the menu only offers Log in, Log out,
Approve, Reject, and Remove. `/mcp add` and `/mcp remove` write the generated
file and are lost on the next launch; change `mcpservers.nix` instead.

### Secrets for MCP servers

A stdio MCP server receives only `HOME`, `LOGNAME`, `PATH`, `SHELL`, `TERM`,
`USER` from fx, plus its own `env`. Use `envFrom` to name login variables:

```json
"github": {
  "enabled": true,
  "envFrom": ["GITHUB_PERSONAL_ACCESS_TOKEN"]
}
```

The wrapper copies the value from its environment into the server's `env` in
`~/.fx/mcp.json` (mode 600) and removes `envFrom` before fx reads it. The value
never enters git. If the variable is unset or empty, nothing is added and the
server sees its normal "not set" error.

### Add or change a server

1. Edit `nixos/programs/mcpservers.nix`.
2. Rebuild.
3. Optionally enable it in `mcp.overrides.json`.

It is then available to OpenCode, Claude, and fx from one definition.

## Skills, agents, themes, instructions

**Skills.** fx discovers the OpenCode skills through
`~/.config/opencode/skills`, which is an out-of-store link into
`~/dotfiles/my-opencode/v2/skills`. Do not put links under `~/.fx/skills`: fx
never follows symlinks in that managed directory. Use another discovery root
(for example `~/.agents/skills`) if you need fx-only skills.

**Agents.** Put profiles in `fx/agents/<name>/`:

```text
fx/agents/reviewer/profile.json
fx/agents/reviewer/prompt.md
```

The whole `agents` directory is linked. A profile directory itself must be a
real directory; fx only lists entries whose kind is `directory`.

**Themes.** Put `<name>.json` in `fx/themes/` and set `"theme": "<name>"` in
`settings.json`. The directory is linked; individual theme files are opened
without following symlinks, so keep them real files.

**Instructions.** `~/.fx/AGENTS.md` is linked to `fx/AGENTS.md`. It may point
only to a file inside `$HOME`. An empty file is ignored.

## Verify and debug

```bash
# which provider and model is active
fx status --json | jq '{model, model_source, provider_endpoint, auth}'

# where a setting comes from
fx config get provider --show-origin
fx config list --show-origin | grep -E '^(file|env):'

# the real deployed paths
readlink -f ~/.config/fx/settings.json
readlink -f ~/.config/fx/mcp.overrides.json
ls -l ~/.fx

# permission mode and configured rules
fx permissions --json | jq '{mode, rules: (.rules|length)}'

# MCP state and errors
fx mcp list --json | jq '.servers[] | {name, status, error}'
fx mcp show github --json | jq '{status, error, version, tools: (.tools|length)}'

# settings the wrapper generated
jq '{github_enabled: .mcpServers.github.enabled,
     token_set: (.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN != null)}' ~/.fx/mcp.json
```

Nix checks:

```bash
nix flake check ./nixos --no-write-lock-file
```

## Troubleshooting

**fx keeps retrying an MCP server.** Read the error:

```bash
fx mcp show <name> --json | jq '{status, error}'
```

The usual causes are a missing secret (`GITHUB_PERSONAL_ACCESS_TOKEN not set`),
a command that is not on `PATH`, or a server that takes longer than
`startup_timeout_ms` (30 seconds by default; add `"startup_timeout_ms": 120000`
to its override).

**The MCP server has no token.** Add the variable to `envFrom` in
`mcp.overrides.json` and rebuild if the wrapper itself is stale. Verify the
wrapper contains the merge logic:

```bash
grep -c envFrom "$(readlink -f "$(command -v fx)")"
```

**Changes to `settings.json` do not apply.** The wrapper syncs at launch, not
while a session is open. Restart fx. If fx wrote settings after your edit, its
version is newer; edit again or use `fx config set`.

**`/exit/exit` was sent as a prompt.** Slash commands are one per line.
`/exit` is an alias of `/quit`, but `/exit/exit` is not a command, so it went to
the model.

**A tool calls the real binary, not the wrapper.** Anything invoking
`/run/current-system/sw/bin/fx` or a store path bypasses the sync: no settings
refresh, no MCP generation, no `FX_OPENCODE_SESSION`. Use `fx` from `PATH`.

**fx reformats the repo files.** fx serializes `settings.json` itself after a
change, often minifying it, and the wrapper writes that back. This is expected;
the content, not the formatting, is the contract.
