import QtQuick
import qs.Commons
import qs.Ui

// Behaves like an entry in omarchy.indicators: collapsed while inactive,
// revealed dimmed when the bar's center section is hovered (or alwaysShow),
// full strength while lid close is being ignored. Place it next to
// omarchy.indicators so it reads as one more indicator.
BarWidget {
  id: root
  moduleName: "chupe.lid-suspend"

  readonly property var service: bar?.shell?.serviceFor("chupe.lid-suspend")
  readonly property bool active: service ? service.ignoreLid : false
  readonly property bool alwaysShow: setting("alwaysShow", false) === true
  readonly property bool revealInactive: alwaysShow
    || (bar && bar.centerSectionRevealHeld === true && bar.centerHoverRevealSuppressed !== true)
  readonly property bool shown: active || revealInactive

  clip: true
  implicitWidth: vertical || shown ? indicator.implicitWidth : 0
  implicitHeight: !vertical || shown ? indicator.implicitHeight : 0

  // The host surface BarIndicator expects; omarchy.indicators exposes the same field.
  QtObject {
    id: revealHost
    readonly property bool revealInactiveIndicators: root.revealInactive
  }

  BarIndicator {
    id: indicator
    anchors.fill: parent
    bar: root.bar
    moduleName: root.moduleName
    settings: root.settings
    indicatorHost: revealHost
    active: root.active
    activeText: "󰌢"
    activeTooltipText: "Allow Lid Suspend"
    inactiveTooltipText: "Ignore Lid Close"
    onPressed: function() { if (root.service) root.service.toggle() }
  }
}
