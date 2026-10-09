#!/bin/zsh
# Double-click to run the campaign with the private, loopback-only advisor broker.
# The credential file is outside the repository and is never passed to Godot.
set -eu
task_root=${0:A:h}
cd "$task_root"
exec python3 tools/marcus_broker.py \
  --credentials-file "$HOME/Library/Application Support/Roman War/private-advisors.json" \
  --campaign --launch
