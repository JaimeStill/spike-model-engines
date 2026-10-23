#!/usr/bin/env bash
# Prints `mise.toml: <tool> <pin> -> <latest>` for each mise tool behind its latest, and exits 1 if
# any; prints nothing when all are current. Reads the network.
set -euo pipefail
cd "$(dirname "$0")/.."

trailing=$(MISE_LOG_LEVEL=error mise outdated --bump --local --json |
  jq -r 'to_entries[] | "mise.toml: \(.key) \(.value.requested) -> \(.value.bump)"')

if [[ -n $trailing ]]; then
  echo "$trailing"
  exit 1
fi
