#!/usr/bin/env bash
# Shellchecks every tracked file whose first line is a sh or bash shebang, so a script without a
# .sh extension, such as an engines-<group>-<verb> command, is checked too.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts=()
while IFS= read -r -d '' file; do
  if head -n 1 "$file" | grep -Eq '^#!.*\b(ba)?sh\b'; then
    scripts+=("$file")
  fi
done < <(git ls-files -z)

shellcheck "${scripts[@]}"
