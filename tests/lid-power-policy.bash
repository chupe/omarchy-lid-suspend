#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/chupe.lid-suspend.power-policy.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

policy_function=$(
  awk '
    /^  function desiredLidPowerAction\(\) \{/ { capture = 1 }
    capture { print }
    capture && /^  \}$/ { exit }
  ' "$plugin_dir/Service.qml"
)

[[ -n $policy_function ]] || {
  echo "desiredLidPowerAction() was not found in Service.qml" >&2
  exit 1
}

cat >"$tmp_dir/shell.qml" <<EOF
import QtQuick
import Quickshell

ShellRoot {
  id: root

  property bool stateLoaded: false
  property bool ignoreLid: false
  property bool lidStateLoaded: false
  property bool lidClosed: false

$policy_function

  function verify(stateReady, enabled, lidReady, closed, expected) {
    root.stateLoaded = stateReady
    root.ignoreLid = enabled
    root.lidStateLoaded = lidReady
    root.lidClosed = closed
    var actual = root.desiredLidPowerAction()
    if (actual !== expected)
      throw new Error("expected " + expected + ", got " + actual)
  }

  function runChecks() {
    try {
      verify(false, false, false, false, "")
      verify(true, true, false, true, "")
      verify(false, true, true, true, "")
      verify(true, false, true, true, "open")
      verify(true, true, true, false, "open")
      verify(true, true, true, true, "close")
      console.log("PASS: power profile follows enabled-and-closed policy")
    } catch (error) {
      console.error("FAIL: " + error)
    }
    Qt.quit()
  }

  Timer {
    interval: 2000
    running: true
    onTriggered: function() {
      console.error("FAIL: power policy test timed out")
      Qt.quit()
    }
  }

  Component.onCompleted: Qt.callLater(root.runChecks)
}
EOF

output=$(qs --no-color --path "$tmp_dir" 2>&1)
printf '%s\n' "$output"
grep -q 'PASS: power profile follows enabled-and-closed policy' <<<"$output"
! grep -q 'FAIL:' <<<"$output"
