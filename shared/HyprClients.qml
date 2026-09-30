import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Retrato das janelas do Hyprland (hyprctl -j clients / workspaces / monitors),
// com a ordem de uso recente (focusHistoryID) que o Dock, o Mission Control e
// o alternador de apps precisam. Atualiza sozinho a cada evento de janela e
// liga cada janela ao Toplevel do Wayland, que é o que o ScreencopyView captura.
Item {
  id: root

  // Janelas "de verdade": mapeadas, fora de mesas especiais.
  property var clients: []
  // Todas, inclusive minimizadas (mesa especial do Pomarchy) e scratchpad.
  property var allClients: []
  property var workspaces: []
  property var monitors: []
  property var byAddress: ({})
  property int serial: 0

  readonly property string minimizedWorkspace: "special:pomar-minimized"

  function normalizeAddress(address) {
    var text = String(address || "").toLowerCase()
    return text.indexOf("0x") === 0 ? text : "0x" + text
  }

  function toplevelFor(address) {
    var wanted = normalizeAddress(address)
    var list = Hyprland.toplevels.values || []
    for (var i = 0; i < list.length; i++) {
      if (normalizeAddress(list[i].address) === wanted) return list[i].wayland
    }
    return null
  }

  function isMinimized(client) {
    return !!client && client.workspace && client.workspace.name === root.minimizedWorkspace
  }

  function refresh() {
    refreshDebounce.restart()
  }

  // Pedido que chega com uma consulta em andamento não se perde: roda de novo
  // ao fim dela (senão vence o retrato de antes da mudança).
  property bool clientsAgain: false

  function refreshNow() {
    if (clientsProc.running) root.clientsAgain = true
    else clientsProc.running = true
    if (!workspacesProc.running) workspacesProc.running = true
    if (!monitorsProc.running) monitorsProc.running = true
  }

  function applyClients(text) {
    var parsed = []
    try { parsed = JSON.parse(text) } catch (error) { return }
    if (!Array.isArray(parsed)) return
    var all = []
    var visible = []
    var map = ({})
    for (var i = 0; i < parsed.length; i++) {
      var c = parsed[i]
      if (!c || c.mapped === false) continue
      c.address = root.normalizeAddress(c.address)
      all.push(c)
      map[c.address] = c
      var wsName = c.workspace ? String(c.workspace.name || "") : ""
      if (wsName.indexOf("special:") !== 0 && (c.workspace ? c.workspace.id : 0) > 0) visible.push(c)
    }
    var byRecent = function(a, b) { return (a.focusHistoryID || 0) - (b.focusHistoryID || 0) }
    all.sort(byRecent)
    visible.sort(byRecent)
    root.allClients = all
    root.clients = visible
    root.byAddress = map
    root.serial++
  }

  Timer {
    id: refreshDebounce
    interval: 40
    onTriggered: root.refreshNow()
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector { onStreamFinished: root.applyClients(text) }
    onRunningChanged: {
      if (!running && root.clientsAgain) {
        root.clientsAgain = false
        running = true
      }
    }
  }

  Process {
    id: workspacesProc
    command: ["hyprctl", "-j", "workspaces"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var list = JSON.parse(text)
          if (Array.isArray(list)) root.workspaces = list.sort(function(a, b) { return a.id - b.id })
        } catch (error) {}
      }
    }
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var list = JSON.parse(text)
          if (Array.isArray(list)) root.monitors = list
        } catch (error) {}
      }
    }
  }

  // Eventos que mudam o conjunto ou o lugar das janelas. Título e foco ficam de
  // fora de propósito: um terminal troca de título várias vezes por segundo, e
  // quem precisa da ordem de foco chama refreshNow() ao abrir.
  readonly property var refreshEvents: ({
    openwindow: true, closewindow: true, movewindow: true, movewindowv2: true,
    workspace: true, workspacev2: true, createworkspace: true, createworkspacev2: true,
    destroyworkspace: true, destroyworkspacev2: true, moveworkspace: true, moveworkspacev2: true,
    renameworkspace: true, activespecial: true, activespecialv2: true,
    monitoradded: true, monitoraddedv2: true, monitorremoved: true, monitorremovedv2: true,
    changefloatingmode: true, fullscreen: true, minimized: true, pin: true, urgent: true,
    configreloaded: true
  })

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.refreshEvents[String(event.name || "")] === true) root.refresh()
    }
  }

  Component.onCompleted: root.refreshNow()
}
