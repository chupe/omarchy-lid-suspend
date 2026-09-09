#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d "$plugin_dir/tmp.lid-state-refresh.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

refresh_function=$(
  awk '
    /^  function refreshLidState\(\) \{/ { capture = 1 }
    capture { print }
    capture && /^  \}$/ { exit }
  ' "$plugin_dir/Service.qml"
)

[[ -n $refresh_function ]] || {
  echo "refreshLidState() was not found in Service.qml" >&2
  exit 1
}

cat >"$tmp_dir/shell.qml" <<EOF
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  property int probeStarts: 0
  property bool finalLidClosed: true

$refresh_function

  Process {
    id: lidStateProbe
    stdinEnabled: true
    command: ["bash", "-c", "read -r; echo 'b true'"]

    onStarted: function() {
      root.probeStarts++
      if (root.probeStarts === 1) {
        lidStateProbe.command = ["bash", "-c", "echo 'b false'"]
        root.refreshLidState()
        lidStateProbe.write("release\\n")
      }
    }

    stdout: SplitParser {
      onRead: function(line) {
        root.finalLidClosed = String(line).trim() === "b true"
      }
    }

    onExited: function() {
      if (root.probeStarts !== 2) return
      Qt.callLater(function() {
        if (root.finalLidClosed) {
          console.error("FAIL: queued lid-open probe did not replace stale lid-closed state")
        } else {
          console.log("PASS: queued lid-open probe replaced stale lid-closed state")
        }
        Qt.quit()
      })
    }
  }

  Timer {
    interval: 2000
    running: true
    onTriggered: function() {
      console.error("FAIL: expected two lid-state probes, observed " + root.probeStarts)
      Qt.quit()
    }
  }

  Component.onCompleted: root.refreshLidState()
}
EOF

output=$(qs --no-color --path "$tmp_dir" 2>&1)
printf '%s\n' "$output"
grep -q 'PASS: queued lid-open probe replaced stale lid-closed state' <<<"$output"
! grep -q 'FAIL:' <<<"$output"
