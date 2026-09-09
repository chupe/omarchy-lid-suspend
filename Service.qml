import QtQuick
import Quickshell
import Quickshell.Io

// Singleton state for the lid-suspend toggle. One instance per shell, so the
// logind inhibitor is held exactly once no matter how many bars show the icon.
//
// State lives in a flag file so it survives shell restarts and can be flipped
// from outside the shell (`omarchy-toggle lid-suspend-off`, menu rows,
// scripts). The flag is named for the off state like Omarchy's own
// suspend-off / screensaver-off toggles.
//
// While the flag is set the service keeps a transient user unit running that
// holds a `handle-lid-switch` block inhibitor. That is what stops suspend on
// stock Omarchy, where logind owns the lid switch. Setups that route lid close
// through their own script can consult the same flag with
// `omarchy-toggle-enabled lid-suspend-off`.
Item {
  id: root

  // Injected by omarchy-shell (the service loader).
  property var shell: null

  readonly property string flagName: "lid-suspend-off"
  readonly property string togglesDir: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"
  readonly property string flagPath: togglesDir + "/" + flagName

  property bool ignoreLid: false
  property bool stateLoaded: false
  property bool hasPendingWrite: false
  property bool pendingWrite: false

  // The inhibitor is a transient user unit, not a child of the shell. A shell
  // reload or crash orphans children (the shell re-execs under the same pid, so
  // a parent-death check would not notice) and a restart would start a second
  // one; a named unit is a singleton that outlives both and is reconciled to
  // the flag on every read. Stopping the unit drops the inhibitor fd and lets
  // logind handle the lid again.
  readonly property string inhibitUnit: "chupe.lid-suspend-inhibit.service"
  readonly property string inhibitorScript: [
    'unit=$1 want=$2',
    'if [[ $want == hold ]]; then',
    '  if ! systemctl --user is-active --quiet "$unit"; then',
    '    systemctl --user reset-failed "$unit" 2>/dev/null',
    '    systemd-run --user --quiet --collect --unit="$unit" \\',
    '      --description="Omarchy Lid Suspend: Ignore Lid Close is on" \\',
    '      systemd-inhibit --what=handle-lid-switch --who="Omarchy Lid Suspend" \\',
    '        --why="Ignore Lid Close is on" --mode=block sleep infinity',
    '  fi',
    'else',
    '  systemctl --user stop --quiet "$unit" 2>/dev/null',
    'fi',
    'systemctl --user is-active --quiet "$unit" && echo held || echo released'
  ].join("\n")
  property bool inhibitorHeld: false
  property bool inhibitorSyncPending: false

  function refresh() {
    if (!stateProbe.running) stateProbe.running = true
  }

  function setIgnoreLid(value) {
    var enabled = !!value
    root.ignoreLid = enabled
    root.stateLoaded = true

    if (stateWriter.running) {
      root.pendingWrite = enabled
      root.hasPendingWrite = true
      return
    }
    runWriter(enabled)
  }

  function toggle() {
    setIgnoreLid(!root.ignoreLid)
  }

  function runWriter(enabled) {
    stateWriter.command = ["omarchy-toggle", root.flagName, enabled ? "on" : "off"]
    stateWriter.running = true
  }

  function syncInhibitor() {
    if (!stateLoaded) return
    if (inhibitorSync.running) {
      inhibitorSyncPending = true
      return
    }
    inhibitorSync.command = ["bash", "-c", inhibitorScript, "_", inhibitUnit, ignoreLid ? "hold" : "release"]
    inhibitorSync.running = true
  }

  function statusJson() {
    return JSON.stringify({
      enabled: root.ignoreLid,
      stateLoaded: root.stateLoaded,
      flagPath: root.flagPath,
      inhibitUnit: root.inhibitUnit,
      inhibitorHeld: root.inhibitorHeld
    })
  }

  Process {
    id: inhibitorSync
    stdout: SplitParser {
      onRead: function(line) { root.inhibitorHeld = String(line).trim() === "held" }
    }
    stderr: SplitParser {
      onRead: function(line) { console.warn("chupe.lid-suspend: inhibitor sync:", String(line).trim()) }
    }
    onExited: function() {
      if (root.inhibitorSyncPending) {
        root.inhibitorSyncPending = false
        root.syncInhibitor()
        return
      }
      if (root.inhibitorHeld !== root.ignoreLid) console.warn("chupe.lid-suspend: inhibitor", root.inhibitorHeld ? "held" : "released", "while flag is", root.ignoreLid ? "on" : "off")
    }
  }

  Process {
    id: stateProbe
    // mkdir keeps the directory watcher valid before the first toggle ever runs.
    command: ["bash", "-c", "mkdir -p \"$1\"; [[ -f $1/$2 ]] && echo yes || echo no", "_", root.togglesDir, root.flagName]
    stdout: SplitParser {
      onRead: function(line) {
        root.ignoreLid = String(line).trim() === "yes"
        root.stateLoaded = true
      }
    }
    onExited: function() {
      togglesDirWatcher.reload()
      root.syncInhibitor()
    }
  }

  Process {
    id: stateWriter
    onExited: function() {
      if (root.hasPendingWrite) {
        var pending = root.pendingWrite
        root.hasPendingWrite = false
        root.runWriter(pending)
        return
      }
      root.refresh()
    }
  }

  // Watching the directory (not the flag) is what makes external toggles show
  // up: a watcher on a missing file never fires when the file is created.
  FileView {
    id: togglesDirWatcher
    path: root.togglesDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Component.onCompleted: refresh()

  IpcHandler {
    target: "chupe.lid-suspend"

    function status(): string {
      return root.statusJson()
    }

    function enable(): string {
      root.setIgnoreLid(true)
      return "enabled"
    }

    function disable(): string {
      root.setIgnoreLid(false)
      return "disabled"
    }

    function toggle(): string {
      root.toggle()
      return root.ignoreLid ? "enabled" : "disabled"
    }
  }
}
