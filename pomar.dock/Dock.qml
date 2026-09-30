import QtQuick
import Qt.labs.folderlistmodel
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
import "DockModel.js" as DockModel
import "DockLayout.js" as DockLayout

// Dock do Pomarchy, como o do Mac: favoritos, apps abertos, janelas minimizadas e
// Lixeira num vidro no pé da tela, com ampliação, rótulo, menu de contexto,
// arrastar para organizar e ocultação automática. Um Dock só, no monitor com
// foco.
//
// Toda a entrada do mouse passa por uma área única (pointerPress/Move/
// Release), que sabe pelo layout qual item está sob o cursor. Os ganchos de
// teste chamam essas mesmas funções.
Item {
  id: root

  // ---------------------------------------------------------- contrato do shell
  // Painel keepLoaded: aparece sozinho com o tema Pomarchy ativo. O summon e o
  // hide do shell revelam e recolhem o Dock, como dock:show e dock:hide.
  readonly property bool opened: root.shown && root.revealed
  function open(payloadJson) { root.showDock() }
  function close() { root.conceal() }

  readonly property bool testMode: Quickshell.env("POMAR_TEST") === "1"
  readonly property bool dark: Tokens.isDark(Color.background)
  readonly property string fontFamily: Style.fontFamily
  readonly property string lang: I18n.resolve(settings.get("language", "auto"), Quickshell.env("LANG"))
  readonly property string home: Quickshell.env("HOME")

  function tr(key, value) {
    return value === undefined ? I18n.tr(Strings.STRINGS, key, root.lang) : I18n.tr(Strings.STRINGS, key, root.lang, value)
  }

  PomarSettings { id: settings }
  HyprClients { id: hypr }
  PomarEvents {
    id: events
    onCommand: function(target, verb, arg) {
      if (target === "dock" && settings.active) root.handleEvent(verb, arg)
    }
  }

  // ---------------------------------------------------------- ajustes
  readonly property bool shown: settings.active && settings.get("dock.enabled", true) === true
    && !root.fullscreenActive && root.dockScreen !== null
  readonly property int maxIconSize: Tokens.clamp(Math.round(Number(settings.get("dock.iconSize", 54)) || 54), 32, 96)
  readonly property bool magnifyEnabled: settings.get("dock.magnification", true) === true
  readonly property int magnifiedSetting: Tokens.clamp(Math.round(Number(settings.get("dock.magnifiedSize", 82)) || 82), 32, 160)
  readonly property bool autohide: settings.get("dock.autohide", false) === true
  readonly property bool showRunning: settings.get("dock.showRunning", true) === true
  readonly property bool showMinimized: settings.get("dock.showMinimized", true) === true
  readonly property bool showTrash: settings.get("dock.showTrash", true) === true
  readonly property var favorites: DockModel.normalizeFavorites(settings.get("dock.favorites", []))

  // ---------------------------------------------------------- medidas
  // Proporções do Dock do Mac, derivadas do tamanho do ícone.
  readonly property int gapSize: Math.max(4, Math.round(root.maxIconSize * 0.11))
  readonly property int padTop: Math.max(4, Math.round(root.maxIconSize * 0.11))
  readonly property int padBottom: Math.max(6, Math.round(root.maxIconSize * 0.15))
  readonly property int padSide: root.padTop + 2
  readonly property int sepWidth: Math.max(10, Math.round(root.maxIconSize * 0.3))
  readonly property int bottomMargin: 6
  readonly property int dotSize: Math.max(3, Math.round(root.maxIconSize * 0.075))
  readonly property int dotInset: Math.max(2, Math.round((root.padBottom - root.dotSize) / 2))
  readonly property int labelHeight: 24
  readonly property int labelGap: 10
  readonly property int labelMaxWidth: 400

  // Com muitos itens o ícone encolhe para o Dock caber na tela.
  readonly property int iconSize: {
    var icons = 0
    var separators = 0
    for (var i = 0; i < root.targetItems.length; i++) {
      if (root.targetItems[i].kind === "separator") separators++
      else icons++
    }
    var available = root.screenWidth - 48 - separators * root.sepWidth - 2 * root.padSide
    var fit = Math.floor(available / Math.max(1, icons) - root.gapSize)
    return Tokens.clamp(fit, 24, root.maxIconSize)
  }
  readonly property int magnifiedSize: root.magnifyEnabled ? Math.max(root.iconSize, root.magnifiedSetting) : root.iconSize
  readonly property int bounceHeight: Math.round(root.iconSize * 0.42)
  readonly property int bodyHeight: root.iconSize + root.padTop + root.padBottom
  readonly property int windowHeight: root.bottomMargin + root.bodyHeight
    + Math.max(root.magnifiedSize - root.iconSize + root.labelGap + root.labelHeight, root.bounceHeight) + 16
  readonly property int textureSize: Math.ceil(root.magnifiedSize * Math.max(1, dockWindow.devicePixelRatio || 1))
  readonly property string launchpadIcon: Qt.resolvedUrl("assets/launchpad.svg")

  // Recolhido, o corpo desce para baixo da borda (com a sombra junto).
  property real slide: root.revealed ? 0 : 1
  Behavior on slide { NumberAnimation { duration: Tokens.motion.base; easing.type: Easing.OutCubic } }
  readonly property real restBodyY: root.windowHeight - root.bottomMargin - root.bodyHeight
  readonly property real bodyY: root.restBodyY + root.slide * (root.bodyHeight + root.bottomMargin + 30)
  // Linha de base dos ícones: crescem e pulam para cima a partir dela.
  readonly property real baselineY: root.bodyY + root.bodyHeight - root.padBottom

  readonly property var dims: ({
    iconSize: root.iconSize,
    magnifiedSize: root.magnifiedSize,
    gap: root.gapSize,
    edge: root.padSide - root.gapSize / 2,
    sepWidth: root.sepWidth,
    centerX: root.screenWidth / 2,
    span: 3 * (root.iconSize + root.gapSize)
  })

  // ---------------------------------------------------------- monitor
  // Um Dock só, no monitor com foco. A troca espera o foco assentar e nunca
  // acontece com o mouse no Dock, menu aberto ou arrastando.
  property string screenName: ""
  // Medidas pela tela, não pela janela: desmapeada (tela cheia) a janela
  // perde a largura e o Dock voltaria encolhido.
  readonly property int screenWidth: root.dockScreen && root.dockScreen.width > 0 ? root.dockScreen.width : 1920
  readonly property var dockScreen: {
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) if (list[i].name === root.screenName) return list[i]
    return list.length > 0 ? list[0] : null
  }

  function followFocusedMonitor() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    if (!name || name === root.screenName) return
    if (root.pointerInside || root.menuOpen || root.dragActive) { screenFollow.restart(); return }
    root.screenName = name
  }

  Timer { id: screenFollow; interval: 350; onTriggered: root.followFocusedMonitor() }

  // Tela cheia de verdade (não "maximizada") na mesa visível do monitor do Dock.
  readonly property bool fullscreenActive: {
    var monitors = hypr.monitors || []
    var workspaceId = -1
    for (var i = 0; i < monitors.length; i++) {
      var m = monitors[i]
      if (m.name === root.screenName || (!root.screenName && m.focused)) workspaceId = m.activeWorkspace ? m.activeWorkspace.id : -1
    }
    if (workspaceId < 0) return false
    var list = hypr.allClients || []
    for (var j = 0; j < list.length; j++) {
      var c = list[j]
      if (!c.workspace || c.workspace.id !== workspaceId) continue
      if (c.fullscreen === true || (typeof c.fullscreen === "number" && (c.fullscreen & 2))) return true
    }
    return false
  }

  // ---------------------------------------------------------- itens
  property var itemData: ({})
  property var targetItems: []
  property var displayKeys: []
  property var displayItems: []
  property var runningOrder: []
  property var minimizedOrder: []
  property var webIndex: ({})
  // Sem animação de entrada enquanto o Dock monta pela primeira vez.
  property bool settled: false
  readonly property int clientSerial: hypr.serial
  property bool rebuildQueued: false

  function scheduleRebuild() {
    if (root.rebuildQueued) return
    root.rebuildQueued = true
    Qt.callLater(function() {
      root.rebuildQueued = false
      root.rebuild()
    })
  }

  function rebuildWebIndex() {
    root.webIndex = DockModel.webappIndex(DesktopEntries.applications.values)
    root.scheduleRebuild()
  }

  function appKeyForClient(client) {
    var cls = String(client["class"] || client.initialClass || "")
    return cls ? DockModel.appKey(DesktopEntries, root.webIndex, cls) : ""
  }

  function appItem(id, entry, group, favorite) {
    var windows = group ? group.windows : []
    var minimized = group ? group.minimized : []
    return {
      key: "app:" + id,
      kind: "app",
      id: id,
      favorite: favorite,
      entry: entry,
      name: Apps.displayName(entry, id),
      icon: Apps.iconSource(Quickshell, entry, id),
      windows: windows,
      minimized: minimized,
      running: windows.length + minimized.length > 0
    }
  }

  function rebuild() {
    var favs = root.favorites
    var favSet = ({})
    for (var f = 0; f < favs.length; f++) favSet[favs[f]] = true

    // Janelas agrupadas por app, já na ordem de uso recente.
    var groups = ({})
    var minimizedClients = []
    var list = hypr.allClients || []
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      var appId = root.appKeyForClient(c)
      if (!appId) continue
      var group = groups[appId] || (groups[appId] = { windows: [], minimized: [] })
      if (hypr.isMinimized(c)) {
        group.minimized.push(c)
        minimizedClients.push({ client: c, appId: appId })
      } else {
        group.windows.push(c)
      }
    }

    var items = []
    for (var j = 0; j < favs.length; j++) {
      var id = favs[j]
      if (id === DockModel.LAUNCHPAD) {
        items.push({ key: "app:" + id, kind: "launchpad", id: id, favorite: true, name: I18n.tr(Strings.STRINGS, "launchpad", root.lang),
                     icon: root.launchpadIcon, windows: [], minimized: [], running: false })
        continue
      }
      // Favorito de app desinstalado some do Dock (continua nos ajustes).
      var entry = DesktopEntries.byId(id) || null
      if (!entry && !groups[id]) continue
      items.push(root.appItem(id, entry, groups[id], true))
    }

    if (root.showRunning) {
      var running = []
      for (var key in groups) if (!favSet[key]) running.push(key)
      root.runningOrder = DockModel.stableOrder(root.runningOrder, running)
      for (var r = 0; r < root.runningOrder.length; r++) {
        var runningId = root.runningOrder[r]
        items.push(root.appItem(runningId, Apps.entryFor(DesktopEntries, runningId), groups[runningId], false))
      }
    }

    var minimizedItems = []
    if (root.showMinimized) {
      var byAddress = ({})
      var addresses = []
      for (var m = 0; m < minimizedClients.length; m++) {
        byAddress[minimizedClients[m].client.address] = minimizedClients[m]
        addresses.push(minimizedClients[m].client.address)
      }
      root.minimizedOrder = DockModel.stableOrder(root.minimizedOrder, addresses)
      for (var n = 0; n < root.minimizedOrder.length; n++) {
        var entryInfo = byAddress[root.minimizedOrder[n]]
        var appEntry = Apps.entryFor(DesktopEntries, entryInfo.appId)
        var title = String(entryInfo.client.title || "")
        minimizedItems.push({
          key: "min:" + entryInfo.client.address,
          kind: "minimized",
          id: entryInfo.appId,
          address: entryInfo.client.address,
          name: title || Apps.displayName(appEntry, entryInfo.appId),
          icon: Apps.iconSource(Quickshell, appEntry, entryInfo.appId)
        })
      }
    }

    if (root.showTrash || minimizedItems.length > 0) items.push({ key: "separator", kind: "separator", name: "" })
    items = items.concat(minimizedItems)
    if (root.showTrash) items.push({ key: "trash", kind: "trash", name: I18n.tr(Strings.STRINGS, "trash", root.lang) })

    // Quem está saindo guarda os dados até a animação de saída terminar.
    var data = ({})
    for (var d = 0; d < root.displayKeys.length; d++) {
      var shownKey = root.displayKeys[d]
      if (root.itemData[shownKey]) data[shownKey] = root.itemData[shownKey]
    }
    for (var t = 0; t < items.length; t++) data[items[t].key] = items[t]
    root.itemData = data
    root.targetItems = items
    root.syncDisplay()
    root.checkLaunches()
    if (root.menuOpen && root.menuRefreshPending && root.menuKey !== "") {
      root.menuRefreshPending = false
      if (root.itemData[root.menuKey]) menu.rows = root.itemRows(root.itemData[root.menuKey])
    }
  }

  // ---------------------------------------------------------- animação dos itens
  // Presença (0 a 1) de cada item e dos vãos do arrasto, animada por quadro
  // só enquanto algo se move; parado, nada roda.
  property var anim: ({ presence: ({}), tweens: ({}), gaps: ({}), gapTweens: ({}) })
  property int animRev: 0
  property bool animating: false

  function targetSet() {
    var set = ({})
    for (var i = 0; i < root.targetItems.length; i++) set[root.targetItems[i].key] = true
    return set
  }

  function syncDisplay() {
    var target = []
    for (var i = 0; i < root.targetItems.length; i++) target.push(root.targetItems[i].key)
    var merged = DockModel.mergeDisplay(root.displayKeys, target)
    var inTarget = root.targetSet()
    var presence = root.anim.presence
    for (var m = 0; m < merged.length; m++) {
      var key = merged[m]
      if (!(key in presence)) presence[key] = root.settled && root.shown ? 0 : 1
      root.tween(root.anim.presence, root.anim.tweens, key, inTarget[key] ? 1 : 0)
    }
    root.setDisplay(merged)
    root.dropGone()
    root.animRev++
  }

  function setDisplay(keys) {
    root.displayKeys = keys
    var values = []
    for (var i = 0; i < keys.length; i++) values.push({ key: keys[i] })
    root.displayItems = values
  }

  function tween(values, tweens, key, to) {
    var current = values[key] === undefined ? 0 : values[key]
    var running = tweens[key]
    if (running ? running.to === to : current === to) return
    if (!root.settled || !root.shown) {
      values[key] = to
      delete tweens[key]
      return
    }
    tweens[key] = { from: current, to: to, start: Date.now(), duration: Tokens.motion.base }
    root.animating = true
  }

  function advance(values, tweens, now) {
    var busy = false
    for (var key in tweens) {
      var tw = tweens[key]
      var p = Math.min(1, (now - tw.start) / tw.duration)
      var eased = 1 - Math.pow(1 - p, 3)
      values[key] = tw.from + (tw.to - tw.from) * eased
      if (p >= 1) delete tweens[key]
      else busy = true
    }
    return busy
  }

  function dropGone() {
    var inTarget = root.targetSet()
    var keep = []
    var changed = false
    for (var i = 0; i < root.displayKeys.length; i++) {
      var key = root.displayKeys[i]
      if (!inTarget[key] && !(key in root.anim.tweens) && (root.anim.presence[key] || 0) <= 0.001) {
        delete root.anim.presence[key]
        changed = true
        continue
      }
      keep.push(key)
    }
    for (var gap in root.anim.gaps) {
      if (!(gap in root.anim.gapTweens) && root.anim.gaps[gap] <= 0.001) delete root.anim.gaps[gap]
    }
    if (changed) root.setDisplay(keep)
  }

  function stepAnimations() {
    var now = Date.now()
    var busy = root.advance(root.anim.presence, root.anim.tweens, now)
    busy = root.advance(root.anim.gaps, root.anim.gapTweens, now) || busy
    root.dropGone()
    root.animRev++
    if (!busy) root.animating = false
  }

  FrameAnimation {
    running: root.animating
    onTriggered: root.stepAnimations()
  }

  // Fila de segmentos para o layout: itens exibidos (menos o arrastado) e os
  // vãos que o arrasto abre entre eles.
  function flow() {
    var out = []
    var keys = root.displayKeys
    var gaps = root.anim.gaps
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      var gapKey = "gap:" + key
      if (gaps[gapKey] > 0) out.push({ key: gapKey, kind: "gap", presence: gaps[gapKey] })
      if (key === root.dragKey) continue
      var data = root.itemData[key]
      var presence = root.anim.presence[key]
      out.push({ key: key, kind: data ? data.kind : "app", presence: presence === undefined ? 1 : presence })
    }
    if (gaps["gap:@tail"] > 0) out.push({ key: "gap:@tail", kind: "gap", presence: gaps["gap:@tail"] })
    return out
  }

  readonly property var layout: {
    root.animRev
    return DockLayout.compute(root.flow(), root.dims, { x: root.pointerX, zoom: root.zoom })
  }

  // ---------------------------------------------------------- cursor e ampliação
  property bool pointerInside: false
  property real pointerX: -1
  property real pointerY: -1
  property string hoverKey: ""
  // Último item com rótulo: o rótulo esmaece no lugar em vez de pular.
  property string labelKey: ""
  property var pressInfo: null
  property string pressedKey: ""

  readonly property bool zoomWanted: root.magnifyEnabled && root.revealed && root.shown
    && (root.dragActive ? root.dragMode === "reorder" : root.pointerInside)
  property real zoom: root.zoomWanted ? 1 : 0
  Behavior on zoom { NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic } }

  readonly property var labelSlot: root.labelKey !== "" ? (root.layout.items[root.labelKey] || null) : null
  readonly property string labelText: {
    var data = root.labelKey !== "" ? root.itemData[root.labelKey] : null
    return data && data.kind !== "separator" ? String(data.name || "") : ""
  }
  readonly property bool labelShown: root.hoverKey !== "" && root.labelSlot !== null && root.labelText !== ""
    && root.revealed && root.pointerInside && !root.menuOpen && !root.dragActive

  function pointerEnter() {
    root.pointerInside = true
    hideTimer.stop()
    // O shell chama close() em todo painel ao recarregar plugins; encostar
    // no Dock desfaz esse recolher e o Dock fixo volta a ser fixo.
    root.hideRequested = false
    if (root.concealMode) root.peek = true
  }

  function pointerExit() {
    // Com o menu aberto o Dock fica como estava (ampliado e sem recolher).
    if (root.menuOpen) return
    root.pointerInside = false
    root.hoverKey = ""
    if (!root.dragActive) longPress.stop()
    if (root.concealMode && !root.dragActive) hideTimer.restart()
  }

  function pointerMove(x, y) {
    if (root.dragActive) { root.updateDrag(x, y); return }
    var press = root.pressInfo
    if (press && press.button === Qt.LeftButton) {
      var dx = x - press.x
      var dy = y - press.y
      if (dx * dx + dy * dy > 36) {
        longPress.stop()
        if (root.draggable(press.key)) { root.beginDrag(press, x, y); return }
      }
    }
    root.pointerY = y
    // Com o rótulo à mostra, subir do ícone até ele não troca de ícone nem
    // mexe na ampliação. Mede no repouso: revelando, o corpo ainda sobe.
    var restBaseline = root.restBodyY + root.bodyHeight - root.padBottom
    if (!root.labelShown || y >= restBaseline - root.layout.maxSize - 2) root.pointerX = x
    var key = DockLayout.keyAt(root.layout, root.pointerX)
    if (key !== root.hoverKey) {
      root.hoverKey = key
      var data = key ? root.itemData[key] : null
      if (data && data.kind === "minimized") root.requestThumbs()
    }
    if (key !== "") root.labelKey = key
  }

  function pointerPress(x, y, button) {
    var key = DockLayout.keyAt(root.layout, x)
    if (button === Qt.RightButton) {
      root.pressInfo = null
      root.openMenuFor(key)
      return
    }
    root.pressInfo = { x: x, y: y, button: button, key: key }
    if (button === Qt.LeftButton && key !== "") {
      root.pressedKey = key
      longPress.restart()
    }
  }

  function pointerRelease(x, y, button) {
    longPress.stop()
    var press = root.pressInfo
    root.pressInfo = null
    root.pressedKey = ""
    if (root.dragActive) { root.endDrag(x, y); return }
    if (!press || press.button !== button || press.key === "") return
    // Soltar fora do item cancela, como num botão.
    if (DockLayout.keyAt(root.layout, x) !== press.key) return
    if (button === Qt.LeftButton) root.activate(press.key)
    else if (button === Qt.MiddleButton) root.openNewWindow(press.key)
  }

  function pointerCancel() {
    longPress.stop()
    root.pressInfo = null
    root.pressedKey = ""
    if (root.dragActive) root.cancelDrag()
  }

  // Segurar o clique abre o menu, como no Mac (útil no trackpad).
  Timer {
    id: longPress
    interval: 550
    onTriggered: {
      var press = root.pressInfo
      if (!press || root.dragActive) return
      root.pressInfo = null
      root.pressedKey = ""
      root.openMenuFor(press.key)
    }
  }

  // ---------------------------------------------------------- recolher e revelar
  property bool hideRequested: false
  property bool peek: false
  readonly property bool concealMode: root.autohide || root.hideRequested
  readonly property bool revealed: !root.concealMode || root.peek || root.menuOpen || root.dragActive

  function peekFor(ms) {
    if (!root.concealMode) return
    root.peek = true
    peekTimer.interval = ms
    peekTimer.restart()
  }

  function showDock() {
    root.hideRequested = false
    root.peekFor(2500)
  }

  function conceal() {
    if (!root.autohide) root.hideRequested = true
    if (!root.pointerInside && !root.menuOpen && !root.dragActive) root.peek = false
  }

  function maybeHide() {
    if (!root.pointerInside && !root.menuOpen && !root.dragActive) root.peek = false
  }

  Timer { id: hideTimer; interval: 600; onTriggered: root.maybeHide() }
  Timer { id: peekTimer; onTriggered: root.maybeHide() }

  function handleEvent(verb, arg) {
    if (verb === "autohide-toggle") settings.set("dock.autohide", !root.autohide)
    else if (verb === "show") root.showDock()
    else if (verb === "hide") root.conceal()
    else if (verb === "minimizing") root.startGenie(arg)
    else if (verb === "minimize") root.minimizeAnimated(arg)
    else if (verb === "minimized") {
      root.peekFor(1800)
      hypr.refresh()
      root.requestThumbs()
    }
  }

  // ---------------------------------------------------------- gênio
  // Janela minimizada escorre para o lugar dela no Dock; restaurar faz o
  // caminho de volta. As posições das janelas ficam guardadas para a volta.
  property string genieKey: ""
  property var minimizedRects: ({})

  readonly property rect genieTarget: {
    var slot = root.genieKey ? root.layout.items[root.genieKey] : null
    if (!slot) slot = root.layout.items["trash"] || null
    var size = slot ? slot.size : root.iconSize
    var center = slot ? slot.center : root.screenWidth / 2
    return Qt.rect(center - size / 2, root.toScreenY(root.baselineY - size), size, size)
  }

  function localRect(x, y, w, h) {
    var sx = root.dockScreen ? root.dockScreen.x : 0
    var sy = root.dockScreen ? root.dockScreen.y : 0
    return Qt.rect(x - sx, y - sy, w, h)
  }

  // "0xabc,x,y,w,h": a janela está saindo (SUPER+M, pelo hypr/pomar.lua).
  function startGenie(arg) {
    var parts = String(arg || "").split(",")
    if (parts.length < 5) return
    var addr = root.address(parts[0])
    var rect = root.localRect(Number(parts[1]), Number(parts[2]), Number(parts[3]), Number(parts[4]))
    if (!(rect.width > 0 && rect.height > 0)) return
    var rects = Object.assign({}, root.minimizedRects)
    rects[addr] = rect
    root.minimizedRects = rects
    root.peekFor(1800)
    root.genieKey = "min:" + addr
    genie.play(hypr.toplevelFor(addr), rect, false)
  }

  // Minimizar pedido por outro lugar (barra de menus, menu do Dock): o próprio
  // Dock anima e tira a janela de cena.
  function minimizeAnimated(arg) {
    var addr = root.address(arg || root.focusedAddress())
    var c = hypr.byAddress[addr]
    if (!addr || !c) return
    root.startGenie([addr, c.at[0], c.at[1], c.size[0], c.size[1]].join(","))
    minimizeLater.address = addr
    minimizeLater.restart()
  }

  Timer {
    id: minimizeLater
    property string address: ""
    interval: 70
    onTriggered: {
      events.dispatch('hl.dsp.window.move({ window = "address:' + address + '", workspace = "special:pomar-minimized", follow = false })')
      root.handleEvent("minimized", address)
    }
  }

  function restoreAnimated(addr) {
    addr = root.address(addr)
    var rect = root.minimizedRects[addr]
    var c = hypr.byAddress[addr]
    if (!rect && c) rect = root.localRect(c.at[0], c.at[1], c.size[0], c.size[1])
    var top = hypr.toplevelFor(addr)
    if (!rect || !top) { root.restoreWindow(addr); return }
    root.genieKey = "min:" + addr
    genie.restoring = addr
    genie.play(top, rect, true)
  }

  // Fechar, minimizar e zoom no alto de cada janela, como no Mac.
  WindowControls {
    id: windowControls
    hypr: hypr
    enabled: settings.active && settings.get("windowControls.enabled", true) === true
    dark: root.dark
    onCloseRequested: function(address) {
      events.dispatch('hl.dsp.window.close({ window = "address:' + root.address(address) + '" })')
    }
    onMinimizeRequested: function(address) { root.minimizeAnimated(address) }
    onZoomRequested: function(address) {
      events.dispatch('hl.dsp.window.fullscreen({ window = "address:' + root.address(address) + '", mode = "maximized" })')
    }
  }

  Genie {
    id: genie
    property string restoring: ""
    screen: root.dockScreen
    toRect: root.genieTarget
    onDone: function(reversed) {
      if (reversed && genie.restoring) {
        root.restoreWindow(genie.restoring)
        genie.restoring = ""
      }
      root.genieKey = ""
    }
  }

  // ---------------------------------------------------------- ações
  function run(argv) {
    // Fora dos testes vai pelo mesmo caminho do lançador do Omarchy (escopo do
    // uwsm). No harness o uwsm-app mandaria o app para a sessão real pelo
    // daemon do uwsm; lá o app sobe direto, dentro do compositor de teste.
    Quickshell.execDetached(root.testMode ? argv : ["uwsm-app", "--"].concat(argv))
  }

  // No harness, recusa o que abre por fora (webapps e lançadores do Omarchy
  // chamam o uwsm-app por conta própria e abririam na sessão real).
  function testSafe(text) {
    return !root.testMode || !/uwsm|omarchy-launch|omarchy-webapp|setsid/.test(String(text || ""))
  }

  function launchApp(id) {
    if (!root.testMode) { Apps.launch(Quickshell, id); return }
    var entry = DesktopEntries.byId(Apps.stripDesktop(id))
    if (entry && root.testSafe(entry.execString)) root.run(["gtk-launch", Apps.stripDesktop(id) + ".desktop"])
  }

  function runAction(action) {
    var argv = []
    var command = action ? action.command : null
    for (var i = 0; command && i < command.length; i++) argv.push(String(command[i]))
    if (argv.length && root.testSafe(argv.join(" "))) root.run(argv)
  }

  function address(value) { return hypr.normalizeAddress(value) }

  function focusedAddress() {
    var top = Hyprland.activeToplevel
    return top ? root.address(top.address) : ""
  }

  function focusWindow(addr) {
    events.dispatch('hl.dsp.focus({ window = "address:' + root.address(addr) + '" })')
  }

  function currentWorkspace() {
    var monitor = Hyprland.focusedMonitor
    var ws = monitor ? monitor.activeWorkspace : null
    if (ws && ws.id > 0) return String(ws.id)
    if (ws && ws.name) return "name:" + ws.name
    return "1"
  }

  // Minimizada volta para a mesa atual e ganha o foco (follow).
  function restoreWindow(addr) {
    events.dispatch('hl.dsp.window.move({ window = "address:' + root.address(addr) + '", workspace = "'
                    + root.currentWorkspace() + '", follow = true })')
  }

  function closeWindow(addr) {
    events.dispatch('hl.dsp.window.close({ window = "address:' + root.address(addr) + '" })')
  }

  function activate(key) {
    var item = root.itemData[key]
    if (!item) return
    if (item.kind === "launchpad") { events.send("launchpad", "toggle"); return }
    if (item.kind === "trash") { root.openTrash(); return }
    if (item.kind === "minimized") { root.restoreAnimated(item.address); return }
    if (item.kind !== "app") return
    if (item.windows.length > 0) {
      var focused = root.focusedAddress()
      var mine = false
      for (var i = 0; i < item.windows.length; i++) if (item.windows[i].address === focused) mine = true
      // Fora de foco: a janela mais recente do app. Em foco: a próxima.
      if (!mine) { root.focusWindow(item.windows[0].address); return }
      if (item.windows.length > 1) {
        var stable = item.windows.map(function(w) { return w.address }).sort()
        root.focusWindow(stable[(stable.indexOf(focused) + 1) % stable.length])
      }
      return
    }
    if (item.minimized.length > 0) { root.restoreAnimated(item.minimized[0].address); return }
    root.beginLaunch(key)
    root.launchApp(item.id)
  }

  function openNewWindow(key) {
    var item = root.itemData[key]
    if (!item) return
    if (item.kind !== "app") { root.activate(key); return }
    var actions = item.entry ? (item.entry.actions || []) : []
    var action = null
    for (var i = 0; i < actions.length; i++) if (String(actions[i].id) === "new-window") action = actions[i]
    root.beginLaunch(key)
    if (action) root.runAction(action)
    else root.launchApp(item.id)
  }

  function quitApp(item) {
    var all = (item.windows || []).concat(item.minimized || [])
    for (var i = 0; i < all.length; i++) root.closeWindow(all[i].address)
  }

  function setFavorites(list) {
    settings.set("dock.favorites", list)
    root.rebuild()
  }

  function keepInDock(id) {
    if (root.favorites.indexOf(id) < 0) root.setFavorites(root.favorites.concat([id]))
  }

  function removeFromDock(id) {
    root.setFavorites(root.favorites.filter(function(f) { return f !== id }))
  }

  // ---------------------------------------------------------- abrir app (quicar)
  property var launching: ({})

  function beginLaunch(key) {
    var item = root.itemData[key]
    var next = ({})
    for (var k in root.launching) next[k] = root.launching[k]
    next[key] = { until: Date.now() + 6000, base: item ? (item.windows || []).length + (item.minimized || []).length : 0 }
    root.launching = next
    root.checkLaunches()
  }

  // Para de quicar quando aparece janela nova do app ou depois de 6 s.
  function checkLaunches() {
    var now = Date.now()
    var next = ({})
    var changed = false
    var soonest = Infinity
    for (var key in root.launching) {
      var launch = root.launching[key]
      var item = root.itemData[key]
      var count = item ? (item.windows || []).length + (item.minimized || []).length : 0
      if (now >= launch.until || count > launch.base) { changed = true; continue }
      next[key] = launch
      soonest = Math.min(soonest, launch.until - now)
    }
    if (changed) root.launching = next
    if (soonest < Infinity) {
      launchTimer.interval = Math.max(50, soonest + 20)
      launchTimer.restart()
    }
  }

  Timer { id: launchTimer; onTriggered: root.checkLaunches() }

  // ---------------------------------------------------------- lixeira
  // Lixeira do usuário em $XDG_DATA_HOME/Trash (especificação freedesktop).
  // No harness só o HOME é isolado, então lá vale a do HOME de teste.
  readonly property string dataHome: {
    var xdg = Quickshell.env("XDG_DATA_HOME")
    return !root.testMode && xdg ? xdg : root.home + "/.local/share"
  }
  readonly property string trashDir: root.dataHome + "/Trash"
  property bool trashReady: false
  readonly property bool trashFull: trashWatch.item ? trashWatch.item.count > 0 : false
  // Desenho próprio, como o do Mac, igual em qualquer tema de ícones.
  readonly property string trashIcon: Qt.resolvedUrl(root.trashFull ? "assets/trash-full.svg" : "assets/trash-empty.svg")
  property string fileManagerId: "org.gnome.Nautilus"

  // A pasta precisa existir antes: sem ela o FolderListModel lista a pasta
  // de trabalho do shell. Criar as pastas é o que a própria Lixeira faz.
  Process {
    id: trashSetup
    command: ["mkdir", "-p", root.trashDir + "/files", root.trashDir + "/info"]
    onExited: root.trashReady = true
  }

  LazyLoader {
    id: trashWatch
    active: root.trashReady
    FolderListModel {
      folder: "file://" + root.trashDir + "/files"
      showDirs: true
      showHidden: true
      showDotAndDotDot: false
      sortField: FolderListModel.Unsorted
    }
  }

  Process {
    id: fileManagerProbe
    command: ["xdg-mime", "query", "default", "inode/directory"]
    stdout: StdioCollector {
      onStreamFinished: {
        var id = Apps.stripDesktop(String(text || "").trim())
        if (id) root.fileManagerId = id
      }
    }
  }

  function emptyTrash() {
    if (!root.testMode) {
      Quickshell.execDetached(["gio", "trash", "--empty"])
      return
    }
    // No harness o gio esvaziaria a Lixeira REAL: o XDG_DATA_HOME e o daemon
    // do GVfs vêm de fora do HOME de teste. Lá só apaga dentro do HOME de
    // teste, e só se ele for mesmo a pasta temporária do harness.
    if (root.trashDir.indexOf("/pomar-nested-") < 0) return
    Quickshell.execDetached(["find", root.trashDir + "/files", root.trashDir + "/info", "-mindepth", "1", "-delete"])
  }

  function openTrash() {
    // No harness abre a pasta da Lixeira de teste: trash:/// passaria pelo
    // GVfs, que enxerga a Lixeira real.
    var target = root.testMode ? "file://" + root.trashDir + "/files" : "trash:///"
    root.run(["gtk-launch", root.fileManagerId + ".desktop", target])
  }

  function askEmptyTrash() {
    root.closeMenu()
    menu.dialog = {
      icon: Qt.resolvedUrl("assets/trash-full.svg"),
      title: root.tr("emptyTrashTitle"),
      message: root.tr("emptyTrashMessage"),
      confirm: root.tr("emptyTrashConfirm"),
      cancel: I18n.tr(Strings.STRINGS, "cancel", root.lang),
      run: root.emptyTrash
    }
  }

  // ---------------------------------------------------------- minimizadas
  property int thumbRequest: 0
  function requestThumbs() { thumbTimer.restart() }
  Timer { id: thumbTimer; interval: 150; onTriggered: root.thumbRequest++ }

  function toplevelFor(addr, serial) {
    return addr ? hypr.toplevelFor(addr) : null
  }

  // ---------------------------------------------------------- menus
  readonly property bool menuOpen: menu.menuShown || menu.dialog !== null
  property string menuKey: ""
  property bool menuRefreshPending: false

  function row(text, action, enabled) {
    return { type: "item", text: text, enabled: enabled !== false, run: action }
  }

  function itemRows(item) {
    var rows = [{ type: "header", text: item.name }]
    var t = function(key) { return I18n.tr(Strings.STRINGS, key, root.lang) }
    if (item.kind === "app") {
      var windows = (item.windows || []).concat(item.minimized || [])
      var focused = root.focusedAddress()
      if (windows.length) rows.push({ type: "separator" })
      windows.forEach(function(w) {
        var minimized = hypr.isMinimized(w)
        var r = root.row(String(w.title || item.name), function() {
          if (minimized) root.restoreWindow(w.address)
          else root.focusWindow(w.address)
        })
        r.checked = w.address === focused
        r.dim = minimized
        rows.push(r)
      })
      rows.push({ type: "separator" })
      rows.push(root.row(t("newWindow"), function() { root.openNewWindow(item.key) }, !!item.entry))
      var actions = item.entry ? (item.entry.actions || []) : []
      for (var i = 0; i < actions.length; i++) {
        if (String(actions[i].id) === "new-window") continue
        rows.push((function(action) {
          return root.row(String(action.name || action.id), function() { root.runAction(action) })
        })(actions[i]))
      }
      rows.push({ type: "separator" })
      rows.push(item.favorite
        ? root.row(t("removeFromDock"), function() { root.removeFromDock(item.id) })
        : root.row(t("keepInDock"), function() { root.keepInDock(item.id) }))
      rows.push(root.row(t("showAllWindows"), function() { events.send("mission", "expose", item.id) }, (item.windows || []).length > 0))
      rows.push(root.row(t("quit"), function() { root.quitApp(item) }, item.running === true))
    } else if (item.kind === "launchpad") {
      rows.push({ type: "separator" })
      rows.push(root.row(t("open"), function() { events.send("launchpad", "toggle") }))
      rows.push({ type: "separator" })
      rows.push(root.row(t("removeFromDock"), function() { root.removeFromDock(item.id) }))
    } else if (item.kind === "trash") {
      rows.push({ type: "separator" })
      rows.push(root.row(t("open"), function() { root.openTrash() }))
      rows.push({ type: "separator" })
      rows.push(root.row(t("emptyTrash"), function() { root.askEmptyTrash() }, root.trashFull))
    } else if (item.kind === "minimized") {
      rows.push({ type: "separator" })
      rows.push(root.row(t("restoreWindow"), function() { root.restoreWindow(item.address) }))
      rows.push(root.row(t("closeWindow"), function() { root.closeWindow(item.address) }))
    }
    return rows
  }

  function dockRows() {
    return [
      root.row(root.autohide ? root.tr("autohideOff") : root.tr("autohideOn"), function() { settings.set("dock.autohide", !root.autohide) }),
      root.row(root.magnifyEnabled ? root.tr("magnifyOff") : root.tr("magnifyOn"), function() { settings.set("dock.magnification", !root.magnifyEnabled) }),
      { type: "separator" },
      root.row(root.tr("dockSettings"), function() {
        Quickshell.execDetached(["omarchy-shell", "shell", "summon", "pomar.settings", '{"page":"dock"}'])
      })
    ]
  }

  function openMenuFor(key) {
    var item = key ? root.itemData[key] : null
    var isItem = item && item.kind !== "separator"
    var slot = key ? root.layout.items[key] : null
    root.menuKey = isItem ? key : ""
    root.menuRefreshPending = isItem
    if (isItem) hypr.refreshNow()
    menu.rows = isItem ? root.itemRows(item) : root.dockRows()
    // Acima do ícone (já ampliado), centrado nele.
    var screenHeight = root.dockScreen ? root.dockScreen.height : dockWindow.height
    var windowTop = screenHeight - dockWindow.height
    var top = slot && isItem ? root.baselineY - slot.size : root.bodyY
    menu.anchorX = slot ? slot.center : root.pointerX
    menu.anchorBottom = windowTop + top - 10
    menu.menuShown = true
  }

  function closeMenu() {
    menu.menuShown = false
    root.menuKey = ""
    root.menuRefreshPending = false
    menuCloseSync.restart()
  }

  function closeDialog() {
    menu.dialog = null
    menuCloseSync.restart()
  }

  // Ao fechar o menu, o compositor devolve o cursor ao Dock (se ainda estiver
  // em cima); só então vale olhar se ele saiu.
  Timer {
    id: menuCloseSync
    interval: 140
    onTriggered: {
      if (!pointerArea.containsMouse && !root.dragActive) {
        root.pointerInside = false
        root.hoverKey = ""
        if (root.concealMode) hideTimer.restart()
      }
    }
  }

  DockMenu {
    id: menu
    dock: root
    onActivated: function(index) {
      var picked = menu.rows[index]
      root.closeMenu()
      if (picked && picked.run) picked.run()
    }
    onDismissed: root.closeMenu()
    onConfirmed: {
      var dialog = menu.dialog
      root.closeDialog()
      if (dialog && dialog.run) dialog.run()
    }
    onCanceled: root.closeDialog()
  }

  // ---------------------------------------------------------- arrastar
  property bool dragActive: false
  property string dragKey: ""
  property string dragMode: ""
  property string gapKey: ""
  property bool dragPin: false
  property var dragInfo: null
  property string settlingKey: ""

  function draggable(key) {
    var item = key ? root.itemData[key] : null
    return !!item && (item.kind === "app" || item.kind === "launchpad")
  }

  function gapAfter(key) {
    var keys = root.displayKeys
    var index = keys.indexOf(key)
    for (var j = index + 1; j < keys.length; j++) if (keys[j] !== key) return "gap:" + keys[j]
    return "gap:@tail"
  }

  function beginDrag(press, x, y) {
    var item = root.itemData[press.key]
    var slot = root.layout.items[press.key]
    if (!item || !slot) return
    var origin = root.gapAfter(press.key)
    root.dragInfo = {
      key: press.key,
      id: item.id,
      favorite: item.favorite === true,
      origin: origin,
      size: slot.size,
      icon: item.icon,
      grabX: slot.center - press.x,
      grabY: (root.baselineY - slot.size / 2) - press.y
    }
    // O vão nasce cheio no lugar do ícone: nada pula quando o arrasto começa.
    root.anim.gaps = ({})
    root.anim.gapTweens = ({})
    root.anim.gaps[origin] = 1
    root.gapKey = origin
    root.dragPin = false
    root.dragKey = press.key
    root.dragMode = "reorder"
    root.dragActive = true
    root.hoverKey = ""
    root.pressedKey = ""
    ghost.follow = true
    ghost.size = slot.size
    ghost.shown = true
    root.updateDrag(x, y)
  }

  // Onde o vão deve abrir para o cursor em x. Medido no repouso e sem o vão,
  // para o vão não empurrar a própria medida.
  function dropTarget(x) {
    var info = root.dragInfo
    var rest = []
    var favKeys = []
    var afterFav = ""
    for (var i = 0; i < root.displayKeys.length; i++) {
      var key = root.displayKeys[i]
      if (key === info.key) continue
      var data = root.itemData[key]
      if (!data) continue
      rest.push({ key: key, kind: data.kind, presence: 1 })
      if (data.favorite) favKeys.push(key)
      else if (!afterFav) afterFav = key
    }
    var layout = DockLayout.compute(rest, root.dims, { x: 0, zoom: 0 })
    var tail = afterFav ? "gap:" + afterFav : "gap:@tail"
    if (!info.favorite) {
      // App aberto só vira favorito quando solto sobre a área dos favoritos.
      var last = favKeys.length ? layout.items[favKeys[favKeys.length - 1]] : null
      var limit = last ? last.slotLeft + last.slotWidth + (root.iconSize + root.gapSize) / 2 : layout.restLeft + root.padSide
      if (x > limit) return { gap: info.origin, pin: false }
    }
    for (var f = 0; f < favKeys.length; f++) {
      if (x < layout.items[favKeys[f]].restCenter) return { gap: "gap:" + favKeys[f], pin: !info.favorite }
    }
    return { gap: tail, pin: !info.favorite }
  }

  function moveGap(target) {
    if (target === root.gapKey) return
    if (root.gapKey) root.tween(root.anim.gaps, root.anim.gapTweens, root.gapKey, 0)
    if (target) root.tween(root.anim.gaps, root.anim.gapTweens, target, 1)
    root.gapKey = target
    root.animRev++
  }

  function updateDrag(x, y) {
    var info = root.dragInfo
    if (!info) return
    root.pointerX = x
    root.pointerY = y
    ghost.cx = x + info.grabX
    ghost.cy = root.toScreenY(y + info.grabY)
    // Arrastar um favorito bem para cima do Dock e soltar tira ele do Dock.
    var above = root.restBodyY - y
    root.dragMode = info.favorite && above > 70 ? "remove" : "reorder"
    if (root.dragMode === "remove") {
      root.dragPin = false
      root.moveGap("")
      return
    }
    var target = root.dropTarget(x)
    root.dragPin = target.pin
    root.moveGap(target.gap)
  }

  function finishDrag() {
    root.anim.gaps = ({})
    root.anim.gapTweens = ({})
    root.gapKey = ""
    root.dragKey = ""
    root.dragMode = ""
    root.dragPin = false
    root.dragActive = false
    root.dragInfo = null
    root.animRev++
  }

  function endDrag(x, y) {
    var info = root.dragInfo
    if (!info) { root.finishDrag(); return }
    if (root.dragMode === "remove") {
      // Volta ao fluxo já sem lugar: o Dock não reabre o espaço do removido.
      // Se o app estiver aberto, reaparece crescendo entre os abertos.
      root.anim.presence[info.key] = 0
      delete root.anim.tweens[info.key]
      ghost.puff()
      root.finishDrag()
      root.removeFromDock(info.id)
      return
    }
    if (info.favorite || root.dragPin) {
      var favs = root.favorites.filter(function(f) { return f !== info.id })
      var anchor = root.itemData[root.gapKey.slice(4)]
      var index = anchor && anchor.favorite ? favs.indexOf(anchor.id) : -1
      if (index < 0) index = favs.length
      favs.splice(index, 0, info.id)
      if (JSON.stringify(favs) !== JSON.stringify(root.favorites)) {
        // Grava e remonta já, antes de fechar o vão: o ícone assenta no lugar
        // novo sem piscar no antigo.
        settings.set("dock.favorites", favs)
        root.rebuild()
      }
    }
    root.settle(info)
  }

  function cancelDrag() {
    var info = root.dragInfo
    if (!info) { root.finishDrag(); return }
    root.settle(info)
  }

  // O ícone solto voa até o lugar dele no Dock e só então reaparece lá.
  function settle(info) {
    root.settlingKey = info.key
    root.finishDrag()
    var slot = root.layout.items[info.key]
    if (!slot) { ghost.shown = false; root.settlingKey = ""; return }
    ghost.flyTo(slot.center, root.toScreenY(root.baselineY - slot.size / 2), slot.size)
  }

  function toScreenY(windowY) {
    var screenHeight = root.dockScreen ? root.dockScreen.height : dockWindow.height
    return screenHeight - dockWindow.height + windowY
  }

  // ---------------------------------------------------------- janela do Dock
  PanelWindow {
    id: dockWindow
    screen: root.dockScreen
    visible: root.shown
    color: "transparent"
    anchors { bottom: true; left: true; right: true }
    implicitHeight: root.windowHeight
    // Fixo, reserva a altura do corpo: janelas lado a lado param acima dele.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: root.autohide ? 0 : root.bodyHeight + root.bottomMargin
    WlrLayershell.namespace: "pomar-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Só o corpo (e o rótulo) recebe o mouse; o resto passa para as janelas.
    // Recolhido, sobra uma faixa de 3 px na borda que revela ao encostar.
    mask: Region {
      x: root.hitRect.x
      y: root.hitRect.y
      width: root.hitRect.w
      height: root.hitRect.h
      Region {
        x: labelBox.x
        y: labelBox.y
        width: root.labelShown ? labelBox.width : 0
        height: root.labelShown ? labelBox.height : 0
      }
    }

    Glass {
      id: body
      dark: root.dark
      radius: Tokens.radius.dock
      x: root.layout.left
      y: root.bodyY
      width: Math.max(0, root.layout.right - root.layout.left)
      height: root.bodyHeight
      visible: root.slide < 0.999
    }

    Item {
      id: iconLayer
      anchors.fill: parent
      visible: root.slide < 0.999

      Repeater {
        model: ScriptModel {
          values: root.displayItems
          objectProp: "key"
        }
        delegate: DockIcon {
          dock: root
        }
      }
    }

    Item {
      id: labelBox
      width: Math.ceil(Math.min(labelTextItem.implicitWidth, root.labelMaxWidth) + 24)
      height: root.labelHeight
      x: Math.round(Tokens.clamp((root.labelSlot ? root.labelSlot.center : 0) - width / 2, 6, root.screenWidth - width - 6))
      y: Math.round(root.baselineY - (root.labelSlot ? root.labelSlot.size : root.iconSize) - root.labelGap - height)
      opacity: root.labelShown ? 1 : 0
      visible: opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: Tokens.motion.instant; easing.type: Easing.OutCubic } }

      Glass {
        anchors.fill: parent
        dark: root.dark
        radius: height / 2
        fill: Tokens.glassStrong(root.dark)
        shadowBlur: 14
        shadowOffsetY: 4
      }

      Text {
        id: labelTextItem
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.labelMaxWidth)
        elide: Text.ElideRight
        text: root.labelText
        font.family: root.fontFamily
        font.pixelSize: 13
        color: Tokens.label(root.dark)
      }
    }

    MouseArea {
      id: pointerArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onEntered: root.pointerEnter()
      onExited: root.pointerExit()
      onPositionChanged: function(mouse) { root.pointerMove(mouse.x, mouse.y) }
      onPressed: function(mouse) { root.pointerPress(mouse.x, mouse.y, mouse.button) }
      onReleased: function(mouse) { root.pointerRelease(mouse.x, mouse.y, mouse.button) }
      onCanceled: root.pointerCancel()
    }
  }

  // Área de acerto do Dock (coordenadas da janela). Com o cursor em cima ela
  // cresce até o topo dos ícones ampliados e encosta no rótulo: subir do
  // ícone para o rótulo não sai do Dock. Vai sempre até a borda da tela.
  readonly property var hitRect: {
    var l = root.layout
    if (!root.revealed) {
      return { x: Math.floor(l.restLeft), y: root.windowHeight - 3, w: Math.ceil(l.restRight - l.restLeft), h: 3 }
    }
    var top = root.bodyY
    if (root.pointerInside || root.dragActive)
      top = Math.min(top, root.baselineY - l.maxSize - (root.labelShown ? root.labelGap : 0))
    top = Math.floor(Math.max(0, top))
    return { x: Math.floor(l.left), y: top, w: Math.ceil(l.right - l.left) + 1, h: root.windowHeight - top }
  }

  // ---------------------------------------------------------- ícone arrastado
  // Numa camada própria acima de tudo, sem mouse (máscara vazia): o arrasto
  // continua recebendo o movimento pela janela do Dock (captura implícita do
  // botão apertado) e o ícone pode ir a qualquer ponto da tela.
  PanelWindow {
    id: ghostWindow
    screen: root.dockScreen
    visible: root.shown && ghost.shown
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "pomar-dock-drag"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Item {
      id: ghost
      property bool shown: false
      property bool follow: true
      property real cx: 0
      property real cy: 0
      property real size: root.iconSize
      property real vanish: 0
      readonly property string icon: root.dragInfo ? String(root.dragInfo.icon || "") : lastIcon
      property string lastIcon: ""
      onIconChanged: if (icon) lastIcon = icon

      function flyTo(x, y, s) {
        fly.stop()
        flyX.to = x
        flyY.to = y
        flySize.to = s
        fly.start()
      }

      function puff() {
        smoke.progress = 0
        vanish = 0
        puffAnim.restart()
      }

      Image {
        width: ghost.size * (1 - 0.6 * ghost.vanish)
        height: width
        x: ghost.cx - width / 2
        y: ghost.cy - height / 2
        source: ghost.icon
        sourceSize.width: root.textureSize
        sourceSize.height: root.textureSize
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        opacity: 1 - ghost.vanish
      }

      // "Remover" acima do ícone enquanto soltar tira ele do Dock.
      Item {
        readonly property bool active: root.dragActive && root.dragMode === "remove"
        width: Math.ceil(removeText.implicitWidth + 24)
        height: root.labelHeight
        x: Math.round(ghost.cx - width / 2)
        y: Math.round(ghost.cy - ghost.size / 2 - root.labelGap - height)
        opacity: active ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.fast } }

        Glass {
          anchors.fill: parent
          dark: root.dark
          radius: height / 2
          fill: Tokens.glassStrong(root.dark)
          shadowBlur: 14
          shadowOffsetY: 4
        }

        Text {
          id: removeText
          anchors.centerIn: parent
          text: root.tr("remove")
          font.family: root.fontFamily
          font.pixelSize: 13
          color: Tokens.label(root.dark)
        }
      }

      // Nuvem do "puf": tufos claros juntos, que incham, se afastam e somem.
      Item {
        id: smoke
        property real progress: 0
        visible: progress > 0 && progress < 1
        Repeater {
          model: 7
          Rectangle {
            required property int index
            readonly property real angle: index / 7 * Math.PI * 2 - Math.PI / 2
            readonly property real distance: ghost.size * (0.1 + 0.34 * smoke.progress) * (index % 2 ? 0.8 : 1)
            width: ghost.size * (0.34 + 0.08 * (index % 3)) * (0.55 + 0.75 * smoke.progress)
            height: width
            radius: width / 2
            x: ghost.cx + Math.cos(angle) * distance - width / 2
            y: ghost.cy + Math.sin(angle) * distance * 0.8 - width / 2 - ghost.size * 0.2 * smoke.progress
            color: Tokens.glassStrong(false)
            border.width: 1
            border.color: Tokens.outline(false)
            opacity: 1 - smoke.progress * smoke.progress
          }
        }
      }

      ParallelAnimation {
        id: fly
        NumberAnimation { id: flyX; target: ghost; property: "cx"; duration: Tokens.motion.fast; easing.type: Easing.OutCubic }
        NumberAnimation { id: flyY; target: ghost; property: "cy"; duration: Tokens.motion.fast; easing.type: Easing.OutCubic }
        NumberAnimation { id: flySize; target: ghost; property: "size"; duration: Tokens.motion.fast; easing.type: Easing.OutCubic }
        onFinished: {
          ghost.shown = false
          root.settlingKey = ""
        }
      }

      SequentialAnimation {
        id: puffAnim
        ParallelAnimation {
          NumberAnimation { target: ghost; property: "vanish"; from: 0; to: 1; duration: Tokens.motion.fast; easing.type: Easing.OutCubic }
          NumberAnimation { target: smoke; property: "progress"; from: 0.01; to: 1; duration: Tokens.motion.slow; easing.type: Easing.OutCubic }
        }
        ScriptAction {
          script: {
            ghost.shown = false
            ghost.vanish = 0
            smoke.progress = 0
          }
        }
      }
    }
  }

  // ---------------------------------------------------------- favoritos iniciais
  // Lista vazia (primeira vez): monta uma com o que existe na máquina. Só
  // depois do arquivo de ajustes carregar, para nunca sobrescrever a lista
  // real com o padrão vazio.
  property bool seeding: false

  function maybeSeed() {
    // Só com o Pomarchy ativo: em outro tema o Dock não grava nada.
    if (root.seeding || !settings.loaded || !settings.active || root.favorites.length > 0) return
    if (settings.get("dock.seeded", false)) return
    if ((DesktopEntries.applications.values || []).length === 0) { seedRetry.restart(); return }
    root.seeding = true
    seedProbe.running = true
  }

  function seed(text) {
    root.seeding = false
    if (root.favorites.length > 0) return
    var defaults = DockModel.parseDefaults(text)
    var list = DockModel.starterFavorites(function(id) { return !!DesktopEntries.byId(id) }, defaults.browser, defaults.terminal)
    if (list.length) root.setFavorites(list)
    settings.set("dock.seeded", true)
  }

  Timer { id: seedRetry; interval: 1000; onTriggered: root.maybeSeed() }

  Process {
    id: seedProbe
    command: ["sh", "-c", "printf 'browser=%s\\nterminal=%s\\n' \"$(env -u BROWSER xdg-settings get default-web-browser 2>/dev/null)\" \"$(xdg-terminal-exec --print-id 2>/dev/null | head -n 1)\""]
    stdout: StdioCollector { onStreamFinished: root.seed(text) }
  }

  // ---------------------------------------------------------- ligações
  onFavoritesChanged: { root.maybeSeed(); root.scheduleRebuild() }
  onShowRunningChanged: root.scheduleRebuild()
  onShowMinimizedChanged: root.scheduleRebuild()
  onShowTrashChanged: root.scheduleRebuild()
  onLangChanged: root.scheduleRebuild()
  onClientSerialChanged: root.scheduleRebuild()
  onConcealModeChanged: if (root.concealMode && !root.pointerInside) root.peek = false

  Connections {
    target: settings
    function onLoadedChanged() { root.maybeSeed() }
    function onActiveChanged() {
      root.maybeSeed()
      if (settings.active && !root.trashReady && !trashSetup.running) trashSetup.running = true
    }
  }

  Connections {
    target: DesktopEntries
    function onApplicationsChanged() { root.rebuildWebIndex() }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuildWebIndex() }
  }

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() { screenFollow.restart() }
    // A ordem de uso recente decide qual janela o clique traz.
    function onRawEvent(event) { if (event.name === "activewindowv2") hypr.refresh() }
  }

  Timer { id: settleTimer; interval: 1500; onTriggered: root.settled = true }

  Component.onCompleted: {
    var monitor = Hyprland.focusedMonitor
    root.screenName = monitor ? String(monitor.name || "") : ""
    if (settings.active) trashSetup.running = true
    fileManagerProbe.running = true
    root.rebuildWebIndex()
    root.maybeSeed()
    settleTimer.start()
  }

  // ---------------------------------------------------------- testes
  // Só existe no harness (POMAR_TEST=1): cliques e arrastos que o harness não
  // simula passam pelas mesmas funções do mouse de verdade.
  function screenOffset() {
    var screenHeight = root.dockScreen ? root.dockScreen.height : dockWindow.height
    return screenHeight - dockWindow.height
  }

  function slotPoint(index) {
    var key = root.displayKeys[index]
    var slot = key ? root.layout.items[key] : null
    if (!slot) return null
    return { key: key, x: slot.center, y: root.baselineY - slot.size / 2 }
  }

  function testState() {
    var offset = root.screenOffset()
    var items = []
    for (var i = 0; i < root.displayKeys.length; i++) {
      var key = root.displayKeys[i]
      var data = root.itemData[key] || ({})
      var slot = root.layout.items[key]
      items.push({
        index: i, key: key, kind: data.kind, name: data.name || "", favorite: data.favorite === true,
        running: data.running === true, windows: (data.windows || []).length, minimized: (data.minimized || []).length,
        x: slot ? Math.round(slot.center) : null, y: slot ? Math.round(offset + root.baselineY - slot.size / 2) : null,
        size: slot ? Math.round(slot.size * 10) / 10 : null, presence: slot ? Math.round(slot.presence * 100) / 100 : 0
      })
    }
    return {
      shown: root.shown, revealed: root.revealed, autohide: root.autohide, peek: root.peek, slide: root.slide,
      zoom: Math.round(root.zoom * 100) / 100, pointerInside: root.pointerInside, hoverKey: root.hoverKey,
      label: root.labelShown ? root.labelText : "", menuOpen: root.menuOpen,
      menu: menu.menuShown ? menu.rows.map(function(r) { return r.type === "item" ? (r.enabled === false ? "(" + r.text + ")" : r.text) : (r.type === "header" ? "# " + r.text : "--") }) : [],
      dialog: menu.dialog ? menu.dialog.title : "", dragActive: root.dragActive, dragMode: root.dragMode, gapKey: root.gapKey,
      screen: root.screenName, windowHeight: dockWindow.height, exclusiveZone: dockWindow.exclusiveZone,
      body: { x: Math.round(root.layout.left), y: Math.round(offset + root.bodyY), w: Math.round(root.layout.right - root.layout.left), h: root.bodyHeight },
      hit: { x: root.hitRect.x, y: offset + root.hitRect.y, w: root.hitRect.w, h: root.hitRect.h },
      iconSize: root.iconSize, trashFull: root.trashFull, favorites: root.favorites, fullscreen: root.fullscreenActive,
      launching: Object.keys(root.launching), focused: root.focusedAddress(), items: items
    }
  }

  IpcHandler {
    target: "pomar-dock-test"
    enabled: root.testMode
    function windowControls(): string { return JSON.stringify(windowControls.describe()) }
    // O clique de um botão, com a posição que a superfície dele tinha.
    function windowAct(kind: string, address: string, gx: string, gy: string): void {
      windowControls.act(kind, hypr.normalizeAddress(address), Number(gx), Number(gy))
    }

    // Congela o gênio num ponto do caminho, para fotografar.
    function genieFreeze(value: real): string {
      genie.stop()
      genie.running = true
      genie.progress = value
      return JSON.stringify({ running: genie.running, progress: genie.progress, key: root.genieKey,
                              from: [genie.fromRect.x, genie.fromRect.y, genie.fromRect.width, genie.fromRect.height],
                              to: [genie.toRect.x, genie.toRect.y, genie.toRect.width, genie.toRect.height] })
    }

    function state(): string { return JSON.stringify(root.testState()) }

    function click(index: int): string {
      var p = root.slotPoint(index)
      if (!p) return "no-item"
      root.pointerPress(p.x, p.y, Qt.LeftButton)
      root.pointerRelease(p.x, p.y, Qt.LeftButton)
      return p.key
    }

    function middleClick(index: int): string {
      var p = root.slotPoint(index)
      if (!p) return "no-item"
      root.pointerPress(p.x, p.y, Qt.MiddleButton)
      root.pointerRelease(p.x, p.y, Qt.MiddleButton)
      return p.key
    }

    function rightClick(index: int): string {
      var p = root.slotPoint(index)
      if (!p) return "no-item"
      root.pointerPress(p.x, p.y, Qt.RightButton)
      root.pointerRelease(p.x, p.y, Qt.RightButton)
      return p.key
    }

    // Coordenadas de tela, como as do passo cursor: do harness.
    function press(x: real, y: real): string {
      root.pointerEnter()
      root.pointerMove(x, y - root.screenOffset())
      root.pointerPress(x, y - root.screenOffset(), Qt.LeftButton)
      return root.pressInfo ? root.pressInfo.key : ""
    }

    function move(x: real, y: real): string {
      root.pointerMove(x, y - root.screenOffset())
      return root.dragActive ? root.dragMode + " " + root.gapKey : "hover " + root.hoverKey
    }

    function release(x: real, y: real): string {
      root.pointerRelease(x, y - root.screenOffset(), Qt.LeftButton)
      return "ok"
    }

    // Quicar sem abrir nada (os webapps abririam na sessão real pelo uwsm).
    function bounce(index: int): string {
      var key = root.displayKeys[index]
      if (!key) return "no-item"
      root.beginLaunch(key)
      return key
    }

    function hover(x: real, y: real): string {
      root.pointerEnter()
      root.pointerMove(x, y - root.screenOffset())
      return root.hoverKey
    }

    function leave(): string {
      root.pointerExit()
      return "ok"
    }

    function menuActivate(index: int): string {
      if (!menu.menuShown || !menu.selectable(index)) return "no-row"
      menu.activated(index)
      return "ok"
    }

    function dismiss(): string {
      if (menu.dialog) menu.canceled()
      else if (menu.menuShown) menu.dismissed()
      return "ok"
    }

    function answer(confirm: bool): string {
      if (!menu.dialog) return "no-dialog"
      if (confirm) menu.confirmed()
      else menu.canceled()
      return "ok"
    }
  }
}
