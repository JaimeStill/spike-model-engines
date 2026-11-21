#!/usr/bin/env bash
# Prints `<file>: <tool> <pin> -> <latest>` for each pin behind its latest, and exits 1 if any;
# prints nothing when all are current. Covers the mise tools of mise.toml, the bench environment
# (mise.bench.toml), and the host environment (mise.host.toml); each host class's llama.cpp build
# (host/llama.env), against the newest b-build with that class's server image on ghcr.io; the vLLM
# release, against vLLM's latest GitHub release; and native vLLM's Python (host/vllm.env), against
# the minor version of CPython's latest release. Reads the network.
#
# See docs/tools.md#the-check-and-currency
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=host/llama-release.sh
source host/llama-release.sh
# shellcheck source=host/vllm.env
source host/vllm.env

mise_tools_behind() {
  local env
  for env in bench host; do
    MISE_ENV=$env MISE_LOG_LEVEL=error mise outdated --bump --local --json |
      jq -r 'to_entries[] | (.value.bump // .value.latest) as $to | select($to != .value.requested) |
        "\(.value.source.path | split("/") | last): \(.key) \(.value.requested) -> \($to)"' ||
      exit
  done | sort -u
}

newest_build_with_image() {
  local flavor=$1 build status
  for build in $builds; do
    status=$(curl -sS -o /dev/null -w '%{http_code}' --head -H "Authorization: Bearer $token" \
      -H "Accept: $accept" "https://ghcr.io/v2/$repository/manifests/server-$flavor-$build") ||
      status=
    case $status in
      200)
        echo "$build"
        return
        ;;
      404) ;;
      *)
        echo "currency: ghcr.io's server-$flavor-$build can't be read (${status:-no answer})" >&2
        exit 2
        ;;
    esac
  done
}

llama_builds_behind() {
  local builds repository token accept class pin flavor latest
  local -A class_flavor=([gb10]=cuda13 [strix-halo]=vulkan)
  builds=$(curl -fsSL 'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=100' |
    jq -r '.[].tag_name | select(test("^b[0-9]+$"))') && [[ -n $builds ]] || {
    echo "currency: llama.cpp's releases can't be read from GitHub" >&2
    exit 2
  }
  repository=${LLAMA_REPOSITORY#ghcr.io/}
  token=$(curl -fsSL "https://ghcr.io/token?scope=repository:$repository:pull" |
    jq -r '.token // empty') && [[ -n $token ]] || {
    echo "currency: ghcr.io gives no pull token for $repository" >&2
    exit 2
  }
  accept=application/vnd.oci.image.index.v1+json
  accept+=,application/vnd.docker.distribution.manifest.list.v2+json
  accept+=,application/vnd.oci.image.manifest.v1+json
  for class in "${LLAMA_CLASSES[@]}"; do
    pin=$(llama_pin "$class") || return
    flavor=${class_flavor[$class]}
    latest=$(newest_build_with_image "$flavor") || return
    if [[ -z $latest ]]; then
      echo "currency: no recent llama.cpp build has an image server-$flavor-<build>" >&2
      exit 2
    fi
    if ((${pin#b} < ${latest#b})); then
      echo "host/llama.env: llama.cpp ($class) $pin -> $latest (server-$flavor)"
    fi
  done
}

vllm_release_behind() {
  local tag
  tag=$(curl -fsSL https://api.github.com/repos/vllm-project/vllm/releases/latest |
    jq -r '.tag_name // empty') || return
  if [[ -z $tag ]]; then
    echo "currency: vLLM's latest release names no tag" >&2
    exit 2
  fi
  if [[ $tag != "$VLLM_RELEASE" ]]; then
    echo "host/vllm.env: vLLM $VLLM_RELEASE -> $tag"
  fi
}

native_python_behind() {
  local latest
  latest=$(MISE_LOG_LEVEL=error mise latest python) || exit 2
  latest=$(cut -d. -f1-2 <<<"$latest") || return
  if [[ $latest != "$VLLM_NATIVE_PYTHON" ]]; then
    echo "host/vllm.env: native Python $VLLM_NATIVE_PYTHON -> $latest"
  fi
}

trailing=$(mise_tools_behind)
for report in llama_builds_behind vllm_release_behind native_python_behind; do
  lines=$("$report")
  trailing+=${lines:+${trailing:+$'\n'}$lines}
done

if [[ -n $trailing ]]; then
  echo "$trailing"
  exit 1
fi
