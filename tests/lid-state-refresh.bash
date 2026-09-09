#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/chupe.lid-suspend.state-refresh.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

run_queue_test() {
  local function_name=$1
  local process_id=$2
  local label=$3
  local case_dir="$tmp_dir/$function_name"
  local refresh_function
  local output

  mkdir -p "$case_dir"
  refresh_function=$(
    awk -v name="$function_name" '
      $0 ~ "^  function " name "\\(\\) \\{" { capture = 1 }
      capture { print }
      capture && /^  \}$/ { exit }
    ' "$plugin_dir/Service.qml"
  )

  [[ -n $refresh_function ]] || {
    echo "$function_name() was not found in Service.qml" >&2
    exit 1
  }

  cat >"$case_dir/shell.qml" <<EOF
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  property int probeStarts: 0
  property string finalOutput: ""

$refresh_function

  Process {
    id: $process_id
    stdinEnabled: true
    command: ["bash", "-c", "read -r; echo first"]

    onStarted: function() {
      root.probeStarts++
      if (root.probeStarts === 1) {
        $process_id.command = ["bash", "-c", "echo second"]
        root.$function_name()
        $process_id.write("release\\n")
      }
    }

    stdout: SplitParser {
      onRead: function(line) {
        root.finalOutput = String(line).trim()
      }
    }

    onExited: function() {
      if (root.probeStarts !== 2) return
      Qt.callLater(function() {
        if (root.finalOutput !== "second") {
          console.error("FAIL: $label refresh kept stale output")
        } else {
          console.log("PASS: $label refresh queued a follow-up probe")
        }
        Qt.quit()
      })
    }
  }

  Timer {
    interval: 2000
    running: true
    onTriggered: function() {
      console.error("FAIL: $label refresh expected two probes, observed " + root.probeStarts)
      Qt.quit()
    }
  }

  Component.onCompleted: root.$function_name()
}
EOF

  output=$(qs --no-color --path "$case_dir" 2>&1)
  printf '%s\n' "$output"
  grep -q "PASS: $label refresh queued a follow-up probe" <<<"$output"
  ! grep -q 'FAIL:' <<<"$output"
}

run_queue_test refreshLidState lidStateProbe lid-state
run_queue_test refresh stateProbe flag-state
