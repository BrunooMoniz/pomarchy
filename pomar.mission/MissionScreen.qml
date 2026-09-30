import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "shared"
import "shared/Tokens.js" as Tokens
import "shared/Apps.js" as Apps
import "shared/I18n.js" as I18n
import "Strings.js" as Strings
import "ExposeLayout.js" as ExposeLayout

// Mission Control num monitor. A janela respeita as zonas reservadas (barra de
// menus em cima, Dock embaixo), que continuam visíveis como no macOS; por isso
// tudo aqui é desenhado com o deslocamento `origin` dessas zonas.
PanelWindow {
  id: win

  required property var modelData
  property var mission: null

  screen: modelData
  readonly property var mon: mission ? mission.monitorByName(modelData.name) : null
  readonly property bool focusedScreen: !!mon && mon.focused === true
  readonly property bool shown: !!mission && mission.opened && (mission.mode === "mission" || focusedScreen)
  readonly property real originX: mon && mon.reserved ? mon.reserved[0] : 0
  readonly property real originY: mon && mon.reserved ? mon.reserved[1] : 0
  readonly property real monX: mon ? mon.x : 0
  readonly property real monY: mon ? mon.y : 0
  readonly property real monW: modelData.width
  readonly property real monH: modelData.height
  readonly property real p: mission ? mission.progress : 0
  readonly property bool dark: mission ? mission.dark : true
  readonly property bool missionMode: !!mission && mission.mode === "mission"
  readonly property int activeWorkspace: mon && mon.activeWorkspace ? mon.activeWorkspace.id : 1

  visible: shown
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "pomar-mission"
  WlrLayershell.keyboardFocus: shown && focusedScreen && !mission.releasing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  // ------------------------------------------------------------ modelo
  function belongs(c) {
    if (!c || !mon) return false
    if (mission.mode === "expose") {
      if (!focusedScreen) return false
      var wsName = c.workspace ? String(c.workspace.name || "") : ""
      var minimized = wsName === mission.minimizedWorkspace
      if (wsName.indexOf("special:") === 0 && !minimized) return false
      return Apps.appKey(DesktopEntries, c["class"] || c.initialClass, mission.webIndex) === mission.exposeApp
    }
    return c.monitor === mon.id && c.workspace && c.workspace.id === activeWorkspace
  }

  // Fechado, nada é capturado: a lista fica vazia e as miniaturas somem.
  readonly property var windowList: {
    var out = []
    if (!shown) return out
    var list = mission ? mission.snapshot : []
    for (var i = 0; i < list.length; i++) if (belongs(list[i])) out.push(list[i])
    return out
  }

  // Em coordenadas desta janela (camada pomar-mission); o teste soma a posição
  // da camada, que o Hyprland informa.
  function closeButtonAt(index) {
    var thumb = thumbs.itemAt(index)
    return thumb ? thumb.closeInfo() : null
  }

  function localRect(c) {
    return { x: c.at[0] - monX - originX, y: c.at[1] - monY - originY, w: c.size[0], h: c.size[1] }
  }

  readonly property real spacesHeight: missionMode ? Math.round(Tokens.clamp(monH * 0.15, 120, 176)) : 0
  readonly property var area: {
    var top = missionMode ? spacesHeight + 36 : 72
    return { x: 56, y: top, w: Math.max(100, width - 112), h: Math.max(100, height - top - 64) }
  }

  readonly property var targets: {
    var rects = []
    for (var i = 0; i < windowList.length; i++) rects.push(localRect(windowList[i]))
    return ExposeLayout.layout(rects, area, { gap: 36, maxScale: 0.88 })
  }

  function targetFor(address) {
    for (var i = 0; i < windowList.length; i++) if (windowList[i].address === address) return targets[i]
    return null
  }

  function onVisibleWorkspace(c) {
    return !!c && !!mon && c.monitor === mon.id && c.workspace && c.workspace.id === activeWorkspace
  }

  readonly property var workspaceList: {
    if (!mission || !mon || !shown || !missionMode) return []
    var list = []
    var all = mission.workspaces
    for (var i = 0; i < all.length; i++) {
      var ws = all[i]
      if (ws.id > 0 && ws.monitor === mon.name) list.push(ws)
    }
    return list
  }

  function windowsOn(workspaceId) {
    var out = []
    var list = mission ? mission.snapshot : []
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (c.workspace && c.workspace.id === workspaceId) out.push(c)
    }
    return out
  }

  function workspaceLabel(ws) {
    var name = String(ws.name || ws.id)
    return String(Number(name)) === name ? I18n.tr(Strings.TABLE, "desktop", mission.lang, name) : name
  }

  // Pronto = toda miniatura visível já tem imagem (ou passou o tempo-limite).
  // Até lá o fundo fica transparente e as janelas de verdade aparecem; depois o
  // fundo opaco entra sem piscar, porque as miniaturas cobrem as janelas.
  property bool primed: false
  function checkPrimed() {
    if (primed || !shown) return
    for (var i = 0; i < thumbs.count; i++) {
      var item = thumbs.itemAt(i)
      if (item && !item.ready) return
    }
    primed = true
  }
  onShownChanged: {
    primed = false
    if (shown) { primeTimeout.restart(); Qt.callLater(checkPrimed) }
  }
  Timer { id: primeTimeout; interval: 140; onTriggered: win.primed = true }
  Timer { interval: 16; repeat: true; running: win.shown && !win.primed; onTriggered: win.checkPrimed() }

  // ------------------------------------------------------------ fundo
  // Papel de parede opaco: esconde as janelas de verdade, que ficam paradas
  // atrás; as miniaturas assumem o lugar delas.
  Item {
    id: backdrop
    anchors.fill: parent
    clip: true
    opacity: win.primed ? 1 : 0
    BackgroundMedia {
      x: -win.originX
      y: -win.originY
      width: win.monW
      height: win.monH
      path: win.mission ? win.mission.wallpaper : ""
      playbackEnabled: win.shown
    }
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, (win.dark ? 0.32 : 0.22) * win.p)
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: win.mission.close()
  }

  // ------------------------------------------------------------ mesas
  Item {
    id: spaces
    visible: win.missionMode
    width: parent.width
    height: win.spacesHeight
    y: Tokens.lerp(-height, 14, win.p)
    opacity: win.p
    z: 5

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: -14
      color: Qt.rgba(0, 0, 0, win.dark ? 0.22 : 0.12)
    }

    Row {
      id: spaceRow
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 4
      spacing: 22
      height: parent.height - 28

      Repeater {
        model: win.workspaceList
        delegate: SpaceThumb {
          required property var modelData
          height: spaceRow.height
          workspace: modelData
          windows: win.windowsOn(modelData.id)
          clients: win.mission.clients
          monitorWidth: win.monW
          monitorHeight: win.monH
          monitorX: win.monX
          monitorY: win.monY
          wallpaper: win.mission.wallpaper
          current: modelData.id === win.activeWorkspace
          dropTarget: win.mission.dragging && win.mission.dropWorkspace === modelData.id
          dark: win.dark
          accent: Color.accent
          label: win.workspaceLabel(modelData)
          onClicked: win.mission.goToWorkspace(modelData.id)
        }
      }

      SpaceThumb {
        id: newSpace
        isNew: true
        height: spaceRow.height
        width: Math.round((spaceRow.height - 24) * 0.62)
        dark: win.dark
        accent: Color.accent
        label: I18n.tr(Strings.TABLE, "newDesktop", win.mission.lang)
        dropTarget: win.mission.dragging && win.mission.dropWorkspace === -1
        onClicked: win.mission.goToWorkspace(win.mission.nextFreeWorkspace())
      }
    }
  }

  function workspaceAt(sceneX, sceneY) {
    for (var i = 0; i < spaceRow.children.length; i++) {
      var child = spaceRow.children[i]
      if (child && child.hit && child.hit(sceneX, sceneY)) return child.isNew ? -1 : child.workspace.id
    }
    return 0
  }

  // ------------------------------------------------------------ janelas
  Item {
    id: stage
    anchors.fill: parent
    z: 3

    Repeater {
      id: thumbs
      model: ScriptModel { values: win.windowList; objectProp: "address" }
      delegate: WindowThumb {
        id: thumb
        required property var modelData
        readonly property var info: win.mission.snapshotMap[modelData.address] || modelData
        client: info
        webIndex: win.mission.webIndex
        toplevel: win.mission.clients.toplevelFor(modelData.address)
        source: win.localRect(info)
        target: win.targetFor(modelData.address) || win.localRect(info)
        fadeFromTarget: !win.onVisibleWorkspace(info)
        progress: win.p
        dark: win.dark
        accent: Color.accent
        lang: win.mission.lang
        selected: win.mission.selectedAddress === modelData.address
        live: win.shown
        primed: win.primed
        z: (selected ? 2000 : 1000) - (info.focusHistoryID || 0)
        visible: !(win.mission.dragging && win.mission.dragAddress === modelData.address)
        onHoverChanged: function(isHovered) { if (isHovered) win.mission.selectedAddress = modelData.address }
        onActivated: win.mission.activate(info)
        onCloseRequested: win.mission.closeWindow(info)
        onDragStarted: function(x, y) { win.mission.startDrag(info, x, y) }
        onDragMoved: function(x, y) { win.mission.moveDrag(x, y, win.workspaceAt(x, y)) }
        onDragFinished: function(x, y) { win.mission.finishDrag(win.workspaceAt(x, y)) }
      }
    }

    // Janela sendo arrastada para outra mesa: segue o ponteiro, menor.
    Item {
      id: ghost
      visible: win.mission.dragging && win.focusedScreen
      width: 260
      height: win.mission.dragAspect > 0 ? width / win.mission.dragAspect : 160
      x: win.mission.dragX - width / 2
      y: win.mission.dragY - height / 2
      z: 5000
      opacity: 0.92
      RectangularShadow { anchors.fill: parent; radius: 10; blur: 24; offset.y: 8; color: Qt.rgba(0, 0, 0, 0.45) }
      ScreencopyView {
        anchors.fill: parent
        captureSource: win.mission.dragAddress ? win.mission.clients.toplevelFor(win.mission.dragAddress) : null
        live: true
      }
    }

    Text {
      anchors.centerIn: parent
      visible: win.windowList.length === 0 && win.p > 0.5
      opacity: win.p
      text: win.mission.mode === "expose"
            ? I18n.tr(Strings.TABLE, "noAppWindows", win.mission.lang, win.mission.exposeName)
            : I18n.tr(Strings.TABLE, "noWindows", win.mission.lang)
      color: "white"
      font.pixelSize: 20
      font.weight: Font.Medium
      style: Text.Raised
      styleColor: Qt.rgba(0, 0, 0, 0.4)
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 26
      visible: win.mission.mode === "expose" && win.windowList.length > 0
      opacity: win.p
      text: I18n.tr(Strings.TABLE, "allWindowsOf", win.mission.lang, win.mission.exposeName)
      color: "white"
      font.pixelSize: 22
      font.weight: Font.DemiBold
      style: Text.Raised
      styleColor: Qt.rgba(0, 0, 0, 0.4)
    }
  }

  // ------------------------------------------------------------ teclado
  FocusScope {
    id: keys
    anchors.fill: parent
    focus: win.shown && win.focusedScreen
    Keys.onPressed: function(event) {
      if (win.mission.handleKey(event, win)) event.accepted = true
    }
  }

  Connections {
    target: win
    function onShownChanged() { if (win.shown && win.focusedScreen) Qt.callLater(function() { keys.forceActiveFocus() }) }
  }
}
