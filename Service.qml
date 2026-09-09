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
// While the flag is set the service holds a `handle-lid-switch` block
// inhibitor. That is what stops suspend on stock Omarchy, where logind owns
// the lid switch. Setups that route lid close through their own script can
// consult the same flag with `omarchy-toggle-enabled lid-suspend-off`.
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

  function statusJson() {
    return JSON.stringify({
      enabled: root.ignoreLid,
      stateLoaded: root.stateLoaded,
      flagPath: root.flagPath,
      inhibitorHeld: inhibitor.running
    })
  }

  // Held only while the toggle is on. Setting `running` false sends SIGTERM,
  // which drops the inhibitor fd and lets logind handle the lid again.
  Process {
    id: inhibitor
    command: [
      "systemd-inhibit",
      "--what=handle-lid-switch",
      "--who=Omarchy Lid Suspend",
      "--why=Ignore Lid Close is on",
      "--mode=block",
      "sleep", "infinity"
    ]
    running: root.stateLoaded && root.ignoreLid
    onExited: function(exitCode, exitStatus) {
      if (root.ignoreLid && exitCode !== 0) console.warn("chupe.lid-suspend: inhibitor exited", exitCode, exitStatus)
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
    onExited: function() { togglesDirWatcher.reload() }
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
