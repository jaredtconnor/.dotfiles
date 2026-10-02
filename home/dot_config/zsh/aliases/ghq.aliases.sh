#!/usr/bin/env bash
# gwq worktree lifecycle shortcuts. Navigation (repo/clone/wt) lives in
# ~/.config/zsh/functions/ghq.functions.sh. Sourced by ~/.zshrc.

if command -v gwq >/dev/null 2>&1; then
    alias wta='gwq add'       # gwq add -b <branch> (new) | <branch> (existing)
    alias wtl='gwq list -g'   # list worktrees across all repos
    alias wts='gwq status -g' # status dashboard across all repos
    alias wtrm='gwq remove'   # remove a worktree (add -b to also drop branch)
    alias wtp='gwq prune'     # clean up stale worktree metadata
fi
