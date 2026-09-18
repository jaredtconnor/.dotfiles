# Migration Manifest

> Historical record of the completed dotbot-to-chezmoi migration (May 2026). Paths and decisions below may no longer match the repo; see README.md for the current layout.

Exhaustive map of every dotbot entry → chezmoi target. Use this to run `chezmoi add` (or straight `cp`) at migration time.

Legend:
- **T** — needs a template (`.tmpl` suffix)
- **OS** — OS-gated via `.chezmoiignore`
- **X** — executable (use `executable_` prefix)
- **P** — private / 0600 (use `private_` prefix)
- **verbatim** — copy as-is

## Editor

**Decisions applied:** VS Code = single canonical target (macOS), no OS bifurcation, no Cursor mirror. Karabiner dropped from migration scope.

| Dotbot source | Chezmoi target | Notes |
|---|---|---|
| `editor/nvim/` | `home/dot_config/nvim/` | verbatim; Windows placement handled by `run_onchange_windows-paths.sh.tmpl` (copies to `AppData/Local/nvim`) |
| `editor/lazyvim/` | `home/dot_config/LazyVim/` | verbatim |
| `editor/vscode/settings.json` | `home/Library/Application Support/Code/User/settings.json` | verbatim; **OS** macOS-only via `Library/` ignore |
| `editor/vscode/keybindings.json` | `home/Library/Application Support/Code/User/keybindings.json` | verbatim |
| `editor/vscode/snippets/` | `home/Library/Application Support/Code/User/snippets/` | verbatim |
| `editor/vscode/extensions.txt` | — | not a config; ignore or track separately as reference |
| `editor/cursor/` | — | **dropped per decision** |
| `editor/zed/keymap.json` | `home/dot_config/zed/keymap.json` | verbatim |
| `editor/zed/settings.json` | `home/dot_config/zed/settings.json` | verbatim |
| `editor/lunarvim/` | — | drop; already gated off in `.chezmoiignore` |

## Shell

| Dotbot source | Chezmoi target | Notes |
|---|---|---|
| `shell/zsh/.zshrc` | `home/dot_zshrc` | drafted (path-rewritten) |
| `shell/zsh/.zprofile` | `home/dot_zprofile` | drafted |
| `shell/zsh/.zshenv` | `home/dot_zshenv` | drafted |
| `shell/zsh/mise.zsh` | `home/dot_config/zsh/mise.zsh` | verbatim |
| `shell/zsh/fzf-theme-dark-plus.sh` | `home/dot_config/zsh/fzf-theme-dark-plus.sh` | verbatim |
| `shell/zsh/fzf-theme.sh` | `home/dot_config/zsh/fzf-theme.sh` | verbatim |
| `shell/zsh/z_add_all_dev_dirs.sh` | `home/dot_local/bin/executable_z-add-all-dev-dirs` | **X** |
| `shell/bash/.bashrc` | `home/dot_bashrc` | verbatim |
| `shell/bash/.bash_profile` | `home/dot_bash_profile` | verbatim |
| `shell/aliases/*.aliases.sh` | `home/dot_config/zsh/aliases/*` | verbatim (6 files) |
| `shell/paths/*.path.sh` | `home/dot_config/zsh/paths/*` | verbatim (6 files) |
| `shell/functions/*.sh` (source-able) | `home/dot_config/zsh/functions/*` | `cdf.sh`, `code.override.sh`, `git.functions.sh`, `icon-cache-check.sh`, `latest_dl.sh`, `latest_payload.sh`, `nvims.sh`, `fssh.sh` |
| `shell/functions/*.sh` (executable) | `home/dot_local/bin/executable_*` | `cws.sh`, `fcom.sh`, `fdd.sh`, `fjq.sh`, `fyr.sh`, `fzl.sh`, `npmjs.sh` — **X** |
| `shell/fish/*` | `home/dot_config/fish/*` | verbatim (3 files) |
| `shell/powershell/user_profile.ps1` | `home/dot_config/powershell/user_profile.ps1` | **OS** Windows-only |
| `shell/powershell/jconnor.omp.json` | `home/dot_config/powershell/jconnor.omp.json` | **OS** Windows-only |
| `shell/starship.toml` | `home/dot_config/starship.toml` | verbatim |
| `shell/scripts/dev-setup.sh` | `home/dot_local/bin/executable_dev-setup` | **X** |
| `shell/scripts/clear-icon-cache.sh` | `home/dot_local/bin/executable_clear-icon-cache` | **X** |
| `shell/scripts/share-ssh-keys.sh` | `home/dot_local/bin/executable_share-ssh-keys` | **X** (gitignored currently; confirm public-safe) |
| `shell/scripts/github-ssh-setup.sh` | `home/dot_local/bin/executable_github-ssh-setup` | **X** |

## Terminal

| Dotbot source | Chezmoi target | Notes |
|---|---|---|
| `terminal/alacritty/*` | `home/dot_config/alacritty/*` | verbatim |
| `terminal/wezterm/*` | `home/dot_config/wezterm/*` | verbatim |
| `terminal/kitty/*` | `home/dot_config/kitty/*` | verbatim |
| `terminal/ghostty/*` | `home/dot_config/ghostty/*` | Unix only; Windows uses `~/AppData/Roaming/ghostty/config` (split target or post-apply copy) |

## Tools — cross-platform

| Dotbot source | Chezmoi target | Notes |
|---|---|---|
| `tools/tmux/.tmux.conf` | `home/dot_tmux.conf` | verbatim |
| `tools/sesh/sesh.toml` | `home/dot_config/sesh/sesh.toml` | verbatim |
| `tools/gitmux/.gitmux.conf` | `home/dot_gitmux.conf` | verbatim |
| `tools/git/.gitconfig` | `home/dot_config/git/config.tmpl` | **T** — drafted |
| `tools/git/.gitconfig-personal` | — | dropped (identity in config.tmpl) |
| `tools/git/.gitconfig-work` | — | dropped (identity in config.tmpl) |
| `tools/git/gitconfig_shared` | `home/dot_config/git/config.tmpl` | merge content into the single config.tmpl |
| `tools/git/gitignore_global` | `home/dot_config/git/ignore` | verbatim |
| `tools/git/githooks/commit-msg` | `home/dot_config/git/githooks/executable_commit-msg` | **X** |
| `tools/git/githooks/pre-commit` | `home/dot_config/git/githooks/executable_pre-commit` | **X** |
| `tools/git/git_template/` | `home/dot_config/git/template/` | verbatim |
| `tools/mise/config.toml` | `home/dot_config/mise/config.toml` | verbatim |
| `tools/zoxide/zoxide-env.zsh` | `home/dot_config/zsh/zoxide-env.zsh` | verbatim |
| `languages/node/prettierrc.js` | `home/dot_prettierrc.js` | verbatim |

## Tools — macOS-only (OS-gated via .chezmoiignore)

| Dotbot source | Chezmoi target |
|---|---|
| `tools/hammerspoon/` | `home/dot_hammerspoon/` |
| `tools/karabiner/` | — **dropped per decision**; manage manually outside chezmoi |
| `tools/sketchybar/*` | `home/dot_config/sketchybar/*` |
| `tools/aerospace/aerospace.toml` | `home/dot_config/aerospace/aerospace.toml` |
| `tools/espanso/` | `home/Library/Application Support/espanso/` |
| `tools/iina/YouTube.conf` | `home/Library/Application Support/com.colliderli.iina/input_conf/YouTube.conf` |
| `tools/raycast/scripts/` | `home/dot_config/raycast/scripts/` |

## AI tooling (Option 2 split)

| Dotbot source | Chezmoi target | Notes |
|---|---|---|
| `tools/ai/claude/settings.json` | `home/dot_claude/settings.json` | Main repo. See `home/dot_claude/README.md`. |
| `tools/ai/commands/*` | `home/dot_claude/commands/*` | Main repo. |
| `tools/ai/hooks/*` | `home/dot_claude/hooks/executable_*` | Main repo. **X** |
| `tools/ai/ccstatusline/settings.json` | `home/dot_config/ccstatusline/settings.json` | Main repo. |
| `tools/ai/cursor/rules/*.mdc` | `home/dot_cursor/rules/*.mdc` | Main repo. |
| `tools/ai/skills/*` | → `agent-tooling.git:skills/*` | Canonical reusable tooling repo. Flat-linked by `run_after_symlink-ai-mirror.sh`. |
| `tools/ai/agents/*` | → `agent-tooling.git:agents/*` | Same. |
| `tools/ai/.pre-commit-config.yaml`, `pyproject.toml`, `uv.lock`, `scripts/`, `tests/`, `docs/` | → `agent-tooling.git:` top level | Keep inside the agent tooling repo; they're tooling for that repo. |

## SSH

| Dotbot source | Chezmoi target | Notes |
|---|---|---|
| `~/.ssh/config` (live, ~83 lines homelab) | `home/private_dot_ssh/config.tmpl` | **T**, **P** — drafted. GitHub aliases + `UseKeychain` templated; homelab block pasted in verbatim at migration time. |
| `ssh/config.example` | — | drop |
| `shell/scripts/share-ssh-keys.sh` | — | **dropped**; use chezmoi secrets for key material |
| SSH private keys | managed via chezmoi secrets (age or 1Password) | separate follow-up — not in scope for this migration |

## Env / secrets

| Dotbot source | Chezmoi target | Notes |
|---|---|---|
| `env/.secrets` | `home/.chezmoiscripts/run_after_create-env-from-1password.sh.tmpl` | **T**, **P** creates `~/.env` once from 1Password, then leaves it unmanaged |
| `env/.secrets.ps1` | `home/dot_config/powershell/secrets.ps1.tmpl` | **T** Windows-only; plaintext today, 1Password later |

## Install / build scripts

| Dotbot source | Chezmoi target | Notes |
|---|---|---|
| `install-osx.sh`, `install-linux.sh`, `justfile` | — at repo root | `justfile` worth keeping; others retire |
| `machines/osx/Brewfile`, `setup-homebrew.sh` | `home/.chezmoiscripts/run_once_before_install-brewfile.sh.tmpl` wrapping `brew bundle` | New one-shot installer on darwin |
| `machines/fedora/fedora_setup.sh` | `home/.chezmoiscripts/run_once_before_fedora-setup.sh.tmpl` | Linux-only one-shot |
| `tools/mise/setup-mise.sh` | `home/.chezmoiscripts/run_once_after_mise-setup.sh` | One-shot; runs after toml is in place |
| `tools/tmux/setup-tmux.sh` | drop (tmux plugins come via chezmoi-external now) | — |
| `tools/git/set-gitconfig.sh` | drop (identity in config.tmpl) | — |
| `shell/scripts/github-ssh-setup.sh` | `home/dot_local/bin/executable_github-ssh-setup` | **X**; invoke manually, not at apply |

## Submodules → chezmoi externals

Already mapped in `home/.chezmoiexternal.toml.tmpl`:

| Dotbot submodule | Chezmoi external path |
|---|---|
| `shell/zsh/oh-my-zsh` | `.oh-my-zsh` |
| `shell/zsh/zgenom` | `.zgenom` |
| `tmux-plugins/tmux-sensible` | `.tmux/plugins/tmux-sensible` |
| `tmux-plugins/tmux-resurrect` | `.tmux/plugins/tmux-resurrect` |
| `tmux-plugins/tmux-continuum` | `.tmux/plugins/tmux-continuum` |
| `tmux-plugins/tmux-fzf-url` | `.tmux/plugins/tmux-fzf-url` |
| `tmux-plugins/vim-tmux-navigator` | `.tmux/plugins/vim-tmux-navigator` |
| `dotbot`, `dotbot-plugins/dotbot-asdf` | — retired |
| `tools/ai` (= skills.git) | → rename to `agent-tooling.git`; external pulls it |

## Counts

- ~75 symlink entries in `install.conf.yaml`.
- 10 git submodules.
- ~63 skills + ~5 agents currently in `tools/ai/`.
- ~25 commands, ~10 hooks under `tools/ai/commands/` and `tools/ai/hooks/`.
- 6 alias files, 6 path files, 16 function files.

## Acceptance tracking

- [x] Shell rc files drafted (`dot_zshrc`, `dot_zprofile`, `dot_zshenv`)
- [x] AI relocation scaffolding (dot_claude/, dot_cursor/, dot_config/ccstatusline/) with README
- [x] `.chezmoiignore` broadened for editor/terminal/macOS gates
- [x] Comprehensive manifest for copy-over at migration time
- [x] Editor scaffolding + READMEs (VS Code macOS-only, Cursor dropped, Karabiner dropped)
- [x] SSH config template drafted (GitHub aliases + `UseKeychain` templated, homelab block pasted)
- [x] Windows path handling via `run_onchange_windows-paths.sh.tmpl` (nvim + Ghostty)
- [x] Git config.tmpl — merged aliases from all 3 sources, added gitconfig_shared settings, VS Code difftool/mergetool
- [x] Shell aliases copied (6 files)
- [x] Shell paths copied (6 files)
- [x] Shell functions split: 8 source-able -> dot_config/zsh/functions/, 7 executable -> dot_local/bin/
- [x] Zsh extras copied (fzf themes, mise.zsh, zoxide-env.zsh)
- [x] Shell scripts copied to dot_local/bin/ (dev-setup, clear-icon-cache, github-ssh-setup)
- [x] Bash, Fish, PowerShell, Starship, Prettier copied
- [x] Editor configs copied: nvim (59 files), LazyVim (57 files), VS Code (3 files), Zed (2 files)
- [x] Terminal configs copied: Alacritty (3), Wezterm (4), Kitty (4), Ghostty (1)
- [x] Cross-platform tools copied: tmux, sesh, gitmux, mise, git ignore/hooks/template
- [x] macOS tools copied: Hammerspoon (2), Sketchybar (27), Aerospace (1), Espanso (3), IINA (1), Raycast (5)
- [x] AI tooling copied: claude/settings.json, commands (27), hooks (9), ccstatusline, cursor rules (54)
- [x] `run_once_before_install-brewfile.sh.tmpl` (Homebrew bundle wrapper) + Brewfile
- [x] `run_once_after_mise-setup.sh` (mise install runner)
- [x] SSH key material secrets strategy — human keys in 1Password, unattended service keys on source hosts
- [x] 1Password `op` reads for `~/.env` — guarded create-once script instead of managed template
- [ ] `agent-tooling.git` repo creation + rename on Forgejo
- [ ] `skills-work.git` repo creation
- [ ] Dry-run: `chezmoi init --apply=false` against throwaway destination
- [ ] Full apply on personal Mac with dotbot still in place
