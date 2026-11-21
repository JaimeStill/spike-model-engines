#!/usr/bin/env bash
# llama.cpp's versions: sourced by scripts/currency.sh and host/llama.sh, and through llama.sh by
# llama-native.sh, so each resolves a version the same way. A version is a semver release, such as
# v0.7.0, or a b-build, such as b11669; a release runs the b-build its notes name ("Nightly
# build:"). The pins are llama.env's, one b-build per host class.
#
# See docs/engines/llama.cpp/scripts.md#the-versions

# shellcheck source=host/llama.env
source "$(dirname "${BASH_SOURCE[0]}")/llama.env"

llama_release() {
  local url=https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$1 json tag
  local tag_re='"tag_name": *"([^"]*)"' build_re='Nightly build:[^b]*(b[0-9]+)'
  if ! json=$(curl -fsSL "$url"); then
    echo "llama.cpp's release $1 can't be read from GitHub" >&2
    return 1
  fi
  [[ $json =~ $tag_re ]] && tag=${BASH_REMATCH[1]}
  if [[ ! $json =~ $build_re ]]; then
    echo "llama.cpp ${tag:-$1}'s notes name no b-build (\"Nightly build:\")" >&2
    return 1
  fi
  echo "${tag:-$1} ${BASH_REMATCH[1]}"
}

LLAMA_CLASSES=(gb10 strix-halo)

llama_pin() {
  case ${1:-} in
    gb10) echo "$LLAMA_BUILD_GB10" ;;
    strix-halo) echo "$LLAMA_BUILD_STRIX_HALO" ;;
    *)
      echo "The host class is ${1:-empty}, which is none of ${LLAMA_CLASSES[*]}" >&2
      return 1
      ;;
  esac
}

llama_build() {
  local release
  if [[ -z ${1:-} ]]; then
    llama_pin "${LLAMA_CLASS:-}"
  elif [[ $1 =~ ^b[0-9]+$ ]]; then
    echo "$1"
  elif [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    release=$(llama_release "$1") || return
    echo "${release#* }"
  else
    echo "$1 is neither a semver release, such as $LLAMA_RELEASE, nor a b-build, such as" \
      "$LLAMA_BUILD_STRIX_HALO" >&2
    return 1
  fi
}
