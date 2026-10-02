#!/usr/bin/env bash
# ghq + gwq + fzf: unified repo/worktree navigation.
#
# Both cloned repos (ghq) and worktrees (gwq) live under one root (~/Code, from
# `git config ghq.root`), so a single fzf jumps to either. Sourced by ~/.zshrc
# from ~/.config/zsh/functions/.
#
#   repo         fuzzy-pick a cloned repo and cd into it
#   clone <spec> ghq-clone <url|host/owner/repo|owner/repo> then cd in
#   wt           fuzzy-pick a git worktree and cd into it (gwq)
#   Ctrl-G       keybinding for `repo`
# Worktree lifecycle aliases (wta/wtl/wts/wtrm) live in ghq.aliases.sh.

# Best-effort: rename the current tmux session to match the directory jumped to.
_repo_tmux_rename() {
    [[ -n "$TMUX" ]] || return 0
    local name="${1##*/}"
    tmux rename-session "${name//[.:= ]/-}" 2>/dev/null || true
}

# repo — fuzzy-pick a ghq-managed clone and cd into it.
repo() {
    if ! command -v ghq >/dev/null 2>&1 || ! command -v fzf >/dev/null 2>&1; then
        echo "repo: needs ghq and fzf on PATH" >&2
        return 1
    fi
    local dest
    dest=$(ghq list --full-path | fzf --prompt 'repo > ' --height 80% \
        --preview 'git -C {} -c color.ui=always log --oneline --decorate -20 2>/dev/null || ls -la {}') || return
    [[ -n "$dest" ]] || return
    cd "$dest" || return 1
    _repo_tmux_rename "$dest"
}

# clone <spec...> — clone into the ghq root, then cd into the new repo.
clone() {
    command -v ghq >/dev/null 2>&1 || {
        echo "clone: ghq not on PATH" >&2
        return 1
    }
    [[ $# -ge 1 ]] || {
        echo "usage: clone <url | host/owner/repo | owner/repo>" >&2
        return 1
    }
    ghq get "$@" || return 1
    # Derive the repo name from the last positional arg to cd into it.
    local spec name dest
    for spec in "$@"; do :; done
    name="${spec##*/}"
    name="${name%.git}"
    dest=$(ghq list --full-path | fzf --filter "$name" 2>/dev/null | head -1)
    [[ -n "$dest" ]] && {
        cd "$dest" || return 1
        _repo_tmux_rename "$dest"
    }
}

# wt — fuzzy-pick a git worktree (across all repos) and cd into it.
# Relies on gwq shell integration (cd.launch_shell=false) sourced below.
wt() {
    command -v gwq >/dev/null 2>&1 || {
        echo "wt: gwq not on PATH" >&2
        return 1
    }
    gwq cd -g "$@" && _repo_tmux_rename "$PWD"
}

# gwq shell integration + completion: makes `gwq cd` / `gwq add -s` change the
# current shell's directory (see cd.launch_shell=false in gwq config.toml).
if command -v gwq >/dev/null 2>&1; then
    source <(gwq completion zsh) 2>/dev/null
fi

# Ctrl-G: jump to a repo via the fzf picker, without disturbing the command line.
if [[ -n "$ZSH_VERSION" ]] && command -v ghq >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
    _repo_zle_widget() {
        local dest
        dest=$(ghq list --full-path | fzf --prompt 'repo > ' --height 80% \
            --preview 'git -C {} -c color.ui=always log --oneline --decorate -20 2>/dev/null || ls -la {}')
        if [[ -n "$dest" ]]; then
            builtin cd "$dest" && _repo_tmux_rename "$dest"
        fi
        zle reset-prompt
    }
    zle -N _repo_zle_widget
    bindkey '^g' _repo_zle_widget
fi
