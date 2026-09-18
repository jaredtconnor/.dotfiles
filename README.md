# .dotfiles

Cross-platform dotfiles managed by [chezmoi](https://www.chezmoi.io/). This one repo configures personal workstations, homelab servers, headless agent VMs, and the work laptop. A few profile flags control what each machine gets. A private companion repo supplies identities and the host inventory.

## Quick Start

```bash
# Fresh machine (macOS/Linux). Clones the public GitHub mirror:
git clone https://github.com/jaredtconnor/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles && ./install.sh

# Windows (PowerShell as admin):
git clone https://github.com/jaredtconnor/.dotfiles.git $HOME\.dotfiles
cd $HOME\.dotfiles; .\install.ps1
```

The bootstrap script installs prerequisites (Homebrew / apt / winget) and chezmoi. It also removes leftover Dotbot symlinks from the old setup, clones this repo to `~/.dotfiles`, optionally clones the private companion, and runs `chezmoi init --apply`.

| Variable | Effect |
|---|---|
| `DOTFILES_REPO_URL` | Where to clone this repo from. Defaults to the GitHub mirror; the canonical source is the private Forgejo. |
| `DOTFILES_PRIVATE_REPO_URL` | Where to clone the private companion from (`install.sh` only). Without it, the machine gets the generic public config. See [Two repos](#two-repos). |
| `CHEZMOI_SERVER=1` | Force the server profile. |
| `CHEZMOI_WORK=1` | Force the work profile. |

`install.ps1` does not clone the companion. On Windows, clone it to `$HOME\.dotfiles-private` before running the script.

## Two Repos

| Repo | Where | Holds |
|---|---|---|
| `dotfiles` (this repo) | Canonical on private Forgejo, mirrored to GitHub | Every config, template, and script. No private values. |
| `dotfiles-private` | Private Forgejo only, never mirrored | `data.yaml` (emails, work hostname, profile host lists, Forgejo address, SSH identities and host groups), `ssh/hosts` (the push list), SSH public-key hints, Hermes config |

Templates read `~/.dotfiles-private/` when they render, using chezmoi `stat` + `include`. If the companion is missing, they fall back to generic output: `~/.ssh/config` has no host blocks, `~/.ssh/hosts` isn't created, Forgejo-hosted externals are skipped, and chezmoi asks whether this is a work machine.

There's a chicken-and-egg problem. The companion's own Forgejo URL is stored inside the companion. So on first bootstrap, you have to supply it yourself, either with `DOTFILES_PRIVATE_REPO_URL` or by cloning it manually. After that, a chezmoi external keeps it up to date.

Secrets live in neither repo. The 1Password SSH agent serves private keys, `~/.env` is created from 1Password, and headless hosts keep on-disk service keys in `~/.ssh/config.local.d/`.

## Profiles

`.chezmoi.toml.tmpl` writes `~/.config/chezmoi/chezmoi.toml` on every `chezmoi init`, which includes every `just sync`. Templates and `.chezmoiignore` branch on these flags:

| Flag | Set when | Effect |
|---|---|---|
| `server` | `CHEZMOI_SERVER` is set, or the hostname is in the companion's `server_hostnames` | Allowlist: only `~/.ssh/config`, `~/.ssh/hosts`, and `~/.config/git/`. No shell frameworks, editors, desktop apps, agent runtimes, or run scripts. The only external is the companion. |
| `work` | Never on servers. Otherwise: `CHEZMOI_WORK` is set, the hostname matches the companion's `work_hostname`, or you answer yes to the one-time prompt | Work Git identity and SSH key, plus the `~/.skills-work` overlay from the work GitHub org |
| `workstation` | The hostname is in the companion's `workstation_hostnames` | Home layout buckets (`~/Code`, `~/Notes`, `~/Data`, `~/Tools`, `~/Sandbox`, `~/Archives`), ghq/gwq repo navigation, `dev-setup` |

Some features are limited to specific hosts listed in the companion:

- `ssh.headless_hosts`: agent VMs with no 1Password. Their SSH config uses the on-disk `agent-claude` key for homelab hosts instead of the 1Password agent.
- `identity.hermes_host`: the only host that gets `~/.hermes/config.yaml`.
- `identity.helium_hosts`: the only hosts that get helium-sync (browser sync LaunchAgent).

This produces the following machine classes. Hostnames live in the companion, not here.

| Machine | Flags | Gets |
|---|---|---|
| Personal Mac workstation | `workstation` | Full macOS config, 1Password SSH agent, agent-forwarding `*-hop` aliases |
| Linux dev / agent VM | `workstation` and/or headless | Full Linux config; headless ones authenticate with on-disk service keys |
| Homelab server (Proxmox, NAS) | `server` | SSH and Git config only |
| Work laptop | `work` | Full desktop config, work identity, work AI tooling overlay |
| Windows | none | PowerShell surface, Git Bash rc files, Zed and herdr under `%APPDATA%` |

## Fleet Distribution

Changes flow one way. You edit and commit on a workstation, push to Forgejo (which mirrors to GitHub), and then each machine pulls and applies. Hosts don't update on a schedule; they only change when a sync runs.

```
workstation:  edit -> commit -> push to Forgejo
                                      |
  just sync        this machine: pull both repos, refresh externals, apply
  just sync-all    this machine, then every host in ~/.ssh/hosts over SSH
  just sync-host   one host from ~/.ssh/hosts
  work laptop      not in the push list; run `just sync` on it directly
```

### What a sync does

`scripts/sync-chezmoi.sh`, the script behind every sync recipe:

1. Runs `git pull --ff-only origin main` in `~/.dotfiles` and `~/.dotfiles-private`. A diverged checkout fails here instead of merging.
2. Runs `chezmoi init`, so profile changes made in the companion take effect.
3. Refreshes all externals without prompting, then reports which Git externals changed.
4. Applies managed files. By default it's interactive, so you can answer overwrite prompts when a local file has diverged. `--force` overwrites without asking; `sync-force`, `sync-all`, and `sync-host` all use it.

For remote hosts, the script is piped over SSH (`ssh host bash -s -- --force`). It runs on the remote host and pulls from there.

### The Push List

`just sync-all`, `just doctor-all`, and `share-ssh-keys` loop over `~/.ssh/hosts`. That file is rendered from the companion's `ssh/hosts`: one SSH alias per line, with `#` comments allowed.

- Each name must match a `Host` alias in `~/.ssh/config`.
- The current machine (per `hostname -s`) is applied locally, not over SSH.
- A host that fails a 5-second non-interactive SSH probe (because it's offline or asks for a password) is reported as skipped, not failed.
- Each target needs an existing `~/.dotfiles` checkout (run `install.sh` there once). It also needs its own read access to Forgejo, because the pull happens on that host. For hosts without 1Password, put a Forgejo deploy key in `~/.ssh/config.local.d/` (see [Server hosts](#server-hosts)).

The work laptop is left out on purpose. It's network-isolated from the homelab, so a workstation can't push to it. Update it by running `just sync` on the laptop.

### Commands

| Command | Does |
|---|---|
| `just sync` | Pull both repos, refresh externals, apply (prompts when a local file has diverged) |
| `just sync-force` | Same, but overwrites local divergence |
| `just sync-all` | `sync-force` here, then on every reachable host in the push list |
| `just sync-host HOST` | `sync-force` on one host from the push list |
| `just doctor-all` | `chezmoi doctor` here, plus the chezmoi version on each host |
| `just share-keys` | Install the homelab admin public key on each host. The key is fetched from 1Password; the private key never leaves it. |
| `just status` | `chezmoi diff` |
| `just verify-publication` | Scan the tree for private data before pushing (see [Publishing](#publishing)) |

### Adding a Machine

1. In the companion: add the hostname to the right list in `data.yaml` (`server_hostnames`, `workstation_hostnames`, `ssh.headless_hosts`, or `work_hostname`). Then add its SSH entry under `ssh.groups`.
2. If a workstation should be able to push to it, add its alias to `ssh/hosts`.
3. Push the companion, then run `just sync` on your workstation so `~/.ssh/config` and `~/.ssh/hosts` include the new host.
4. Run `just share-keys` to authorize your admin key on the new host.
5. On the new host, run `install.sh` with `DOTFILES_PRIVATE_REPO_URL` set, and `DOTFILES_REPO_URL` set to the Forgejo URL if the host should pull from Forgejo rather than the GitHub mirror.
6. For headless hosts, add a Forgejo deploy key under `~/.ssh/config.local.d/`.
7. From your workstation, run `just sync-host <name>` to confirm push works.

### Server Hosts

The server profile is intentionally minimal. Only SSH aliases and Git config are applied (the `.chezmoiignore` allowlist), so new configs added to the repo stay off servers unless someone deliberately allows them. Hosts listed in the companion's `server_hostnames` are detected automatically. To force the profile:

```bash
CHEZMOI_SERVER=1 chezmoi init --apply --source ~/.dotfiles
```

Headless servers can't use the 1Password SSH agent. Put host-local Forgejo deploy or service keys in `~/.ssh/config.local.d/*.conf`. `~/.ssh/config` includes that directory before any managed `Host` blocks:

```sshconfig
Host git.example.com
    HostName git.example.com
    User git
    Port 222
    IdentityAgent none
    IdentityFile ~/.ssh/forgejo-deploy
    IdentitiesOnly yes
```

## What's Managed

| Category | Contents |
|---|---|
| **Shell** | Zsh (rc, profile, env), Bash, Fish, PowerShell, Starship prompt |
| **Shell config** | 7 alias files, 6 path augmenters, 9 sourced functions, 16 `~/.local/bin` helpers |
| **Editors** | Neovim, VS Code, Cursor (Linux), Zed |
| **Terminals** | Alacritty, Wezterm, Kitty, Ghostty; tmux, sesh, gitmux, herdr |
| **Tools** | Git (templated), mise, Homebrew bundle, 1Password, prettier |
| **macOS** | Hammerspoon, Sketchybar, Aerospace, Espanso, IINA, Raycast, helium-sync |
| **AI tooling** | Claude Code (settings, commands, hooks), ccstatusline, OMP global instructions (`~/.omp/agent/AGENTS.md`), Hermes config (one host) |
| **SSH** | Templated config: 1Password agent or on-disk service keys, per-org GitHub identities, homelab hosts from the companion |
| **Secrets** | `~/.env` is created from 1Password once, on the first interactive apply. Routine and headless applies never call `op`. To regenerate it, delete it and re-apply. |

## How It Works

### Bootstrap Flow

```
install.sh / install.ps1
  ├── Detect OS, install prerequisites (Homebrew / apt / winget) and chezmoi
  ├── Detect and remove old Dotbot symlinks (if migrating)
  ├── Clone repo to ~/.dotfiles
  ├── Clone private companion to ~/.dotfiles-private (if DOTFILES_PRIVATE_REPO_URL)
  └── chezmoi init --apply --source ~/.dotfiles
        ├── .chezmoi.toml.tmpl: resolve server / work / workstation flags
        ├── run_once_before: Brewfile (macOS) / Linux packages
        ├── Externals: companion, zsh frameworks, tmux plugins, agent tooling
        ├── Templates + managed files for this profile
        └── run_after: 1Password ~/.env, OMP install, AI tooling symlinks,
                       SSH pub-key hints, mise setup
```

### Source Layout

```
.chezmoiroot -> home/                   # chezmoi reads sources from home/
install.sh / install.ps1                # bootstrap
justfile                                # sync and fleet recipes
scripts/sync-chezmoi.sh                 # pull + apply, used locally and over SSH
scripts/verify-publication.sh           # publication gate
policy/publication-policy.yaml          # public/private classification per path
tests/                                  # profile rendering + policy tests
docs/adr/                               # architecture decisions
CONTEXT.md                              # domain vocabulary
home/
  .chezmoi.toml.tmpl                    # profile flags + companion data
  .chezmoiexternal.toml.tmpl            # external git clones / archives
  .chezmoiignore                        # OS, profile, and host gating
  .chezmoiscripts/                      # run_once / run_onchange / run_after
  .chezmoitemplates/                    # shared fragments (Zed, herdr)
  private_dot_ssh/config.tmpl           # -> ~/.ssh/config (0600)
  private_dot_ssh/hosts.tmpl            # -> ~/.ssh/hosts, from the companion
  private_dot_hermes/                   # Hermes agent config (hermes_host only)
  dot_config/git/config.tmpl            # -> ~/.config/git/config
  dot_config/zsh/                       # aliases/, paths/, functions/
  dot_config/nvim/                      # Neovim
  dot_claude/                           # Claude Code commands, hooks, settings
  dot_omp/                              # OMP global agent instructions
  dot_local/bin/                        # helper executables
  Library/                              # macOS app configs
  AppData/                              # Windows app configs
```

Chezmoi naming conventions: `dot_` = `.`, `private_` = `0600`, `executable_` = `+x`, `.tmpl` = template.

### Externals

Defined in `.chezmoiexternal.toml.tmpl` and refreshed weekly by `chezmoi apply` (monthly for NvChad). `just sync` refreshes them every time.

| External | Target | Applies to |
|---|---|---|
| Private companion (Forgejo) | `~/.dotfiles-private` | Every profile, once the companion is present |
| oh-my-zsh, zgenom | `~/.oh-my-zsh`, `~/.zgenom` | Non-server |
| tmux-sensible, -resurrect, -continuum, -fzf-url, vim-tmux-navigator | `~/.tmux/plugins/` | Non-server |
| NvChad starter | `~/.config/nvchad-nvim` | Non-server |
| `pi-agent-setup` (Forgejo) | `~/.pi/agent` | Non-server, with companion |
| `agent-tooling` (Forgejo, public mirror on GitHub) | `~/.agent-tooling` | Non-server, with companion |
| Skill packs from `~/.agent-tooling/external-skills.json` | `~/.skills-external/<name>` | Non-server; appear on the second apply of a new machine |
| Work skills overlay (work GitHub org) | `~/.skills-work` | Work only |

To force a refresh: `chezmoi apply --refresh-externals`

### AI Tooling Split

Reusable AI tooling lives in `agent-tooling`, with third-party skill packs in `~/.skills-external` and work-only content in the `~/.skills-work` overlay. `run_after_symlink-ai-mirror.sh` flat-symlinks skills, agents, commands, and hooks from those sources into Claude Code, Cursor, Codex, Pi, and `~/.agents`. It also prunes dead links. When a workflow exists as both a command and a skill, only the command is exported, so it appears once as a slash entry.

Machine-specific AI settings and ccstatusline config live directly in this repo under `home/dot_claude/` and `home/dot_config/ccstatusline/`.

## Common Commands

All commands work from any directory.

```bash
chezmoi diff                     # preview changes before applying
chezmoi apply                    # apply all changes to home directory
chezmoi add ~/.config/foo/bar    # bring a new file under management
chezmoi add --template ~/.foo    # add as a template
chezmoi edit ~/.zshrc            # edit managed file
chezmoi cat ~/.ssh/config        # show rendered template output
chezmoi managed                  # list all managed files
chezmoi data                     # show all template variables (incl. profile flags)
chezmoi doctor                   # check for problems
chezmoi cd                       # cd into the source directory
```

Prefer `just sync` over `chezmoi update`. It also pulls the companion and reports external changes.

## Publishing

This repo is mirrored to GitHub, so nothing private can land in it. `policy/publication-policy.yaml` classifies every tracked path. `scripts/publication-policy.txt` holds structural patterns (private addressing, tailnet names, key material). The git-ignored `scripts/publication-policy.local.txt` holds the literal identifiers. Host, identity, and network specifics belong in the companion.

```bash
just verify-publication           # gitleaks + policy scan of the working tree
just verify-publication-history   # same, over all reachable history
```

## Design Decisions

1. **Hostname gating, with one exception.** Identity depends on the machine, not on where a repo lives. The single `includeIf gitdir:` block covers `~/.dotfiles` itself, which always pushes with the personal email, including from the work machine. See `dot_config/git/config.personal`.
2. **Public repo plus private companion.** Everything reusable is public. Private values are supplied by the companion when templates render, so a public-only checkout still applies cleanly.
3. **Push over SSH, not a pull timer.** A workstation drives fleet updates, so no host changes unless you run a sync.
4. **Server profile is an allowlist.** New configs stay off infrastructure hosts until they're explicitly allowed.
5. **Reusable tooling plus work overlay.** `agent-tooling` goes on every non-server machine; the work overlay only goes on work machines.
6. **VS Code as difftool/mergetool.** Git uses `code --wait --diff` and `code --wait --merge`. Delta handles terminal diffs.
7. **Karabiner excluded.** It's managed manually because of its TypeScript build pipeline.
8. **Repo at `~/.dotfiles`.** chezmoi's `sourceDir` is `~/.dotfiles`, and `.chezmoiroot` points it at `home/`.

## Migration History

This repo replaced an older dotbot-based setup that used symlinks and git submodules; this one uses chezmoi templates and externals. `install.sh` handles the cutover by removing Dotbot symlinks before applying chezmoi. `MIGRATION_MANIFEST.md` is the historical record of how each dotbot entry was mapped.
