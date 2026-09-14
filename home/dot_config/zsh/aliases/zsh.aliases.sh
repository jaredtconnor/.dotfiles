#!/usr/bin/env bash

# OS Detection
OS=$(uname)

#######################################
# Universal Aliases (work on all systems)
#######################################

# Zsh management
alias rl='source ~/.zshrc; echo ".zshrc reloaded"'
alias regen='zgenom reset;source ~/.zshrc'

# Main directories — home buckets (created by `dev-setup`)
alias .f='cd $(chezmoi source-path 2>/dev/null || echo ~/.dotfiles)'
alias .c='cd ~/Code'
alias .d='cd ~/Code'      # legacy: ~/dev -> ~/Code
alias .n='cd ~/Notes'
alias .dt='cd ~/Data'
alias .t='cd ~/Tools'
alias .s='cd ~/Sandbox'
alias .a='cd ~/Archives'

# Easier navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias .2='cd ../..'
alias .3='cd ../../..'
alias .4='cd ../../../..'
alias .5='cd ../../../../..'
alias ~='cd ~/'

# Notes (single ~/Notes bucket; subfolders for work/personal)
alias notes='cd ~/Notes'
alias worknotes='cd ~/Notes/work'

# Prompt if overwriting
alias cp='cp -i'
alias mv='mv -i'

# History search function
hs() { history | grep -i "$1"; }

# Pi (default: no skills to reduce clutter, but keep management subcommands working)
# Some hosts inject an `alias pi=...` before this file loads, which makes the
# function definition below fail to parse. Clear it first so we always win.
unalias pi 2>/dev/null
pi() {
    case "$1" in
        install|remove|uninstall|update|list|config)
            command pi "$@"
            ;;
        *)
            command pi --no-skills "$@"
            ;;
    esac
}
alias pi-skills='command pi'

# Code editor
alias ca='code -a'

# Other universal commands
alias t="touch"

# cd into the most recently modified directory
alias cdd='cd $(ls -v1td */ | head -1)'

# Case conversion
alias to_lower="tr '[:upper:]' '[:lower:]'"
alias to_upper="tr '[:lower:]' '[:upper:]'"

# JWT from clipboard (requires jq)
alias jwt_from_clip="pbpaste | jwt decode -j - | jq -r '.payload'"
alias jqkeys="jq -r 'select(objects)|=[.] | map( paths(scalars) ) | map( map(select(numbers)=\"[]\") | join(\".\")) | unique | .[]' | sed 's/.\[\]/[]/g' | xargs printf -- '.%s\n'"

# Nvim aliases
alias nvim-chad="NVIM_APPNAME=NvChad nvim"

#######################################
# Tool-specific aliases (with detection)
#######################################

# LSD (better ls) - works on both systems
if type lsd >/dev/null 2>&1; then
    alias ll='lsd -alF --icons --color=always --group-directories-first'
    alias llt='lsd -alF --icons --color=always -s=mod --reverse'
else
    alias ll='ls -la'
    alias llt='ls -lat'
fi

# Bat (better cat) - works on both systems
if type bat >/dev/null 2>&1; then
    alias cat="bat --paging=never"
fi

# Ripgrep (better grep) - works on both systems
if type rg >/dev/null 2>&1; then
    alias rg="rg -i --hidden -g '!.git/'"
    alias rgf="rg --files | rg"
fi

# Tree with .gitignore support - works on both systems
if type rg >/dev/null 2>&1 && type tree >/dev/null 2>&1; then
    alias tr1='rg --files | tree --fromfile -L 1 -C'
    alias tr2='rg --files | tree --fromfile -L 2 -C'
    alias tr3='rg --files | tree --fromfile -L 3 -C'
    alias trall='rg --files | tree --fromfile -C'
fi

#######################################
# OS-Specific Aliases
#######################################

case $OS in
    'Linux')
        # Linux/WSL specific aliases
        alias ls='ls --color=auto -p'

        # APT package management
        alias sagi='sudo apt-get install'
        alias sai='sudo apt install'
        alias sagu='sudo apt-get update'
        alias saguu='sudo apt-get update && sudo apt-get upgrade'
        alias saar='sudo add-apt-repository'
        alias sagr='sudo apt-get remove'
        alias sagrp='sudo apt-get remove --purge'
        alias sacs='apt-cache search'
        alias sacs='apt-cache show'

        # Clipboard aliases (requires xclip)
        if type xclip >/dev/null 2>&1; then
            alias pbcopy='xclip -selection c'
            alias pbpaste='xclip -selection clipboard -o'
        fi

        # Systemctl shortcuts
        if type systemctl >/dev/null 2>&1; then
            alias senable='sudo systemctl enable'
            alias srestart='sudo systemctl restart'
            alias sstatus='sudo systemctl status'
            alias sstop='sudo systemctl stop'
            alias sstart='sudo systemctl start'
            alias sdisable='sudo systemctl disable'
            alias sreload='sudo systemctl reload'
        fi

        # WSL-specific aliases
        if [[ -n "$WSL_DISTRO_NAME" ]]; then
            # Open Windows Explorer in current directory
            alias open='explorer.exe .'
            alias explorer='explorer.exe'

            # Access Windows drives easily
            alias cdc='cd /mnt/c'
            alias cdd='cd /mnt/d'
            alias cde='cd /mnt/e'

            # Windows utilities
            alias cmd='cmd.exe'
            alias powershell='powershell.exe'
            alias pwsh='pwsh.exe'
        fi
        ;;

    'Darwin')
        # macOS specific aliases

        # Karabiner restart (keyboard management)
        alias rk="launchctl stop org.pqrs.karabiner.karabiner_console_user_server;sleep 2;launchctl start org.pqrs.karabiner.karabiner_console_user_server"

        # Homebrew shortcuts
        alias bi='brew install'
        alias bs='brew search'
        alias bu='brew update'
        alias buu='brew update && brew upgrade'
        alias binfo='brew info'
        alias blist='brew list'
        alias boutdated='brew outdated'

        # macOS system aliases
        alias flushdns='sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'
        alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder /System/Library/CoreServices/Finder.app'
        alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder /System/Library/CoreServices/Finder.app'

        # Notification alias
        if type terminal-notifier >/dev/null 2>&1; then
            alias notify="terminal-notifier -title 'ZSH' -sound funk -message"
        fi

        # Flux restart
        alias reflux='osascript -e "tell application \"Flux\" to quit" && open -a Flux'

        # Kitty SSH
        if type kitten >/dev/null 2>&1; then
            alias s="kitten ssh"
        fi

        # Quick Look
        alias ql='qlmanage -p'

        # Lock screen
        alias lock='/System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -suspend'

        # Get macOS version
        alias version='sw_vers'

        # Cleanup
        alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"

        # Empty Trash
        alias emptytrash="sudo rm -rfv /Volumes/*/.Trashes; sudo rm -rfv ~/.Trash; sudo rm -rfv /private/var/log/asl/*.asl; sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV* 'delete from LSQuarantineEvent'"
        ;;

    *)
        # Other Unix systems - minimal aliases
        echo "Unknown OS: $OS - using minimal aliases"
        ;;
esac

#######################################
# Enhanced LS aliases for all systems
#######################################

if [[ "$OS" == "Linux" ]]; then
    alias la='ls -A --color=auto'
    alias l='ls -CF --color=auto'
    alias lh='ls -lah --color=auto'
    alias lt='ls -lat --color=auto'
elif [[ "$OS" == "Darwin" ]]; then
    alias la='ls -A'
    alias l='ls -CF'
    alias lh='ls -lah'
    alias lt='ls -lat'
fi

#######################################
# Development aliases (universal)
#######################################

# Git shortcuts
alias g='git'
alias ga='git add'
alias gaa='git add .'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gs='git status'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gl='git log --oneline'
alias glog='git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'

# Docker shortcuts (if docker is available)
if type docker >/dev/null 2>&1; then
    alias d='docker'
    alias dc='docker-compose'
    alias dps='docker ps'
    alias dpsa='docker ps -a'
    alias di='docker images'
    alias drmi='docker rmi'
    alias drm='docker rm'
    alias dstop='docker stop'
    alias dstart='docker start'
    alias drestart='docker restart'
    alias dexec='docker exec -it'
    alias dlogs='docker logs'
    alias dclean='docker system prune -af'
fi

# Node.js shortcuts
alias ni='npm install'
alias nis='npm install --save'
alias nid='npm install --save-dev'
alias nig='npm install --global'
alias nr='npm run'
alias ns='npm start'
alias nt='npm test'
alias nb='npm run build'

# Yarn shortcuts
if type yarn >/dev/null 2>&1; then
    alias y='yarn'
    alias ya='yarn add'
    alias yad='yarn add --dev'
    alias yag='yarn global add'
    alias yr='yarn run'
    alias ys='yarn start'
    alias yt='yarn test'
    alias yb='yarn build'
fi

# PNPM shortcuts
if type pnpm >/dev/null 2>&1; then
    alias p='pnpm'
    alias pa='pnpm add'
    alias pad='pnpm add --save-dev'
    alias pag='pnpm add --global'
    alias pr='pnpm run'
    alias ps='pnpm start'
    alias pt='pnpm test'
    alias pb='pnpm build'
fi

#######################################
# Network and system monitoring
#######################################

# Network
alias myip='curl ifconfig.me'
alias localip="ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'"
alias ping='ping -c 5'

# System monitoring
alias top='htop'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# Process management
alias psg='ps aux | grep'
alias killall='killall -9'

#######################################
# Fun aliases
#######################################

# Weather (requires curl)
alias weather='curl wttr.in'

# Random quotes (requires curl)
alias quote='curl -s "https://api.quotable.io/random" | jq -r ".content + \" - \" + .author"'

# Colorized output for some commands
alias mount='mount | column -t'
alias path='echo -e ${PATH//:/\\n}'
