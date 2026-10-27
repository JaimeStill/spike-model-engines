#!/usr/bin/env bash
# llama.cpp's versions, in one place: sourced by scripts/currency.sh and host/llama.sh, and by any
# script that runs llama.cpp natively, so each resolves a version the same way. A version is a
# semver release, such as v0.7.0, or a b-build, such as b11669; a release runs the b-build its
# notes name ("Nightly build:"). It reads the notes with curl and bash alone, since the host's
# scripts run outside mise and can't count on its jq.

# shellcheck source=host/llama.env
source "$(dirname "${BASH_SOURCE[0]}")/llama.env"

# Prints the tag of the release given (a semver tag, or latest for llama.cpp's latest release) and
# the b-build its notes name, as `<tag> <build>`, such as `v0.7.0 b11669`. Reads the network, and
# fails, saying why, when the release can't be read or its notes name no b-build.
llama_release() {
  local url=https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$1 json tag
  local tag_re='"tag_name": *"([^"]*)"' build_re='Nightly build:[^b]*(b[0-9]+)'
  [[ $1 == latest ]] && url=https://api.github.com/repos/ggml-org/llama.cpp/releases/latest
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

# Prints the b-build for the version given: a b-build as given, a semver release's b-build from its
# notes (llama_release), and the pin's, LLAMA_BUILD, when given nothing. Refuses anything else.
llama_build() {
  local release
  if [[ -z ${1:-} ]]; then
    echo "$LLAMA_BUILD"
  elif [[ $1 =~ ^b[0-9]+$ ]]; then
    echo "$1"
  elif [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    release=$(llama_release "$1") || return
    echo "${release#* }"
  else
    echo "$1 is neither a semver release, such as $LLAMA_RELEASE, nor a b-build, such as" \
      "$LLAMA_BUILD" >&2
    return 1
  fi
}
