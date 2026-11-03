#!/usr/bin/env bash
# Prints `<file>: <tool> <pin> -> <latest>` for each pin behind its latest, and exits 1 if any;
# prints nothing when all are current. Covers the mise tools, those of mise.toml, of the bench
# environment (mise.bench.toml, GuideLLM's), and of the host environment (mise.host.toml, hf's); the
# llama.cpp build of each host class (host/llama-release.sh), reported only when it is behind its
# latest, the b-build named in the notes of llama.cpp's latest semver release, since a class may run
# a b-build past that release, as gb10 does; the vLLM release, whose latest is vLLM's latest GitHub
# release; and native vLLM's Python (host/vllm.env), a minor version, whose latest is the minor
# version of CPython's latest release, as mise reads it. A pin held on purpose, as GuideLLM's
# Python, the vLLM release, and native vLLM's Python are, is reported like any other, and its
# comment says why it is held.
# Reads the network.
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

# shellcheck source=host/llama-release.sh
source host/llama-release.sh
release=$(llama_release latest) || exit 2
tag=${release% *} latest=${release#* }
for class in "${LLAMA_CLASSES[@]}"; do
  pin=$(llama_pin "$class")
  if ((${pin#b} < ${latest#b})); then
    trailing+="${trailing:+$'\n'}host/llama.env: llama.cpp ($class) $pin -> $latest ($tag)"
  fi
done

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

latest=$(MISE_LOG_LEVEL=error mise latest python) || exit 2
latest=$(cut -d. -f1-2 <<<"$latest")
if [[ $latest != "$VLLM_NATIVE_PYTHON" ]]; then
  trailing+="${trailing:+$'\n'}host/vllm.env: native Python $VLLM_NATIVE_PYTHON -> $latest"
fi

if [[ -n $trailing ]]; then
  echo "$trailing"
  exit 1
fi
