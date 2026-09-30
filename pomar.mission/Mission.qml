import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "shared"
import "shared/Tokens.js" as Tokens
import "shared/Apps.js" as Apps
import "shared/I18n.js" as I18n
import "ExposeLayout.js" as ExposeLayout

// Mission Control e App Exposé.
//
// Tudo é guiado por `progress` (0 = desktop normal, 1 = janelas espalhadas).
// O gesto de três dedos manda deslocamentos ao vivo (mission:delta) e o
// progresso acompanha os dedos 1:1; ao soltar, termina abrindo ou voltando
// conforme a posição e a velocidade, como no macOS. Atalho e comando só
// animam o mesmo progresso.
Item {
  id: root

  property bool opened: false
  property string mode: ""              // "mission" ou "expose"
  property string exposeApp: ""
  property string exposeName: ""
  property real progress: 0
  property bool tracking: false
  property real accum: 0
  property real startProgress: 0
  property real velocity: 0
  property bool frozen: false
  property var snapshot: []
  property var snapshotMap: ({})
  property string wallpaper: ""
  property string selectedAddress: ""
  // O Hyprland não troca o foco enquanto este overlay segura o teclado; ao
  // escolher uma janela, o teclado é solto primeiro e o foco vem logo depois.
  property bool releasing: false
  property var pendingDispatches: []

  property bool dragging: false
  property string dragAddress: ""
  property real dragAspect: 1.6
  property real dragX: 0
  property real dragY: 0
  property int dropWorkspace: 0

  readonly property real gestureDistance: 260
  readonly property bool dark: Tokens.isDark(Color.background)
  readonly property string lang: I18n.resolve(settings.get("language", "auto"), Quickshell.env("LANG"))
  readonly property bool usable: settings.active && settings.get("mission.enabled", true)
  readonly property var clients: hypr
  readonly property var workspaces: hypr.workspaces
  readonly property var webIndex: Apps.webappIndex(DesktopEntries.applications.values)
  readonly property string minimizedWorkspace: hypr.minimizedWorkspace

  PomarSettings { id: settings }
  PomarEvents {
    id: events
    onCommand: function(target, verb, arg) { root.handle(target, verb, arg) }
  }
  HyprClients {
    id: hypr
    onSerialChanged: root.takeSnapshot()
  }

  Process {
    id: wallpaperProc
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector { onStreamFinished: root.wallpaper = text.trim() }
  }

  Variants {
    id: screens
    model: Quickshell.screens
    delegate: MissionScreen {
      mission: root
    }
  }

  // ------------------------------------------------------------ dados
  function takeSnapshot() {
    if (root.frozen) return
    root.snapshot = hypr.allClients
    root.snapshotMap = hypr.byAddress
  }

  function monitorByName(name) {
    var list = hypr.monitors
    for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
    return null
  }

  function focusedMonitor() {
    var list = hypr.monitors
    for (var i = 0; i < list.length; i++) if (list[i].focused) return list[i]
    return list.length ? list[0] : null
  }

  function focusedWorkspaceId() {
    var mon = focusedMonitor()
    return mon && mon.activeWorkspace ? mon.activeWorkspace.id : 1
  }

  function nextFreeWorkspace() {
    var used = ({})
    for (var i = 0; i < hypr.workspaces.length; i++) used[hypr.workspaces[i].id] = true
    var id = 1
    while (used[id]) id++
    return id
  }

  function activeAppKey() {
    var active = ToplevelManager.activeToplevel
    var cls = active ? active.appId : ""
    return cls ? Apps.appKey(DesktopEntries, cls, root.webIndex) : ""
  }

  function appName(key) {
    return Apps.displayName(Apps.entryFor(DesktopEntries, key), key)
  }

  // ------------------------------------------------------------ abrir e fechar
  function prepare() {
    root.frozen = false
    hypr.refreshNow()
    root.takeSnapshot()
    wallpaperProc.running = true
  }

  function begin(newMode, app) {
    if (!root.usable) return false
    if (!root.opened) root.prepare()
    root.mode = newMode
    root.exposeApp = newMode === "expose" ? String(app || "") : ""
    root.exposeName = root.exposeApp ? root.appName(root.exposeApp) : ""
    root.selectedAddress = ""
    root.opened = true
    events.send("overlay", "opened", "mission")
    return true
  }

  function animateTo(value) {
    settle.stop()
    settle.from = root.progress
    settle.to = value
    settle.duration = Math.round(Tokens.lerp(140, 380, Math.abs(value - root.progress)))
    settle.start()
  }

  function finishClose() {
    settle.stop()
    root.opened = false
    root.mode = ""
    root.exposeApp = ""
    root.progress = 0
    root.frozen = false
    root.dragging = false
    root.selectedAddress = ""
    root.releasing = false
  }

  function dispatchAfterRelease(list) {
    root.releasing = true
    root.pendingDispatches = list
    releaseTimer.restart()
  }

  Timer {
    id: releaseTimer
    interval: 45
    onTriggered: {
      var list = root.pendingDispatches
      root.pendingDispatches = []
      for (var i = 0; i < list.length; i++) events.dispatch(list[i])
    }
  }

  // Contrato do Omarchy: summon/hide/toggle pelo shell também funcionam.
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (error) {}
    var wanted = payload.mode === "expose" ? "expose" : "mission"
    var app = wanted === "expose" ? (payload.app || root.activeAppKey()) : ""
    if (wanted === "expose" && !app) return
    if (root.begin(wanted, app)) root.animateTo(1)
  }

  function close() {
    if (root.opened) root.animateTo(0)
  }

  function toggle() {
    if (root.opened && root.progress > 0.5) root.close()
    else root.open("{}")
  }

  NumberAnimation {
    id: settle
    target: root
    property: "progress"
    easing.type: Easing.OutCubic
    onFinished: if (root.progress <= 0.001 && !root.tracking) root.finishClose()
  }

  // ------------------------------------------------------------ gesto ao vivo
  function gestureBegin() {
    root.tracking = true
    root.accum = 0
    root.velocity = 0
    settle.stop()
    root.startProgress = root.opened ? root.progress : 0
    if (!root.opened) root.mode = ""
  }

  function gestureDelta(dy) {
    if (!root.tracking) return
    root.accum += dy
    root.velocity = root.velocity * 0.55 + dy * 0.45
    if (!root.opened) {
      if (root.accum <= -6) {
        if (!root.begin("mission", "")) { root.tracking = false; return }
      } else if (root.accum >= 6) {
        var app = root.activeAppKey()
        if (!app || !root.begin("expose", app)) { root.tracking = false; return }
      } else {
        return
      }
    }
    var delta = root.accum / root.gestureDistance
    var value = root.mode === "expose" ? root.startProgress + delta : root.startProgress - delta
    root.progress = Tokens.clamp(value, 0, 1)
  }

  function gestureEnd(cancelled) {
    if (!root.tracking) return
    root.tracking = false
    if (!root.opened) return
    if (cancelled) {
      root.animateTo(root.startProgress >= 0.5 ? 1 : 0)
      return
    }
    // Positivo = no sentido de abrir o modo atual. "Arremesso" (dedos rápidos)
    // decide sozinho, mas só depois de um deslocamento mínimo: um esbarrão
    // não fecha nem abre nada.
    var towardOpen = root.mode === "expose" ? root.velocity : -root.velocity
    var travelled = Math.abs(root.accum) >= 24
    var target
    if (travelled && towardOpen > 3) target = 1
    else if (travelled && towardOpen < -3) target = 0
    else if (root.startProgress >= 0.5) target = root.progress > 0.7 ? 1 : 0
    else target = root.progress > 0.3 ? 1 : 0
    root.animateTo(target)
  }

  function handle(target, verb, arg) {
    if (target === "overlay") {
      if (verb === "opened" && arg !== "mission" && root.opened) root.finishClose()
      return
    }
    if (target !== "mission") return
    if (verb === "toggle") root.toggle()
    else if (verb === "open") root.open("{}")
    else if (verb === "close") root.close()
    else if (verb === "expose") {
      if (root.opened && root.mode === "expose") { root.close(); return }
      var app = arg ? Apps.stripDesktop(arg) : root.activeAppKey()
      if (app) root.open(JSON.stringify({ mode: "expose", app: app }))
    }
    else if (verb === "begin") root.gestureBegin()
    else if (verb === "delta") root.gestureDelta(Number(arg) || 0)
    else if (verb === "end") root.gestureEnd(arg === "1")
  }

  // ------------------------------------------------------------ ações
  function addressExpr(address) {
    return '"address:' + String(address).replace(/[^0-9a-fx]/gi, "") + '"'
  }

  function activate(client) {
    if (!client) return
    root.frozen = true
    root.selectedAddress = client.address
    var list = []
    if (hypr.isMinimized(client)) {
      list.push('hl.dsp.window.move({ window = ' + addressExpr(client.address)
        + ', workspace = "' + focusedWorkspaceId() + '", follow = true })')
    }
    list.push('hl.dsp.focus({ window = ' + addressExpr(client.address) + ' })')
    root.dispatchAfterRelease(list)
    root.animateTo(0)
  }

  function closeWindow(client) {
    if (!client) return
    events.dispatch('hl.dsp.window.close({ window = ' + addressExpr(client.address) + ' })')
    hypr.refresh()
  }

  function moveToWorkspace(client, workspaceId) {
    if (!client || !workspaceId) return
    events.dispatch('hl.dsp.window.move({ window = ' + addressExpr(client.address)
      + ', workspace = "' + workspaceId + '", follow = false })')
    hypr.refresh()
  }

  function goToWorkspace(workspaceId) {
    root.dispatchAfterRelease(['hl.dsp.focus({ workspace = "' + workspaceId + '" })'])
    root.animateTo(0)
  }

  function startDrag(client, x, y) {
    root.dragAddress = client.address
    root.dragAspect = client.size[1] > 0 ? client.size[0] / client.size[1] : 1.6
    root.dragX = x
    root.dragY = y
    root.dropWorkspace = 0
    root.dragging = true
  }

  function moveDrag(x, y, workspaceId) {
    root.dragX = x
    root.dragY = y
    root.dropWorkspace = workspaceId
  }

  function finishDrag(workspaceId) {
    var client = root.snapshotMap[root.dragAddress]
    root.dragging = false
    if (!client) return
    if (workspaceId === -1) root.moveToWorkspace(client, root.nextFreeWorkspace())
    else if (workspaceId > 0) root.moveToWorkspace(client, workspaceId)
    root.dragAddress = ""
  }

  // Setas escolhem, ENTER abre, ESC fecha, 1–9 vão para a mesa.
  function handleKey(event, screen) {
    var key = event.key
    if (key === Qt.Key_Escape) { root.close(); return true }
    if (key >= Qt.Key_1 && key <= Qt.Key_9) { root.goToWorkspace(key - Qt.Key_0); return true }
    var list = screen.windowList
    if (!list.length) return false
    var index = -1
    for (var i = 0; i < list.length; i++) if (list[i].address === root.selectedAddress) index = i
    if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
      root.activate(list[index >= 0 ? index : 0])
      return true
    }
    var direction = key === Qt.Key_Left ? "left" : key === Qt.Key_Right ? "right"
                  : key === Qt.Key_Up ? "up" : key === Qt.Key_Down ? "down" : ""
    if (key === Qt.Key_Tab) {
      root.selectedAddress = list[(index + 1) % list.length].address
      return true
    }
    if (!direction) return false
    var next = index < 0 ? 0 : ExposeLayout.neighbor(screen.targets, index, direction)
    root.selectedAddress = list[next].address
    return true
  }

  IpcHandler {
    target: "pomar-mission-test"
    enabled: Quickshell.env("POMAR_TEST") === "1"
    function state(): string {
      return JSON.stringify({ opened: root.opened, mode: root.mode, progress: root.progress,
                              windows: root.snapshot.length, selected: root.selectedAddress,
                              exposeApp: root.exposeApp })
    }
    function progressTo(value: string): void { if (!root.opened) root.begin("mission", ""); root.progress = Number(value) }
    function activateFirst(): void {
      var mon = root.focusedMonitor()
      for (var i = 0; i < root.snapshot.length; i++) {
        var c = root.snapshot[i]
        if (mon && c.monitor === mon.id && c.workspace && c.workspace.id === mon.activeWorkspace.id) { root.activate(c); return }
      }
    }
    function activate(address: string): void {
      var c = root.snapshotMap[hypr.normalizeAddress(address)]
      if (c) root.activate(c)
    }
    // Onde fica o X da miniatura `index` (na primeira tela), em coordenadas da
    // tela, e se ele está à vista: para o teste clicar nele de verdade.
    function closeButton(index: string): string {
      var screen = screens.instances.length ? screens.instances[0] : null
      var info = screen ? screen.closeButtonAt(Number(index)) : null
      return JSON.stringify(info)
    }
    function dragFirstTo(workspace: string): void {
      var c = root.snapshot.length ? root.snapshot[0] : null
      if (c) root.moveToWorkspace(c, Number(workspace))
    }
  }
}
