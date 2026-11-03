---
name: diagnostics-fallback
description: Use when you need compiler errors, type checking, or lint diagnostics in a project. OpenCode V2 has no LSP runtime, so this skill supplies working per-language check commands and rules for reporting missing tools instead of guessing.
---

# Diagnostics Fallback (no LSP in OpenCode V2)

OpenCode V2 (through 2.2.1) validates and preserves the `lsp` config block but
never starts a language server, exposes LSP tools, or returns diagnostics.
The agent gets no editor-layer feedback. Use real build, typecheck, and lint
commands instead.

## Rules

1. Prefer project-defined commands first: `package.json` scripts, `Makefile`,
   `justfile`, `flake.nix` checks, CI config, or the project's `AGENTS.md`.
2. Run the narrowest command that covers the files you touched, then the full
   project check before claiming work is complete.
3. Never invent, summarize, or assume diagnostics you did not run. Quote the
   failing output and the command that produced it.
4. If a tool is missing, say so explicitly and propose `nix run nixpkgs#<pkg>`,
   `uvx <tool>`, `bunx <tool>`, or adding it to the project. Ask for permission
   before running any of these or making a persistent installation; never
   install globally.
5. Do not add or rely on `lsp` entries expecting them to work. That block is
   inert until upstream `anomalyco/opencode#38528` lands.

## Commands by language

| Language | Files | Check |
| --- | --- | --- |
| Nix | `.nix` | `nix flake check` (full, slow); `nix eval --raw .#<attr>`; `nix build .#<attr>` |
| TypeScript / JS | `.ts .tsx .js .jsx` | `tsc --noEmit` (or `npm run typecheck`); `npx tsc --noEmit` fallback |
| Vue | `.vue` | `vue-tsc --noEmit` (missing locally; use project dep or `npx vue-tsc --noEmit`) |
| Rust | `.rs` | `cargo check`; `cargo build` |
| Python | `.py .pyi` | `pyright <path>`; `python -m compileall -q <path>`; `black --check <files>` |
| Go | `.go` | `go vet ./...`; `go build ./...`; `gopls check <files>` |
| C / C++ | `.c .h .cc .cpp .hpp` | `clang-tidy <files> -- <include flags>`; or the project's build system |
| Lua | `.lua` | `luac -p <file>`; `lua-language-server --check=<dir>` |
| Bash / sh / zsh | `.sh .bash .zsh` | `bash -n <file>` (zsh: `zsh -n <file>`) |
| Zig | `.zig .zon` | `zig build`; `zig fmt --check <files>` |
| QML | `.qml` | `qmllint -I /etc/profiles/per-user/asergi/lib/qt-6/qml <file>` |
| Markdown | `.md` | `npx markdownlint-cli2 <files>` (not installed) |
| Docker | `Dockerfile` | `docker build ...`; `hadolint` (not installed) |
| LaTeX | `.tex .bib` | project recipe (`latexmk` not installed) |
| Nushell | `.nu` | `nu --ide-check 100 <file>` |
| Mojo | `.mojo` | `uv run --with "max[all]" mojo build <file>` |

## Tools present on this machine

`tsc`, `pyright`, `prettier`, `black`, `gopls`, `rust-analyzer`, `cargo`,
`rustc`, `clang-tidy`, `qmllint`, `luac`, `zig`, `go`, `nix`, `node`, `npm`,
`npx`, `bun`, `uv`, `uvx`, `nu`, `texlab`.

## Tools missing (do not assume they work)

`eslint`, `biome`, `vue-tsc`, `ruff`, `shellcheck`, `stylua`, `luacheck`,
`markdownlint`, `hadolint`, `chktex`, `latexmk`, `rustfmt`, `cargo clippy`,
`nixfmt`, `mojo`.

## Notes

- `cargo fmt` and `cargo clippy` are unavailable (`rustfmt` / `clippy-driver`
  are not in the toolchain). Use `cargo check` and report the gap.
- `nix flake check` can be slow and may build derivations. Prefer evaluating
  the specific attribute when the failure is local.
- For Tailwind, HTML, JSON, Astro, and other purely editor-side servers, there
  is no CLI equivalent; rely on the project's build or `prettier --check`.
