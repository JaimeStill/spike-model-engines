#!/usr/bin/env bash
# Prints `<file>: <tool> <pin> -> <latest>` for each pin behind its latest, and exits 1 if any;
# prints nothing when all are current. Covers the mise tools, those of mise.toml, of the bench
# environment (mise.bench.toml, GuideLLM's), and of the host environment (mise.host.toml, hf's);
# the llama.cpp build, whose latest is the b-build named in the notes of llama.cpp's latest semver
# release; and the vLLM release, whose latest is vLLM's latest GitHub release. Reads the network.
set -euo pipefail
cd "$(dirname "$0")/.."

# Each environment is read on its own, since both pin uv and one would hide the other's pin;
# mise.toml's tools, which both read, are listed once. mise lists a tool not installed here, such
# as hf on the laptop, with no bump, so its pin is compared with its latest instead. A failed read
# stops the script.
trailing=$(for env in bench host; do
  MISE_ENV=$env MISE_LOG_LEVEL=error mise outdated --bump --local --json |
    jq -r 'to_entries[] | (.value.bump // .value.latest) as $to | select($to != .value.requested) |
      "\(.value.source.path | split("/") | last): \(.key) \(.value.requested) -> \($to)"' ||
    exit
done | sort -u)

# shellcheck source=host/llama.env
source host/llama.env
release=$(curl -fsSL https://api.github.com/repos/ggml-org/llama.cpp/releases/latest)
latest=$(jq -r '.body | capture("Nightly build:[^b]*(?<b>b[0-9]+)").b' <<<"$release")
tag=$(jq -r .tag_name <<<"$release")
if [[ -z $latest ]]; then
  echo "currency: llama.cpp $tag's notes name no b-build (\"Nightly build:\")" >&2
  exit 2
fi
if [[ $latest != "$LLAMA_BUILD" ]]; then
  trailing+="${trailing:+$'\n'}host/llama.env: llama.cpp $LLAMA_BUILD -> $latest ($tag)"
fi

# shellcheck source=host/vllm.env
source host/vllm.env
tag=$(curl -fsSL https://api.github.com/repos/vllm-project/vllm/releases/latest |
  jq -r '.tag_name // empty')
if [[ -z $tag ]]; then
  echo "currency: vLLM's latest release names no tag" >&2
  exit 2
fi
if [[ $tag != "$VLLM_RELEASE" ]]; then
  trailing+="${trailing:+$'\n'}host/vllm.env: vLLM $VLLM_RELEASE -> $tag"
fi

if [[ -n $trailing ]]; then
  echo "$trailing"
  exit 1
fi
