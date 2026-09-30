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
import "Strings.js" as Strings
import "Library.js" as Library

// Launchpad do Pomarchy: todos os apps numa tela, sobre o papel de parede
// desfocado, com busca, páginas e a pinça de quatro dedos que acompanha os
// dedos. Overlay keepLoaded: fica montado desde a subida do shell (lista de
// apps e papel de parede prontos) e só mostra a janela quando abre.
Item {
  id: root

  // Contrato de overlay do Omarchy.
  property bool opened: false
  // Injetado pelo shell; o ambiente é o plano B.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

  // 0 = fechado, 1 = aberto. Anima no abrir/fechar e segue os dedos na pinça.
  // Sem Behavior: o gesto escreve direto e as animações são explícitas.
  property real progress: 0
  readonly property bool shown: opened || progress > 0 || gesture.active

  readonly property bool dark: Tokens.isDark(Color.background)
  readonly property bool available: settings.active && settings.get("launchpad.enabled", true) === true
  readonly property string lang: I18n.resolve(settings.get("language", "auto"), Quickshell.env("LANG"))
  readonly property bool testMode: Quickshell.env("POMAR_TEST") === "1"

  property var screenInfo: null
  property string query: ""
  readonly property bool searching: Library.words(Library.fold(query)).length > 0
  readonly property var apps: catalog.items
  readonly property var results: searching ? Library.search(apps, query) : []
  readonly property var shownItems: searching ? results : apps
  property int selected: 0
  property var menuItem: null
  property string lastLaunched: ""

  // ------------------------------------------------------------ medidas
  // Tudo sai do tamanho da tela (nunca do conteúdo): 96 px de ícone numa tela
  // de 1920x1200, grade de 7x5 em tela 16:10 grande e menos em telas menores.
  readonly property real sw: Math.max(640, screenInfo ? screenInfo.width : 1920)
  readonly property real sh: Math.max(480, screenInfo ? screenInfo.height : 1200)
  readonly property real dpr: screenInfo && screenInfo.devicePixelRatio > 0 ? screenInfo.devicePixelRatio : 1
  readonly property bool portrait: sh > sw
  // Referência 1920x1200 (ou 1200x1920 com a tela em pé).
  readonly property real unit: portrait ? Math.min(sw / 1200, sh / 1920) : Math.min(sw / 1920, sh / 1200)
  readonly property int iconSize: Math.round(Tokens.clamp(96 * unit, 56, 136))
  readonly property int labelGap: Math.round(Tokens.clamp(10 * unit, 6, 12))
  readonly property int labelHeight: Math.ceil(Style.font.body * 1.4)
  readonly property int searchHeight: Math.round(Tokens.clamp(30 * unit, 26, 34))
  readonly property int searchWidth: Math.round(Tokens.clamp(250 * unit, 200, 300))
  readonly property int searchTop: Math.round(Tokens.clamp(44 * unit, 24, 60))
  // O Dock do Pomarchy fica por cima do Launchpad, embaixo, como no Mac: os
  // pontinhos de página ficam logo acima dele.
  readonly property bool dockBelow: settings.get("dock.enabled", true) === true && settings.get("dock.position", "bottom") === "bottom"
  readonly property int dockReserve: dockBelow ? Math.round(Number(settings.get("dock.iconSize", 54)) + 34) : 0
  readonly property int dotsCenterY: Math.round(sh - dockReserve - Tokens.clamp(34 * unit, 22, 44))
  readonly property int gridTop: searchTop + searchHeight + Math.round(Tokens.clamp(48 * unit, 24, 64))
  readonly property int gridBottom: Math.round(dotsCenterY - Tokens.clamp(28 * unit, 16, 40))
  readonly property int blockHeight: iconSize + labelGap + labelHeight
  readonly property int minRowGap: Math.round(Tokens.clamp(28 * unit, 14, 40))
  readonly property int maxCols: portrait ? 5 : 7
  readonly property int maxRows: portrait ? 7 : 5
  readonly property real gridMaxWidth: Math.round(sw * (portrait ? 0.88 : 0.76))
  readonly property int cols: Math.max(3, Math.min(maxCols, Math.floor(gridMaxWidth / Math.round(iconSize * 1.6))))
  readonly property int rows: Math.max(2, Math.min(maxRows, Math.floor((gridBottom - gridTop) / (blockHeight + minRowGap))))
  readonly property int perPage: cols * rows
  readonly property real cellWidth: Math.floor(Math.min(gridMaxWidth / cols, iconSize * 2.3))
  readonly property real cellHeight: Math.floor((gridBottom - gridTop) / rows)
  readonly property real gridX: Math.round((sw - cellWidth * cols) / 2)
  readonly property real gridY: gridTop

  // Pinça: quanto os dedos precisam juntar (ou abrir) para ir de 0 a 1.
  readonly property real pinchInRange: 0.5
  readonly property real pinchOutRange: 0.6

  function tr(key) {
    return I18n.tr(Strings.TABLE, key, root.lang)
  }

  // ------------------------------------------------------------ abrir e fechar
  function focusedScreen() {
    var name = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    var list = Quickshell.screens || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].name === name) return list[i]
    }
    return list.length > 0 ? list[0] : null
  }

  // Antes de aparecer: tela com foco, papel de parede atualizado e busca limpa
  // (também quando reabre no meio da animação de saída).
  function prepare() {
    if (!root.shown) {
      var target = root.focusedScreen()
      if (target !== root.screenInfo) root.screenInfo = target
    }
    if (!root.opened) {
      root.resetSearch()
      root.dismissMenu()
    }
    backdrop.refresh()
  }

  function open(payloadJson) {
    if (!root.available) return
    if (root.opened && !gesture.active) return
    gesture.active = false
    root.prepare()
    root.opened = true
    root.animateTo(1, Tokens.motion.base + 40)
    events.send("overlay", "opened", "launchpad")
    Qt.callLater(root.focusSearch)
  }

  function close() {
    if (!root.shown) return
    gesture.active = false
    root.opened = false
    root.dismissMenu()
    root.animateTo(0, Tokens.motion.base + 40)
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function animateTo(value, duration) {
    progressAnimation.stop()
    progressAnimation.to = value
    progressAnimation.duration = Math.max(60, Math.round(duration))
    progressAnimation.start()
  }

  function focusSearch() {
    if (root.opened) searchPill.focusInput()
  }

  function resetSearch() {
    searchPill.clear()
    root.query = ""
    root.selected = 0
  }

  NumberAnimation {
    id: progressAnimation
    target: root
    property: "progress"
    easing.type: Easing.OutCubic
    onFinished: {
      // Fechou de vez: devolve a busca ao estado inicial para a próxima vez.
      if (!root.opened && root.progress <= 0) root.resetSearch()
    }
  }

  // ------------------------------------------------------------ gesto de pinça
  // `scale` é o do libinput: 1 no início, menor ao juntar os dedos, maior ao
  // abrir. Se o primeiro valor vier perto de 0, o compositor mandou a variação
  // relativa (escala - 1) e a conta usa 1 + valor.
  QtObject {
    id: gesture

    property bool active: false
    property bool fromOpen: false
    property real startProgress: 0
    property bool hasFirst: false
    property bool relative: false
    property double lastTime: 0
    property real lastProgress: 0
    property real velocity: 0
  }

  function gestureBegin() {
    if (!root.available) return
    progressAnimation.stop()
    root.prepare()
    gesture.fromOpen = root.opened
    gesture.startProgress = root.progress
    gesture.hasFirst = false
    gesture.relative = false
    gesture.velocity = 0
    gesture.lastTime = Date.now()
    gesture.lastProgress = root.progress
    gesture.active = true
  }

  function gestureScale(text) {
    if (!gesture.active) return
    var value = Number(text)
    if (!isFinite(value)) return
    if (!gesture.hasFirst) {
      gesture.hasFirst = true
      gesture.relative = Math.abs(value) < 0.5
    }
    var scale = gesture.relative ? 1 + value : value
    var next = gesture.fromOpen
      ? gesture.startProgress - Math.max(0, scale - 1) / root.pinchOutRange
      : gesture.startProgress + Math.max(0, 1 - scale) / root.pinchInRange
    next = Tokens.clamp(next, 0, 1)
    var now = Date.now()
    var seconds = Math.max(0.004, (now - gesture.lastTime) / 1000)
    gesture.velocity = gesture.velocity * 0.5 + ((next - gesture.lastProgress) / seconds) * 0.5
    gesture.lastTime = now
    gesture.lastProgress = next
    root.progress = next
  }

  function gestureEnd(cancelled) {
    if (!gesture.active) return
    gesture.active = false
    var p = root.progress
    // Dedos parados antes de soltar: a velocidade não conta mais.
    var velocity = Date.now() - gesture.lastTime > 140 ? 0 : gesture.velocity
    var stayOpen
    if (cancelled) stayOpen = gesture.fromOpen
    else if (gesture.fromOpen) stayOpen = (1 - p) < 0.35 && velocity > -1.6
    else stayOpen = p > 0.35 || velocity > 1.6
    var remaining = Math.abs((stayOpen ? 1 : 0) - p)
    var duration = Tokens.clamp((Tokens.motion.base + 40) * Math.max(remaining, 0.35), 110, Tokens.motion.base + 40)
    if (stayOpen) {
      var wasOpen = root.opened
      root.opened = true
      root.animateTo(1, duration)
      if (!wasOpen) events.send("overlay", "opened", "launchpad")
      Qt.callLater(root.focusSearch)
    } else {
      root.opened = false
      root.dismissMenu()
      root.animateTo(0, duration)
    }
  }

  // ------------------------------------------------------------ apps
  function launchItem(item) {
    // Fechando já: o segundo clique de um duplo clique não abre o app de novo.
    if (!item || !item.id || !root.opened) return
    root.lastLaunched = item.id
    if (root.testMode) {
      // Nos testes o app não abre de verdade (o uwsm-app falaria com a sessão
      // real); fica registrado no log o que seria executado.
      console.info("POMAR_TEST launchpad launch uwsm-app -- gtk-launch " + item.id + ".desktop")
    } else {
      Apps.launch(Quickshell, item.id)
    }
    root.close()
  }

  function activateIndex(index) {
    var list = root.shownItems
    if (index < 0 || index >= list.length) return
    root.launchItem(list[index])
  }

  function activePages() {
    return root.searching ? resultPages : appPages
  }

  function setSelection(index) {
    if (!root.searching || root.results.length === 0) return
    root.selected = Math.max(0, Math.min(root.results.length - 1, index))
    resultPages.goTo(resultPages.pageOf(root.selected))
  }

  function moveSelection(dx, dy) {
    if (!root.searching || root.results.length === 0) return
    var next = root.selected + dx + dy * root.cols
    if (next < 0 || next >= root.results.length) {
      // Para cima ou para baixo além da grade: fica onde está.
      if (dy !== 0) return
      next = Math.max(0, Math.min(root.results.length - 1, next))
    }
    root.setSelection(next)
  }

  function flipPage(delta) {
    var pages = root.activePages()
    pages.step(delta)
    if (root.searching && root.results.length > 0) root.selected = Math.min(root.results.length - 1, pages.page * root.perPage)
  }

  onQueryChanged: {
    root.selected = 0
    resultPages.jumpTo(0)
  }

  // ------------------------------------------------------------ teclado
  function handleKey(event) {
    var key = event.key
    if (menu.shown) {
      if (key === Qt.Key_Escape) root.dismissMenu()
      else if (key === Qt.Key_Down || key === Qt.Key_Tab) menu.move(1)
      else if (key === Qt.Key_Up || key === Qt.Key_Backtab) menu.move(-1)
      else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) menu.trigger()
      event.accepted = true
      return
    }
    if (key === Qt.Key_Escape) {
      if (root.query.length > 0) root.resetSearch()
      else root.close()
      event.accepted = true
    } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      if (root.searching && root.results.length > 0) root.launchItem(root.results[root.selected])
      event.accepted = true
    } else if (key === Qt.Key_PageDown) {
      root.flipPage(1)
      event.accepted = true
    } else if (key === Qt.Key_PageUp) {
      root.flipPage(-1)
      event.accepted = true
    } else if (key === Qt.Key_Left || key === Qt.Key_Right) {
      var dx = key === Qt.Key_Left ? -1 : 1
      if (root.searching) root.moveSelection(dx, 0)
      else root.flipPage(dx)
      event.accepted = true
    } else if (key === Qt.Key_Up || key === Qt.Key_Down) {
      if (root.searching) root.moveSelection(0, key === Qt.Key_Up ? -1 : 1)
      event.accepted = true
    } else if ((key === Qt.Key_Home || key === Qt.Key_End) && !root.searching) {
      appPages.goTo(key === Qt.Key_Home ? 0 : appPages.pageCount - 1)
      event.accepted = true
    } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      event.accepted = true
    }
  }

  // ------------------------------------------------------------ menu do app
  function favorites() {
    var list = settings.get("dock.favorites", [])
    return Array.isArray(list) ? list.slice() : []
  }

  function hiddenList() {
    var list = settings.get("launchpad.hidden", [])
    return Array.isArray(list) ? list.slice() : []
  }

  function openMenu(item, sceneX, sceneY) {
    if (!item || !item.id || !root.opened) return
    var inDock = root.favorites().indexOf(item.id) !== -1
    root.menuItem = item
    menu.entries = [
      { key: "open", text: root.tr("open"), separator: false },
      { key: inDock ? "removeFromDock" : "keepInDock", text: root.tr(inDock ? "removeFromDock" : "keepInDock"), separator: true },
      { key: "hide", text: root.tr("hideFromLaunchpad"), separator: false }
    ]
    menu.anchorX = sceneX
    menu.anchorY = sceneY
    menu.current = -1
    menu.shown = true
  }

  function openMenuForIndex(index) {
    var list = root.shownItems
    if (index < 0 || index >= list.length) return
    var pages = root.activePages()
    pages.goTo(pages.pageOf(index))
    var local = index % root.perPage
    var x = root.gridX + (local % root.cols) * root.cellWidth + root.cellWidth / 2
    var y = root.gridY + Math.floor(local / root.cols) * root.cellHeight + root.cellHeight / 2
    root.openMenu(list[index], x, y)
  }

  function dismissMenu() {
    menu.shown = false
    menu.current = -1
    if (root.opened) Qt.callLater(root.focusSearch)
  }

  function menuChosen(key) {
    var item = root.menuItem
    root.dismissMenu()
    if (!item) return
    if (key === "open") {
      root.launchItem(item)
    } else if (key === "keepInDock") {
      var list = root.favorites()
      if (list.indexOf(item.id) === -1) list.push(item.id)
      settings.set("dock.favorites", list)
    } else if (key === "removeFromDock") {
      settings.set("dock.favorites", root.favorites().filter(function(id) { return id !== item.id }))
    } else if (key === "hide") {
      var hidden = root.hiddenList()
      if (hidden.indexOf(item.id) === -1) hidden.push(item.id)
      settings.set("launchpad.hidden", hidden)
    }
  }

  // ------------------------------------------------------------ serviços
  PomarSettings { id: settings }

  PomarEvents {
    id: events
    onCommand: function(target, verb, arg) {
      if (target === "overlay") {
        // Outro overlay do Pomarchy abriu: sai da frente.
        if (verb === "opened" && arg !== "launchpad" && root.shown) root.close()
        return
      }
      if (target !== "launchpad") return
      if (verb === "toggle") root.toggle()
      else if (verb === "open") root.open("{}")
      else if (verb === "close") root.close()
      else if (verb === "begin") root.gestureBegin()
      else if (verb === "scale") root.gestureScale(arg)
      else if (verb === "end") root.gestureEnd(arg === "1")
    }
  }

  onAvailableChanged: if (!root.available) root.close()

  Catalog {
    id: catalog
    omarchyPath: root.omarchyPath
    hiddenIds: settings.get("launchpad.hidden", [])
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      if (!root.shown) root.screenInfo = root.focusedScreen()
    }
  }

  Component.onCompleted: root.screenInfo = root.focusedScreen()

  // ------------------------------------------------------------ janela
  PanelWindow {
    id: panel

    screen: root.screenInfo
    visible: root.shown
    color: "transparent"
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "pomar-launchpad"
    WlrLayershell.layer: WlrLayer.Overlay
    // Teclado só com o Launchpad aberto de fato: durante a pinça e a animação
    // de saída a digitação continua indo para o app de baixo.
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Sem abrir de fato (pinça em andamento, animação de saída), o mouse
    // atravessa a tela.
    mask: root.opened ? null : passThrough

    Region { id: passThrough }

    onVisibleChanged: if (visible) Qt.callLater(root.focusSearch)

    Item {
      id: scene
      anchors.fill: parent

      // Tudo menos o menu: é também a fonte do vidro desfocado do menu.
      Item {
        id: content
        anchors.fill: parent

        Backdrop {
          id: backdrop
          anchors.fill: parent
          dark: root.dark
          decodeWidth: Math.round(root.sw / 2)
          decodeHeight: Math.round(root.sh / 2)
          opacity: root.progress
        }

        // Grade: vem de 1,12x para 1x com o esmaecer, como no Mac.
        Item {
          id: stage
          anchors.fill: parent
          opacity: root.progress
          scale: Tokens.lerp(1.12, 1.0, root.progress)
          transformOrigin: Item.Center

          AppPages {
            id: appPages
            anchors.fill: parent
            items: root.apps
            cols: root.cols
            perPage: root.perPage
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            gridX: root.gridX
            gridY: root.gridY
            iconSize: root.iconSize
            labelGap: root.labelGap
            devicePixelRatio: root.dpr
            dragEnabled: root.opened && !menu.shown
            enabled: !root.searching
            opacity: root.searching ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic } }
            onActivated: function(index) { root.launchItem(root.apps[index]) }
            onMenuRequested: function(index, sceneX, sceneY) { root.openMenu(root.apps[index], sceneX, sceneY) }
            onEmptyClicked: root.close()
          }

          AppPages {
            id: resultPages
            anchors.fill: parent
            items: root.results
            cols: root.cols
            perPage: root.perPage
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            gridX: root.gridX
            gridY: root.gridY
            iconSize: root.iconSize
            labelGap: root.labelGap
            devicePixelRatio: root.dpr
            selectedIndex: root.selected
            showSelection: true
            dragEnabled: root.opened && !menu.shown
            enabled: root.searching
            opacity: root.searching ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic } }
            onActivated: function(index) { root.launchItem(root.results[index]) }
            onMenuRequested: function(index, sceneX, sceneY) { root.openMenu(root.results[index], sceneX, sceneY) }
            onEmptyClicked: root.close()
          }
        }

        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          y: Math.round((root.gridTop + root.gridBottom) / 2 - height / 2)
          width: Math.min(parent.width - 80, 520)
          spacing: 8
          opacity: root.searching && root.results.length === 0 ? root.progress : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: Tokens.motion.fast } }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.tr("noResults")
            textFormat: Text.PlainText
            color: Tokens.label(true)
            font.family: Style.fontFamily
            font.pixelSize: Style.font.display
            font.weight: Font.DemiBold
            style: Text.Raised
            styleColor: Tokens.shadow(true)
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.tr("noResultsHint")
            textFormat: Text.PlainText
            color: Tokens.secondaryLabel(true)
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        SearchPill {
          id: searchPill
          width: root.searchWidth
          height: root.searchHeight
          x: Math.round((parent.width - width) / 2)
          y: root.searchTop
          opacity: root.progress
          placeholder: root.tr("search")
          clearLabel: root.tr("clearSearch")
          onTextChanged: root.query = text
          onKeyPressed: function(event) { root.handleKey(event) }
        }

        PageDots {
          anchors.horizontalCenter: parent.horizontalCenter
          y: Math.round(root.dotsCenterY - height / 2)
          opacity: root.progress
          dotSize: Math.round(Tokens.clamp(8 * root.unit, 7, 10))
          count: root.searching ? resultPages.pageCount : appPages.pageCount
          current: root.searching ? resultPages.page : appPages.page
          lang: root.lang
          onPicked: function(index) { root.activePages().goTo(index) }
        }
      }

      // Com o menu aberto, um clique fora dele só fecha o menu.
      MouseArea {
        anchors.fill: parent
        visible: menu.shown
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.dismissMenu()
        onWheel: function(wheel) { wheel.accepted = true }
      }

      AppMenu {
        id: menu
        dark: root.dark
        blurSource: content
        onChosen: function(key) { root.menuChosen(key) }
      }
    }
  }

  // ------------------------------------------------------------ testes
  // Só existe com POMAR_TEST=1 (o harness sobe o shell assim): clique e gesto
  // de verdade não dão para simular no Hyprland aninhado.
  IpcHandler {
    target: "pomar-launchpad-test"
    enabled: root.testMode

    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        shown: root.shown,
        progress: Math.round(root.progress * 1000) / 1000,
        available: root.available,
        lang: root.lang,
        screen: root.screenInfo ? root.screenInfo.name : "",
        apps: root.apps.length,
        firstApps: root.apps.slice(0, 8).map(function(item) { return item.name }),
        pageCount: appPages.pageCount,
        page: appPages.page,
        query: root.query,
        searching: root.searching,
        results: root.results.length,
        firstResults: root.results.slice(0, 5).map(function(item) { return item.name }),
        selected: root.selected,
        resultPage: resultPages.page,
        cols: root.cols,
        rows: root.rows,
        iconSize: root.iconSize,
        cell: [root.cellWidth, root.cellHeight],
        grid: [root.gridX, root.gridY],
        menu: menu.shown,
        menuEntries: menu.entries.map(function(entry) { return entry.key }),
        focus: searchPill.hasFocus,
        wallpaper: backdrop.path,
        wallpaperReady: backdrop.ready,
        favorites: root.favorites(),
        hidden: root.hiddenList(),
        lastLaunched: root.lastLaunched,
        builds: catalog.builds
      })
    }

    function open(): void { root.open("{}") }
    function close(): void { root.close() }
    function type(text: string): void { searchPill.text = searchPill.text + text }
    function clear(): void { root.resetSearch() }
    function select(index: int): void { root.setSelection(index) }
    function activate(index: int): void { root.activateIndex(index) }
    function page(index: int): void { root.activePages().goTo(index) }
    function contextMenu(index: int): void { root.openMenuForIndex(index) }
    function menuChoose(key: string): void { if (menu.shown) root.menuChosen(key) }
    function progress(value: real): void {
      progressAnimation.stop()
      if (!root.shown) root.prepare()
      root.progress = Tokens.clamp(value, 0, 1)
    }
  }
}
