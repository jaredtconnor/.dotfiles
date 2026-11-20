#!/usr/bin/env bash

# GOPATH (~/.local/share/go, keeps $HOME tidy) is set in Go's env file, managed
# from .chezmoitemplates/go-env, so every go process sees it, not just
# interactive zsh. The Go toolchain itself comes from mise; here we only put
# GOPATH's bin (the destination for `go install`) on PATH.
export PATH="$PATH:$HOME/.local/share/go/bin"
