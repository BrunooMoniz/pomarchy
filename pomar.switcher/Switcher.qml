import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "shared"
import "shared/Tokens.js" as Tokens
import "shared/Apps.js" as Apps
import "shared/I18n.js" as I18n
import "Strings.js" as Strings

// Alternador de apps no estilo Cmd+Tab. Quem guia é o Hyprland: SUPER+TAB
// abre e avança, SUPER+SHIFT+TAB volta, soltar o SUPER escolhe (submapa
// "pomar-switcher" no hypr/pomar.lua). Este overlay não pega o teclado; só
// mostra os apps na ordem de uso e obedece aos eventos switcher:*.
Item {
  id: root

  property bool opened: false
  property bool shown: false
  property var apps: []
  property int index: 0
  readonly property bool dark: Tokens.isDark(Color.background)
  readonly property string lang: I18n.resolve(settings.get("language", "auto"), Quickshell.env("LANG"))
  readonly property bool usable: settings.active && settings.get("switcher.enabled", true)
  readonly property var webIndex: Apps.webappIndex(DesktopEntries.applications.values)
  readonly property var selectedApp: apps.length ? apps[Math.max(0, Math.min(index, apps.length - 1))] : null

  PomarSettings { id: settings }
  HyprClients { id: hypr; onSerialChanged: if (root.opened) root.rebuild(false) }
  PomarEvents {
    id: events
    onCommand: function(target, verb, arg) {
      if (target === "overlay" && verb === "opened" && arg !== "switcher" && root.opened) root.cancel()
      if (target !== "switcher") return
      if (verb === "next") root.step(1)
      else if (verb === "prev") root.step(-1)
      else if (verb === "commit") root.commit()
      else if (verb === "cancel") root.cancel()
      else if (verb === "quit") root.quitSelected()
    }
  }

  // Agrupa as janelas por app, na ordem de uso recente (focusHistoryID).
  function group(clients) {
    var order = []
    var byKey = ({})
    for (var i = 0; i < clients.length; i++) {
      var c = clients[i]
      var cls = c["class"] || c.initialClass || ""
      if (!cls) continue
      var key = Apps.appKey(DesktopEntries, cls, root.webIndex)
      if (!byKey[key]) {
        var entry = Apps.entryFor(DesktopEntries, cls, root.webIndex)
        byKey[key] = { key: key, name: Apps.displayName(entry, cls),
                       icon: Apps.iconSource(Quickshell, entry, cls), windows: [] }
        order.push(byKey[key])
      }
      byKey[key].windows.push(c)
    }
    return order
  }

  function rebuild(resetIndex) {
    var list = []
    var all = hypr.allClients
    for (var i = 0; i < all.length; i++) {
      var ws = all[i].workspace ? String(all[i].workspace.name || "") : ""
      if (ws.indexOf("special:") === 0 && ws !== hypr.minimizedWorkspace) continue
      list.push(all[i])
    }
    root.apps = root.group(list)
    if (resetIndex) root.index = root.apps.length > 1 ? 1 : 0
    else root.index = Math.min(root.index, Math.max(0, root.apps.length - 1))
  }

  function step(direction) {
    if (!root.usable) { resetSubmap(); return }
    if (!root.opened) {
      root.opened = true
      hypr.refreshNow()
      root.rebuild(true)
      if (direction < 0) root.index = Math.max(0, root.apps.length - 1)
      // Toque rápido (SUPER+TAB e solta) troca de app sem piscar a tela.
      showDelay.restart()
      events.send("overlay", "opened", "switcher")
    } else if (root.apps.length) {
      root.index = (root.index + direction + root.apps.length) % root.apps.length
    }
    watchdog.restart()
  }

  function focusApp(app) {
    if (!app || !app.windows.length) return
    var win = app.windows[0]
    var address = String(win.address).replace(/[^0-9a-fx]/gi, "")
    if (hypr.isMinimized(win)) {
      var mon = null
      for (var i = 0; i < hypr.monitors.length; i++) if (hypr.monitors[i].focused) mon = hypr.monitors[i]
      var ws = mon && mon.activeWorkspace ? mon.activeWorkspace.id : 1
      events.dispatch('hl.dsp.window.move({ window = "address:' + address + '", workspace = "' + ws + '", follow = true })')
    }
    events.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  function commit() {
    if (!root.opened) return
    var app = root.selectedApp
    root.hide()
    // Com um app só na lista não há para onde ir; ainda assim foca a janela dele.
    root.focusApp(app)
  }

  function cancel() {
    root.hide()
  }

  function hide() {
    showDelay.stop()
    watchdog.stop()
    root.opened = false
    root.shown = false
    resetSubmap()
  }

  function resetSubmap() {
    events.dispatch('hl.dsp.submap("reset")')
  }

  // SUPER+Q com o alternador aberto fecha todas as janelas do app escolhido.
  function quitSelected() {
    var app = root.selectedApp
    if (!app) return
    for (var i = 0; i < app.windows.length; i++) {
      var address = String(app.windows[i].address).replace(/[^0-9a-fx]/gi, "")
      events.dispatch('hl.dsp.window.close({ window = "address:' + address + '" })')
    }
    hypr.refresh()
    watchdog.restart()
  }

  // Contrato do Omarchy (summon/hide pelo shell).
  function open(payloadJson) { root.step(1) }
  function close() { root.cancel() }

  Timer {
    id: showDelay
    interval: 110
    onTriggered: if (root.opened) root.shown = true
  }

  // Rede de segurança: se o soltar do SUPER se perder, ninguém fica preso no
  // submapa do alternador.
  Timer {
    id: watchdog
    interval: 20000
    onTriggered: root.cancel()
  }

  PanelWindow {
    id: panel
    visible: root.shown
    color: "transparent"
    screen: {
      var mon = Hyprland.focusedMonitor
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) if (mon && screens[i].name === mon.name) return screens[i]
      return screens.length ? screens[0] : null
    }
    implicitWidth: Math.min((screen ? screen.width : 1920) - 80, card.implicitWidth + 60)
    implicitHeight: card.implicitHeight + 60
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "pomar-switcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property int cell: 112
    readonly property int iconSize: 92

    Item {
      id: card
      anchors.centerIn: parent
      implicitWidth: row.implicitWidth + 36
      implicitHeight: panel.cell + 64
      width: Math.min(implicitWidth, panel.width - 60)
      height: implicitHeight
      scale: root.shown ? 1 : 0.94
      opacity: root.shown ? 1 : 0
      Behavior on scale { NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: Tokens.motion.instant } }

      Glass {
        anchors.fill: parent
        dark: root.dark
        radius: 26
        fill: Tokens.glassStrong(root.dark)
        shadowBlur: 40
        shadowOffsetY: 14
      }

      Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 18
        anchors.bottomMargin: 46
        contentWidth: row.implicitWidth
        contentHeight: height
        interactive: false
        clip: true
        contentX: {
          var itemX = root.index * (panel.cell + row.spacing)
          var max = Math.max(0, contentWidth - width)
          return Tokens.clamp(itemX - (width - panel.cell) / 2, 0, max)
        }
        Behavior on contentX { NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic } }

        Row {
          id: row
          spacing: 6
          height: parent.height
          Repeater {
            model: root.apps
            delegate: Item {
              id: cellItem
              required property var modelData
              required property int index
              readonly property bool current: index === root.index
              width: panel.cell
              height: panel.cell

              Rectangle {
                anchors.fill: parent
                radius: 18
                color: cellItem.current ? (root.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10)) : "transparent"
                Behavior on color { ColorAnimation { duration: Tokens.motion.instant } }
              }

              AppIconTile {
                anchors.centerIn: parent
                width: panel.iconSize
                height: panel.iconSize
                textureSize: panel.iconSize * 2
                source: cellItem.modelData.icon
                dark: root.dark
              }

              // Várias janelas do mesmo app: um número discreto no canto.
              Rectangle {
                visible: cellItem.modelData.windows.length > 1
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                width: 22
                height: 22
                radius: 11
                color: Color.accent
                Text {
                  anchors.centerIn: parent
                  text: cellItem.modelData.windows.length
                  color: "white"
                  font.pixelSize: 11
                  font.bold: true
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.index = cellItem.index
                onClicked: { root.index = cellItem.index; root.commit() }
              }
            }
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        width: parent.width - 40
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.selectedApp ? root.selectedApp.name : I18n.tr(Strings.TABLE, "noApps", root.lang)
        color: Tokens.label(root.dark)
        font.pixelSize: 14
        font.weight: Font.Medium
      }
    }
  }

  IpcHandler {
    target: "pomar-switcher-test"
    enabled: Quickshell.env("POMAR_TEST") === "1"
    function state(): string {
      return JSON.stringify({ opened: root.opened, shown: root.shown, index: root.index,
                              apps: root.apps.map(function(a) { return a.name + " (" + a.windows.length + ")" }) })
    }
  }
}
