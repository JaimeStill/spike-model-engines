#!/usr/bin/env bash
# Prints `<file>: <tool> <pin> -> <latest>` for each pin behind its latest, and exits 1 if any;
# prints nothing when all are current. Covers the mise tools, those of mise.toml, of the bench
# environment (mise.bench.toml, GuideLLM's), and of the host environment (mise.host.toml, hf's); the
# llama.cpp build of each host class (host/llama-release.sh), whose latest is the newest b-build
# with that class's server image on ghcr.io (server-cuda13-<build> for gb10, server-vulkan-<build>
# for strix-halo), not the newest release, since llama.cpp publishes images only nightly and on
# manual runs, so its newest release often has none and `engines llama update` couldn't pull it,
# and reported only when the pin is lower; the vLLM release, whose latest is vLLM's latest GitHub
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
# The flavor whose image stands for each class's: gb10's cuda13, and strix-halo's vulkan.
declare -A flavors=([gb10]=cuda13 [strix-halo]=vulkan)
builds=$(curl -fsSL 'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=100' |
  jq -r '.[].tag_name | select(test("^b[0-9]+$"))') && [[ -n $builds ]] || {
  echo "currency: llama.cpp's releases can't be read from GitHub" >&2
  exit 2
}
repository=${LLAMA_REPOSITORY#ghcr.io/}
token=$(curl -fsSL "https://ghcr.io/token?scope=repository:$repository:pull" | jq -r '.token // empty') &&
  [[ -n $token ]] || {
  echo "currency: ghcr.io gives no pull token for $repository" >&2
  exit 2
}
accept=application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json
accept+=,application/vnd.oci.image.manifest.v1+json
for class in "${LLAMA_CLASSES[@]}"; do
  pin=$(llama_pin "$class") flavor=${flavors[$class]} latest=
  # Newest first, stopping at the first build whose image exists (200); a 404 means none yet, and
  # any other answer is a failed read.
  for build in $builds; do
    status=$(curl -sS -o /dev/null -w '%{http_code}' --head -H "Authorization: Bearer $token" \
      -H "Accept: $accept" "https://ghcr.io/v2/$repository/manifests/server-$flavor-$build") || status=
    case $status in
      200) latest=$build && break ;;
      404) ;;
      *)
        echo "currency: ghcr.io's server-$flavor-$build can't be read (${status:-no answer})" >&2
        exit 2
        ;;
    esac
  done
  if [[ -z $latest ]]; then
    echo "currency: no recent llama.cpp build has an image server-$flavor-<build>" >&2
    exit 2
  fi
  if ((${pin#b} < ${latest#b})); then
    trailing+="${trailing:+$'\n'}host/llama.env: llama.cpp ($class) $pin -> $latest (server-$flavor)"
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
