import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Os botões do Mac (fechar, minimizar, zoom) no alto de cada janela lado a lado
// da mesa à vista. O Hyprland não desenha barra de título: o pomar.lua abre um
// espaço em cima de cada janela e os botões moram nele, sem cobrir nada do app.
Scope {
  id: controls

  property var hypr: null
  property bool enabled: false
  property bool dark: false
  // Mesmo valor do pomar.lua (M.TITLE_GAP) e do border_size.
  readonly property int gap: 28
  readonly property int border: 1

  signal closeRequested(string address)
  signal minimizeRequested(string address)
  signal zoomRequested(string address)

  readonly property string activeAddress: hypr && Hyprland.activeToplevel
    ? hypr.normalizeAddress(Hyprland.activeToplevel.address) : ""

  // Janelas agrupadas em abas: o Hyprland desenha a barra de abas logo acima
  // delas, no espaço dos botões. Os botões sobem para cima da barra de abas
  // (como no Mac, acima das abas), com a altura que ela ocupa na config.
  property int groupReserve: 28
  property bool groupStacked: false
  // group:groupbar:disable_when_only: grupo de uma aba só sem barra de abas.
  property bool groupHideWhenOnly: false

  function readGroupbar(text) {
    var values = ({})
    var pattern = /"option"\s*:\s*"group:groupbar:(\w+)"\s*,\s*"(?:int|bool)"\s*:\s*(true|false|-?\d+)/g
    var match
    while ((match = pattern.exec(text)) !== null)
      values[match[1]] = match[2] === "true" ? 1 : match[2] === "false" ? 0 : Number(match[2])
    if (values.height === undefined) return
    controls.groupStacked = values.stacked === 1
    controls.groupHideWhenOnly = values.disable_when_only === 1
    controls.groupReserve = values.enabled === 0 ? 0
      : values.height + (values.indicator_height || 0) + (values.indicator_gap || 0) + (values.gaps_out || 0)
  }

  Process {
    id: groupbarProc
    command: ["sh", "-c", "for o in enabled height indicator_height indicator_gap gaps_out stacked disable_when_only; do hyprctl -j getoption group:groupbar:$o; done"]
    stdout: StdioCollector { onStreamFinished: controls.readGroupbar(text) }
  }

  Component.onCompleted: groupbarProc.running = true

  // Uma aba só já é grupo: o Hyprland desenha a barra de abas do mesmo jeito,
  // a não ser com group:groupbar:disable_when_only.
  function grouped(c) {
    if (!c || !Array.isArray(c.grouped)) return false
    return c.grouped.length > 1 || (c.grouped.length === 1 && !groupHideWhenOnly)
  }

  // Onde começa, em cima, o que é da janela (a barra de abas, se agrupada).
  function topOf(c) { return c.at[1] - (grouped(c) ? groupReserve : 0) }

  // Canto de cima da superfície dos botões, em coordenadas do Hyprland.
  function origin(c) { return [c.at[0] + 8 - 6, topOf(c) - border - gap / 2 - 12] }

  // Antes de agir, confere numa consulta nova se a janela ainda está onde os
  // botões estão: trocar janelas de lugar pelo teclado não gera evento, e um
  // clique nos botões de antes fecharia a janela errada.
  property var pending: null

  function act(kind, address, gx, gy) {
    if (verifyProc.running) return
    controls.pending = { kind: kind, address: address, gx: gx, gy: gy }
    verifyProc.running = true
  }

  function verified(text) {
    var request = controls.pending
    controls.pending = null
    if (!request) return
    var list = []
    try { list = JSON.parse(text) } catch (error) { list = [] }
    var c = null
    for (var i = 0; i < list.length; i++) {
      if (hypr.normalizeAddress(list[i].address) === request.address) c = list[i]
    }
    var here = c ? origin(c) : null
    // As abas de um grupo dividem o mesmo lugar: só a aba à vista (a de foco
    // mais recente do grupo) recebe o clique, senão fecharia uma aba escondida.
    var visibleTab = c
    if (c && Array.isArray(c.grouped) && c.grouped.length > 1) {
      var members = c.grouped.map(function(a) { return hypr.normalizeAddress(a) })
      for (var j = 0; j < list.length; j++) {
        var other = list[j]
        if (members.indexOf(hypr.normalizeAddress(other.address)) !== -1
            && (other.focusHistoryID || 0) < (visibleTab.focusHistoryID || 0)) visibleTab = other
      }
    }
    if (!here || visibleTab !== c || Math.abs(here[0] - request.gx) > 2 || Math.abs(here[1] - request.gy) > 2) {
      controls.unsettle()  // a janela mudou de lugar: os botões voltam no lugar novo
      if (controls.hypr) controls.hypr.refreshNow()
      return
    }
    if (request.kind === "close") controls.closeRequested(request.address)
    else if (request.kind === "minimize") controls.minimizeRequested(request.address)
    else controls.zoomRequested(request.address)
  }

  Process {
    id: verifyProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector { onStreamFinished: controls.verified(text) }
  }

  // As janelas se mexem por uns 400 ms depois de abrir, fechar, trocar de mesa
  // ou mudar de tamanho: os botões somem nesse meio-tempo e voltam já no lugar.
  property bool settled: true
  property var lastGeometry: ({})

  function unsettle() {
    controls.settled = false
    settle.restart()
  }

  Timer {
    id: settle
    interval: 450
    onTriggered: {
      if (controls.hypr) controls.hypr.refreshNow()
      reveal.restart()
    }
  }
  Timer {
    id: reveal
    interval: 90
    onTriggered: controls.settled = true
  }
  // Redimensionar não gera evento no Hyprland; confere de tempos em tempos.
  Timer {
    interval: 700
    repeat: true
    running: controls.enabled
    onTriggered: if (controls.hypr) controls.hypr.refreshNow()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event.name || "")
      if (name === "configreloaded" && !groupbarProc.running) groupbarProc.running = true
      if (controls.hypr && controls.hypr.refreshEvents[name] === true) controls.unsettle()
    }
  }

  Connections {
    target: controls.hypr
    function onSerialChanged() {
      var list = controls.hypr.clients
      var now = ({})
      var moved = false
      for (var i = 0; i < list.length; i++) {
        var c = list[i]
        var key = [c.at[0], c.at[1], c.size[0], c.size[1]].join(",")
        now[c.address] = key
        if (controls.lastGeometry[c.address] !== undefined && controls.lastGeometry[c.address] !== key) moved = true
      }
      controls.lastGeometry = now
      if (moved && controls.settled) controls.unsettle()
    }
  }

  // Centro de cada botão, em coordenadas do Hyprland (para os testes clicarem).
  function describe() {
    var out = []
    var screens = Quickshell.screens
    for (var s = 0; s < screens.length; s++) {
      var list = windowsOn(monitorFor(screens[s]))
      for (var i = 0; i < list.length; i++) {
        var c = list[i]
        var place = origin(c)
        var x = place[0] + 6 + 6
        var y = place[1] + 12
        out.push({ address: c.address, origin: place, close: [x, y], minimize: [x + 20, y], zoom: [x + 40, y] })
      }
    }
    return { enabled: enabled, settled: settled, windows: out }
  }

  function monitorFor(screen) {
    var list = hypr ? hypr.monitors : []
    for (var i = 0; i < list.length; i++) {
      if (screen && list[i].name === screen.name) return list[i]
    }
    return null
  }

  // Janelas lado a lado da mesa à vista neste monitor. Flutuantes e em tela
  // cheia ficam de fora (não há espaço em cima delas). A ampliada pelo botão
  // verde guarda o espaço, e as que ficaram atrás dela não mostram botões.
  function windowsOn(monitor) {
    if (!monitor || !hypr) return []
    if (monitor.specialWorkspace && monitor.specialWorkspace.id !== 0) return []
    var active = monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    var tiled = []
    var zoomed = []
    var groupsSeen = ({})
    // Em ordem de uso: de cada grupo fica só a aba à vista (a de foco mais recente).
    var list = hypr.clients
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (c.monitor !== monitor.id || !c.workspace || c.workspace.id !== active) continue
      if (c.floating || c.hidden) continue
      if (grouped(c)) {
        var key = c.grouped.slice().sort().join(",")
        if (groupsSeen[key] || groupStacked) continue
        groupsSeen[key] = true
      }
      var mode = c.fullscreen || 0
      if (mode === 1) zoomed.push(c)
      else if (mode === 0) tiled.push(c)
      else return []
    }
    return zoomed.length ? zoomed : tiled
  }

  // Janelas com botões à vista, em todos os monitores.
  readonly property var shownWindows: {
    var out = []
    var screens = Quickshell.screens
    for (var s = 0; s < screens.length; s++) out = out.concat(windowsOn(monitorFor(screens[s])))
    return out
  }
  readonly property var shownAddresses: shownWindows.map(function(c) { return c.address })

  function screenFor(client) {
    var list = hypr && client ? hypr.monitors : []
    var name = ""
    for (var i = 0; i < list.length; i++) if (list[i].id === client.monitor) name = list[i].name
    var screens = Quickshell.screens
    for (var s = 0; s < screens.length; s++) if (screens[s].name === name) return screens[s]
    return null
  }

  // Uma janela flutuante por cima do lugar dos botões: eles somem (a camada dos
  // botões fica acima das janelas, senão apareceriam por cima dela).
  function covered(x, y, w, h, workspaceId) {
    var list = hypr ? hypr.clients : []
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (!c.floating || !c.workspace || c.workspace.id !== workspaceId) continue
      if (x < c.at[0] + c.size[0] && c.at[0] < x + w && y < c.at[1] + c.size[1] && c.at[1] < y + h) return true
    }
    return false
  }

  // Uma superfície pequena por janela, só do tamanho dos botões, acima das
  // janelas: o vão entre janelas lado a lado conta como delas para o mouse, então
  // numa camada de baixo o clique iria para a janela. Fora dos botões, nada muda.
  Variants {
    model: controls.enabled ? controls.shownAddresses : []

    delegate: PanelWindow {
      id: surface

      required property string modelData
      readonly property var client: controls.hypr ? controls.hypr.byAddress[modelData] || null : null
      readonly property var where: controls.screenFor(client)
      // Canto de cima da superfície em coordenadas do Hyprland.
      readonly property var place: client ? controls.origin(client) : [0, 0]
      readonly property int gx: place[0]
      readonly property int gy: place[1]
      readonly property bool hiddenBehind: client ? controls.covered(gx, gy, width, height, client.workspace.id) : true
      readonly property bool lit: modelData === controls.activeAddress || hover.hovered
      readonly property bool interactive: controls.settled && !hiddenBehind

      screen: where
      visible: client !== null && where !== null
      anchors { top: true; left: true }
      margins { top: gy - (where ? where.y : 0); left: gx - (where ? where.x : 0) }
      implicitWidth: 64
      implicitHeight: 24
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "pomar-window-controls"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Escondidos (janelas se mexendo ou flutuante por cima), não pegam clique.
      // Com uma janela flutuante por cima, o clique passa para ela. A área não
      // liga e desliga a cada reorganização: com o mouse parado, o Hyprland só
      // voltaria a entregar o clique aos botões depois de um movimento. Enquanto
      // as janelas se mexem (meio segundo), os botões só ignoram o clique.
      mask: Region { width: surface.hiddenBehind ? 0 : 64; height: surface.hiddenBehind ? 0 : 24 }

      Item {
        id: group
        x: 6
        y: 6
        width: 52
        height: 12
        opacity: controls.settled && !surface.hiddenBehind ? 1 : 0
        enabled: opacity > 0.99 && surface.interactive
        Behavior on opacity { NumberAnimation { duration: controls.settled ? 160 : 60 } }

        HoverHandler { id: hover }

        Row {
          spacing: 8
          TrafficDot {
            kind: "close"; lit: surface.lit; glyph: hover.hovered; dark: controls.dark
            onClicked: controls.act("close", surface.modelData, surface.gx, surface.gy)
          }
          TrafficDot {
            kind: "minimize"; lit: surface.lit; glyph: hover.hovered; dark: controls.dark
            onClicked: controls.act("minimize", surface.modelData, surface.gx, surface.gy)
          }
          TrafficDot {
            kind: "zoom"; lit: surface.lit; glyph: hover.hovered; dark: controls.dark
            onClicked: controls.act("zoom", surface.modelData, surface.gx, surface.gy)
          }
        }
      }
    }
  }
}
