# fx configuration: design notes

This document explains why the fx setup looks the way it does: what fx allows,
what it refuses, and how `nixos/programs/fx-sh.nix` plus this directory work
around those limits without weakening the normal Nix and secrets rules.

For day-to-day commands, see `README.md`.

## Goals

1. Keep fx configuration in this repository, reviewable in git.
2. Change configuration without rebuilding when fx allows it.
3. Define MCP servers once, in `nixos/programs/mcpservers.nix`, and share them
   with OpenCode and Claude.
4. Never put a credential value in git, in the Nix store, or in an error
   message.
5. Stay machine-agnostic: no `/home/<user>`, no fixed username, no hostname.
6. Use a real wrapper only where fx leaves no alternative.

## fx version

`nixos/flake.nix` overrides `pkgs-master.fx-sh` to 0.0.18 while nixpkgs still
ships 0.0.16. The OpenCode Go connection needs the custom-connection fields that
0.0.17 introduced (`headers` and the related connection options), so the overlay
stays until nixpkgs carries a version with the same schema. The system package
and the Home Manager wrapper both use the overlaid package.

## Constraints in fx

These were read from fx 0.0.18. They drive every decision below.

| Area | fx behaviour | Consequence |
|---|---|---|
| `~/.fx` directory | opened with `follow_symlinks = false` | `~/.fx` must be a real directory |
| `~/.fx/settings.json` | opened `O_NOFOLLOW`; hard links rejected; mode must be 600 | a symlink at this path cannot work |
| Settings writes | temp file + durable rename over `settings.json` | replacing the path would destroy a symlink |
| `~/.fx/mcp.json` reads | `openExistingReadOnlyRegularFile(..., .follow)` | a symlink is readable |
| `~/.fx/mcp.json` writes | `durableReplaceVerified`; project variant rejects links and hard links | fx cannot write a linked `mcp.json` |
| stdio MCP environment | only `HOME`, `LOGNAME`, `PATH`, `SHELL`, `TERM`, `USER`, then the server's `env` | secrets must be named per server |
| `~/.fx/agents` | root directory is opened with symlink following; entries must be directories | link the root, not an individual profile directory |
| `~/.fx/themes` | directory is followed; each theme file is opened `O_NOFOLLOW` | link the directory, keep theme files real |
| `~/.fx/AGENTS.md` | a link is allowed when it resolves inside `$HOME` | no store symlink for this file |
| `~/.fx/skills` | symlinks are never followed in the managed root | do not put linked skills there |
| Other skill roots | a linked skill is allowed when it resolves inside home/workspace or a configured authority | use `~/.config/opencode/skills` or another root |
| `/provider` picker | built-in catalog only (`vercel`, `codex`, `grok`) | custom connections are selected outside the picker |
| `auto` mode review | a custom connection uses its `reviewer_model`, or the selected model | pin a cheap reviewer so safety checks stay cheap |
| Reasoning effort | fx offers and sends only the levels declared in `model_metadata.reasoning_efforts` | declare levels per model, or `/effort` has nothing to choose |
| Session binding | a session stays on the connection it started on | switching connections needs a new process |
| Settings reload | settings are read at startup; MCP config reloads at the next prompt | restart fx for settings, not for MCP toggles |

The two hard limits are settings symlinks and the managed skills directory.
Everything else can be a normal out-of-store link.

## Architecture

```text
~/dotfiles/fx/settings.json
    │  home.file out-of-store link
    ▼
~/.config/fx/settings.json
    │  wrapper: install -m 600 (content comparison)
    ▼
~/.fx/settings.json  (real, 600)  ──fx──▶ providers

~/dotfiles/fx/mcp.overrides.json
    │  home.file out-of-store link
    ▼
~/.config/fx/mcp.overrides.json
    │
    │  wrapper: jq merge + envFrom expansion
    ▼
~/.fx/mcp.json  (real, 600)  ──fx──▶ MCP servers
    ▲
    │  pkgs.formats.json
nixos/programs/mcpservers.nix -> fx-mcp-base.json (store)

~/dotfiles/fx/{agents,themes,AGENTS.md}
    │  home.file out-of-store links
    ▼
~/.fx/{agents,themes,AGENTS.md}  ──fx──▶ profiles, themes, instructions
```

`fx` on `PATH` is the wrapper from `home.packages`; it shadows the system
`fx-sh` in `configuration.nix`.

## Path ownership

| Runtime path | Type | Source of truth |
|---|---|---|
| `~/.fx` | real directory | fx, chmod 700 |
| `~/.fx/settings.json` | real file, 600 | `fx/settings.json` via wrapper |
| `~/.fx/mcp.json` | real file, 600 | generated base + `fx/mcp.overrides.json` |
| `~/.fx/agents` | symlink | `fx/agents` |
| `~/.fx/themes` | symlink | `fx/themes` |
| `~/.fx/AGENTS.md` | symlink | `fx/AGENTS.md` |
| `~/.config/fx/settings.json` | symlink | `fx/settings.json` |
| `~/.config/fx/mcp.overrides.json` | symlink | `fx/mcp.overrides.json` |

`~/.fx/sessions`, `backups`, `logs`, `recordings`, `diagnostics`, `hosts`,
`mcp-credentials` and `history.jsonl` are fx runtime state and are intentionally
not in the repository.

## Settings: materialize, then write back

A direct link at `~/.fx/settings.json` is impossible. fx's settings store opens
the directory and the file with no-follow flags, rejects hard links, and commits
with a temporary file plus rename. A link is either rejected or replaced by the
first write.

The wrapper therefore implements a small two-way sync:

1. If `~/.config/fx/settings.json` exists, make `~/.fx` and copy it to
   `~/.fx/settings.json` when:
   - the destination is a symlink or has more than one link,
   - it is missing,
   - or its content differs from the source.

   `install -m 600` creates the real file with the mode fx requires.
2. Snapshot the materialized file.
3. Run the real fx binary.
4. If fx changed the file during the run, and the source is still the
   Home Manager symlink, write the new content back with `cat "$dst" > "$src"`.

The write-back deliberately uses shell redirection: it truncates the target
through the symlink and preserves the link. `install`, `cp` or `mv` could unlink
and replace the source, turning the deployed link into a regular file.

Content comparison, not mtime, decides the initial copy. That removes the
"same second" and "fx wrote after your edit" edge cases of an mtime check while
still copying only when needed.

Known race: if the repository file is edited while fx is running and fx then
writes settings, the write-back wins. Settings are read at startup, so restart
fx after editing the repository file.

## MCP: generate once, patch at launch

fx can read a linked `mcp.json`, but cannot write one. A direct link from
`~/dotfiles/fx/mcp.json` would work for reads and would reload live, but it
would duplicate the server definitions already present in
`mcpservers.nix`. The chosen design keeps one definition:

1. At evaluation time, `fx-sh.nix` converts
   `config.programs.mcp.servers` to fx's shape and writes a store file
   (`fx-mcp-base.json`).
2. At every launch, the wrapper merges the tracked override file over that base
   and writes a real `~/.fx/mcp.json` (600).
3. fx reads the real file and reloads it at the next prompt when it changes.

The conversion is intentionally small:

| Neutral option | fx field |
|---|---|
| `command` + `args` | `type = "stdio"`, `command = [ command ] ++ args` |
| `url` | `type = "http"`, `url` |
| `enabled = true/false` | `enabled`; if null, `!disabled` |
| `env` | `env` |

`headers` and `envFiles` have no safe generic mapping here and are omitted. If a
server needs custom HTTP headers, add them through the override in fx's
`{ "env": "VAR" }` form; `envFiles` has no fx equivalent.

`disabled = true` in `mcpservers.nix` becomes `enabled: false`. This is the same
semantic OpenCode uses, so every client starts with the same servers off.

### Override format and merge

`fx/mcp.overrides.json` is a partial `mcp.json`:

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

The wrapper merges each entry field-by-field over the generated base. An entry
for a server that is not in the base is ignored. It then expands `envFrom`: for
each named variable, if the wrapper's environment has a non-empty value, that
value is added to the server's `env`; an unset or empty variable is skipped.
Finally `envFrom` is deleted, because it is not an fx field.

This is how a login-only secret reaches a stdio MCP server without being stored
in git. The expanded value exists only in `~/.fx/mcp.json`, which is mode 600
and regenerated at each launch.

`/mcp add` and `/mcp remove` write `~/.fx/mcp.json`, but the next launch
regenerates the file. Add or remove servers in `mcpservers.nix` instead.

`/mcp` has no enable/disable action in 0.0.18. Enabling a server is editing the
override (persistent) or editing `~/.fx/mcp.json` (one session, until the next
launch). fx reloads the file at the next prompt.

## Linked configuration

These are plain Home Manager out-of-store links because fx follows them:

- `agents`: the root is opened with normal symlink following. The individual
  profile directories must be real directories; a symlinked profile directory
  is skipped. Home profiles may link their `profile.json` and `prompt.md`
  anywhere.
- `themes`: the directory is followed, but each `<name>.json` is opened with
  `O_NOFOLLOW`. Link the directory, keep the files real.
- `AGENTS.md`: fx allows a link to a file elsewhere in `$HOME`. A store link
  would be outside home, so this must remain an out-of-store link into the
  repository.

Skills are the exception. `~/.fx/skills` is fx's managed install directory and
never follows symlinks. The OpenCode skills root
(`~/.config/opencode/skills`) is already a link into this repository and is
inside `$HOME`, so fx discovers those skills without any extra work. For
fx-only skills, add another discovery root such as `~/.agents/skills` pointing
at a repository directory; the link must resolve inside `$HOME` or be listed in
`skill_symlink_authorities`.

## Providers and OpenCode Go

`settings.json` defines custom connections, not built-ins. fx's `/provider`
picker is built from `provider_catalog.entries` (vercel, codex, grok) and
`.configured` has no sign-in methods, so custom connections never appear there.
Selection is therefore:

- `fx provider <name>` (persisted in settings, written back to the repo), or
- `FX_PROVIDER=<name>` (one process).

There is no mid-session switch. A saved session is bound to its connection.

OpenCode Go is stricter than a normal OpenAI-compatible endpoint: its
coding-agent requests require a stable `x-opencode-session` header. fx does not
send one. The connection declares:

```json
"headers": {
  "x-opencode-session": { "env": "FX_OPENCODE_SESSION" }
}
```

and the wrapper exports a fresh UUID per launch. The header is read at request
time from the environment, never stored in settings.

`model_metadata` supplies context and output limits; without a context window
fx cannot compute automatic compaction. Keep the values aligned with the
upstream model limits when changing model IDs.

## Permissions and the reviewer

fx's `permission` rules and OpenCode's `permissions` array express the same
intent in different shapes, so the configuration mirrors the intent rather than
copying the array. fx uses one object per tool, wildcard patterns, and
`mcp_select_tool` for MCP access; OpenCode uses a list of action/resource
records and `mcp_*`.

The chosen policy keeps `permission_mode: "auto"` and adds:

- `read`, `edit`, `glob`, and `grep` deny the same secret-file patterns as the
  OpenCode config, including `/run/secrets` and `/run/secrets.d`;
- `mcp_select_tool: "ask"`, so exposing an MCP server or tool through `toolbox`
  asks first.

`auto` mode is not "ask before anything dangerous." It sends only uncertain
actions to the reviewer, and the reviewer answers one question: does this action
show prompt injection or harm to the machine? Deleting code or tests, pushing
branches, and running a script the agent wrote are not held by that review. The
rules above are the part that enforces the secrets policy, and rules skip the
reviewer entirely.

Model choice for the reviewer is a cost decision. A custom connection defaults
its reviewer to the selected model, so a session on an expensive model would
also use it for every safety review. Both connections pin `reviewer_model` to
the flash model used for coding. `title_model` is pinned the same way; it names
sessions from the first prompt.

Reasoning effort is declared per model as `reasoning_efforts` with the request
fragment the endpoint expects. Both current endpoints accept
`reasoning_effort: low|medium|high`; this was verified directly against the
OpenAI-compatible APIs before adding the levels. With no level selected
(`effort: auto`), fx sends no effort field. `/effort` and Ctrl+T only offer
levels a model declares.

## Secrets

The repository contains credential **names** only:

- `/run/secrets/*` values are exported by `nixos/programs/zsh.nix`, guarded by
  `[ -f ... ]` per secret.
- `settings.json` references provider keys by environment variable
  (`auth.env`).
- `mcp.overrides.json` lists MCP variables in `envFrom`.
- The wrapper expands `envFrom` into the local `~/.fx/mcp.json` (600) and never
  prints it.
- The generated Nix base contains no secret; a token in `mcpservers.nix env`
  would end up in the store, so tokens belong in the login environment.

## Alternatives considered

| Alternative | Why it was not chosen |
|---|---|
| Link `~/.fx/settings.json` directly | fx rejects symlinks and hard links; rename would replace the link |
| Set `FX_HOME=~/dotfiles/fx` | live, but sessions, backups, logs and credentials land in the repo |
| Copy settings only at activation | every settings change needs a rebuild; no write-back |
| Patch fx to follow and replace through symlinks | fork of security-critical path handling; fx releases every few weeks |
| Link `fx/mcp.json` directly | works and reloads live, but duplicates every server already in `mcpservers.nix` |
| Link `~/.fx/mcp.json` to the generated store file | one source, but enabling a server needs a rebuild |
| Put MCP tokens in the Nix option | secret value would enter the store and git |
| Copy the OpenCode permissions array literally | the schemas differ (records vs per-tool objects, `mcp_*` vs `mcp_select_tool`); the intent is mirrored instead |
| Pass the whole environment to MCP servers | fx intentionally limits it; would leak provider keys to every server |
| `makeWrapper` instead of a script | no post-run hook, so settings could not be written back |

## Failure modes

- **Direct binary invocation.** `/run/current-system/sw/bin/fx` and store paths
  bypass the wrapper: no settings sync, no MCP generation, no session header.
  Use `fx` from `PATH`.
- **Wrapper not rebuilt.** The installed wrapper is a store path. After changing
  `fx-sh.nix`, rebuild before testing; `grep envFrom "$(readlink -f "$(command -v fx)")"`
  tells you whether the current wrapper has the merge logic.
- **Missing login environment.** Launch fx from a shell where the secret
  variables are exported. A GUI or a stripped environment has no keys.
- **Settings race.** A repository edit and an in-app settings write can collide;
  the last writer wins.
- **MCP reload boundaries.** Settings load at startup; MCP config loads at the
  next prompt. In-session edits to `~/.fx/mcp.json` are temporary.
- **fx serializer.** fx rewrites `settings.json` in its own formatting (often
  minified), and the wrapper writes it back. Commit content, not formatting.
- **Skills.** A link under `~/.fx/skills` is silently ignored. Use a non-managed
  discovery root.

## Verification

The following were used while building this setup:

- `nix flake check ./nixos --no-write-lock-file`
- a fake `$HOME` exercising the wrapper: missing destination, hard-linked
  destination, symlinked destination, unchanged content, changed content, and
  MCP base/override merge;
- `jq` round-trip of the neutral MCP shape: all 12 servers present, all
  `enabled: false`;
- an override enabling `playwright`/`openrouter` and the merge result;
- direct requests to OpenCode Go: `400 MissingSessionID` without the header,
  `200` with it;
- direct requests with `reasoning_effort: low` to both endpoints: `200`;
- `fx permissions --json` parsed the secret patterns over `read`, `edit`,
  `glob`, and `grep`, plus `mcp_select_tool: ask`;
- `fx ask --effort high` returned a reply through the declared level;
- `fx mcp show github --json` with the token in the server's `env`: status
  `ready` with the full tool list.

## Maintenance

**Add or change a provider or model.** Edit `fx/settings.json`. Add
`model_metadata` with context/output limits and `reasoning_efforts`, and update
`reviewer_model`/`title_model` if the cheap model changes. `fx provider` and
`/model` write back to the same file.

**Change the secret policy.** Update the `permission` patterns, then check the
parsed rules with `fx permissions --json`. The rule shapes and wildcard
semantics are fx's, not OpenCode's.

**Add or change an MCP server.** Edit `nixos/programs/mcpservers.nix`
(`command`/`args` or `url`, `env`, `disabled`). Rebuild. Enable it in the
override if it should be on by default. If it needs a login secret, add its
variable to `envFrom`.

**Upgrade fx.** The overlay in `nixos/flake.nix` pins the version and source
hash. After an upgrade, check that the schema still accepts:
`settings.providers.*.headers`, `model_metadata`, MCP `enabled`, and MCP
`env`. Also re-check the settings no-follow behaviour; if upstream ever accepts
symlinks, this whole wrapper can be simplified.

**Remove the workaround.** If fx later supports a symlinked `settings.json` or
a read-write external config path, replace the materialization with a plain
`mkOutOfStoreSymlink`. If it supports enabling MCP servers from `/mcp` while
keeping the file linked, the override merge can go too.

## Future upstream improvements

- Let `/provider` list configured connections and switch without restarting.
- Accept a symlinked `settings.json` read-only, or a separate `FX_SETTINGS`
  path, so settings can be a normal dotfile link.
- Add an enable/disable action to `/mcp` that persists in a writable state
  file, so `enabled: false` entries can be toggled like OpenCode.
