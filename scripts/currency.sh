#!/usr/bin/env bash
# Prints `<file>: <tool> <pin> -> <latest>` for each pin behind its latest, and exits 1 if any;
# prints nothing when all are current. Covers the mise tools, those of mise.toml and of the bench
# environment (mise.bench.toml, GuideLLM's), and the llama.cpp build, whose latest is the b-build
# named in the notes of llama.cpp's latest semver release. Reads the network.
set -euo pipefail
cd "$(dirname "$0")/.."

trailing=$(MISE_ENV=bench MISE_LOG_LEVEL=error mise outdated --bump --local --json |
  jq -r 'to_entries[] |
    "\(.value.source.path | split("/") | last): \(.key) \(.value.requested) -> \(.value.bump)"')

# shellcheck source=engines/llama.env
source engines/llama.env
release=$(curl -fsSL https://api.github.com/repos/ggml-org/llama.cpp/releases/latest)
latest=$(jq -r '.body | capture("Nightly build:[^b]*(?<b>b[0-9]+)").b' <<<"$release")
tag=$(jq -r .tag_name <<<"$release")
if [[ -z $latest ]]; then
  echo "currency: llama.cpp $tag's notes name no b-build (\"Nightly build:\")" >&2
  exit 2
fi
if [[ $latest != "$LLAMA_BUILD" ]]; then
  trailing+="${trailing:+$'\n'}engines/llama.env: llama.cpp $LLAMA_BUILD -> $latest ($tag)"
fi

if [[ -n $trailing ]]; then
  echo "$trailing"
  exit 1
fi
