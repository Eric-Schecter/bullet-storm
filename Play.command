#!/bin/zsh
cd "$(dirname "$0")"
exec /Applications/Godot.app/Contents/MacOS/Godot --path "$PWD" --log-file /tmp/t16-game.log "$@"
