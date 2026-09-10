#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

agent_control_file=$(
  find "$plugin_dir" \
    -path "$plugin_dir/.git" -prune -o \
    -type f \( \
      -iname AGENTS.md -o \
      -iname CLAUDE.md -o \
      -iname GEMINI.md -o \
      -name .cursorrules -o \
      -name .windsurfrules -o \
      -path '*/.github/copilot-instructions.md' \
    \) -print -quit
)

if [[ -n $agent_control_file ]]; then
  echo "agent-control file is not allowed in marketplace payload: $agent_control_file" >&2
  exit 1
fi

echo "repository layout tests passed"
