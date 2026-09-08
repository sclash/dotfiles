#!/bin/sh

selected_path=$(find $(pwd) -type d  \
		! -path "*node_modules*" \
		! -path "*__pycache__*" \
		! -path "*.git*" \
		! -path "*.venv*" \
		! -path "*venv*" \
		! -path "build.zig" \
		! -path "Cargo.toml" \
		! -path "go.mod" \
		| fzf)
if [ -n "$selected_path" ]; then
    tmux new-session -d -c "$selected_path" 
    tmux attach-session
fi
