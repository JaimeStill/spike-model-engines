#!/usr/bin/env bash
# Shellchecks every tracked file whose first line is a sh or bash shebang, so a script without a
# .sh extension, such as an engines-<group>-<verb> command, is checked too, and runs lint-context
# and lint-references.
set -uo pipefail
cd "$(dirname "$0")/.." || exit

shellcheck_scripts() {
  local scripts=() file
  while IFS= read -r -d '' file; do
    if head -n 1 "$file" | grep -Eq '^#!.*\b(ba)?sh\b'; then
      scripts+=("$file")
    fi
  done < <(git ls-files -z)
  shellcheck "${scripts[@]}"
}

run_lint() {
  if ! command -v "$1" >/dev/null; then
    echo "FAIL: $1 is not on PATH; run mise install" >&2
    return 1
  fi
  "$1"
}

fail=0
shellcheck_scripts || fail=1
run_lint lint-context || fail=1
run_lint lint-references || fail=1
exit "$fail"
