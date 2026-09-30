import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "shared"
import "shared/Tokens.js" as Tokens
import "shared/I18n.js" as I18n
import "shared/Apps.js" as Apps
import "Strings.js" as S
import "ui"

// Ajustes do Pomarchy e boas-vindas. Painel sob demanda: o shell carrega este
// arquivo no `summon` e chama open(payload); `{"page": "welcome"}` abre as
// boas-vindas, `{"page": "dock"}` (etc.) abre os Ajustes naquela página.
//
// Os Ajustes são duas superfícies: o véu escuro (tela toda, sem desfoque,
// fecha ao clicar, e é onde a sombra da janela é desenhada) e a janela
// central na camada pomar-settings, que o Hyprland desfoca atrás do vidro.
// As boas-vindas são uma superfície de tela cheia.
Item {
  id: root

  // Injetados pelo shell do Omarchy ao carregar o painel.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool surfacesVisible: false
  property string mode: "settings"
  property string page: "geral"
  property int step: 0
  readonly property int stepCount: 6
  readonly property var pages: ["geral", "dock", "barra", "mission", "trackpad", "teclado", "sobre"]

  readonly property bool testMode: Quickshell.env("POMAR_TEST") === "1"
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "pomar.settings"
  readonly property string lang: I18n.resolve(settings.get("language", "auto"), Quickshell.env("LANG"))
  // Endereço provisório: trocar pelo repositório público quando existir.
  readonly property string projectUrl: "https://example.com/pomar"

  PomarSettings { id: settings }

  PomarEvents {
    id: events
    onCommand: function(target, verb, arg) {
      if (target === "settings") {
        // Pelo barramento vale a regra do contrato: sem Pomarchy ativo, nada abre.
        if (!settings.active && verb !== "close") return
        if (verb === "toggle") root.opened ? root.close() : root.open(arg ? JSON.stringify({ page: arg }) : "{}")
        else if (verb === "open") root.open(arg ? JSON.stringify({ page: arg }) : "{}")
        else if (verb === "close") root.close()
      } else if (target === "overlay" && verb === "opened" && arg !== "settings" && root.opened) {
        // Outro overlay do Pomarchy abriu por cima: os Ajustes saem da frente.
        root.close()
      }
    }
  }

  // ---------------------------------------------------------------- textos
  function t(key) {
    var args = [S.TABLE, key, root.lang]
    for (var i = 1; i < arguments.length; i++) args.push(arguments[i])
    return I18n.tr.apply(null, args)
  }

  function fingersText(count) {
    return root.t(Number(count) === 4 ? "fingers.4" : "fingers.3")
  }

  function fileUrl(path) {
    return Util.fileUrl(path)
  }

  // ---------------------------------------------------------------- abrir e fechar
  // Chamado pelo shell no summon. Aqui não se exige Pomarchy ativo: quem pediu
  // os Ajustes explicitamente precisa conseguir ligar "manter em qualquer tema".
  function open(payloadJson) {
    var payload = {}
    try {
      var parsed = JSON.parse(String(payloadJson || "{}"))
      if (parsed && typeof parsed === "object") payload = parsed
    } catch (error) {
      payload = {}
    }
    var wanted = String(payload.page || "")
    // Saiu das boas-vindas por outro caminho (pediram os Ajustes): conta como vista.
    if (root.opened && root.mode === "welcome" && wanted !== "welcome") settings.set("welcome.seen", true)
    if (wanted === "welcome") {
      root.mode = "welcome"
      root.step = 0
    } else {
      root.mode = "settings"
      if (root.pages.indexOf(wanted) !== -1) root.page = wanted
    }
    closeTimer.stop()
    root.targetScreen = root.focusedScreen()
    root.surfacesVisible = true
    root.focusPrimed = false
    root.opened = true
    primeTimer.restart()
    Qt.callLater(root.focusContent)
    refreshWallpaper()
    events.send("overlay", "opened", "settings")
    return root.mode + ":" + (root.mode === "welcome" ? root.step : root.page)
  }

  function close() {
    if (!root.opened) return
    if (root.mode === "welcome") settings.set("welcome.seen", true)
    root.flushLive()
    root.opened = false
    closeTimer.restart()
  }

  function toggle() {
    root.opened ? root.close() : root.open("{}")
  }

  function goTo(name) {
    if (root.pages.indexOf(name) === -1) return
    root.page = name
  }

  function openWelcome() {
    root.step = 0
    root.mode = "welcome"
    root.focusPrimed = false
    primeTimer.restart()
    Qt.callLater(root.focusContent)
  }

  // ---------------------------------------------------------------- boas-vindas
  function next() {
    if (root.step < root.stepCount - 1) root.step++
    else root.finish(false)
  }

  function back() {
    if (root.step > 0) root.step--
  }

  function goToStep(index) {
    root.step = Tokens.clamp(Math.round(index), 0, root.stepCount - 1)
  }

  // Fim das boas-vindas: marca como vista; "Abrir Ajustes" segue para a
  // página Geral sem fechar a sessão.
  function finish(openSettings) {
    settings.set("welcome.seen", true)
    if (openSettings) {
      root.mode = "settings"
      root.page = "geral"
      root.focusPrimed = false
      primeTimer.restart()
      Qt.callLater(root.focusContent)
    } else {
      root.close()
    }
  }

  // ---------------------------------------------------------------- ajustes
  function get(key, fallback) {
    return settings.get(key, fallback)
  }

  // O hypr/pomar.lua lê estes ajustes ao carregar: depois de mudar, o
  // Hyprland precisa reler a configuração para gestos e atalhos valerem.
  function needsReload(key) {
    return key === "alwaysOn" || key.indexOf("gestures.") === 0 || key.indexOf("keys.") === 0
      || key === "mission.enabled" || key === "launchpad.enabled" || key === "switcher.enabled"
      || key === "dock.enabled" || key === "windowControls.enabled"
  }

  function set(key, value) {
    settings.set(key, value)
    if (root.needsReload(key)) reloadTimer.restart()
    // Ligar ou desligar o Pomarchy fora dos temas dele troca também a barra.
    if (key === "alwaysOn") barTimer.restart()
  }

  // Valores ao vivo das réguas: a prévia acompanha o dedo e o arquivo é
  // regravado no máximo algumas vezes por segundo (os outros plugins relêem
  // o arquivo a cada gravação).
  property var liveValues: ({})
  property var pendingLive: ({})

  function live(key, fallback) {
    return key in root.liveValues ? root.liveValues[key] : settings.get(key, fallback)
  }

  function setLive(key, value) {
    var next = Object.assign({}, root.liveValues)
    next[key] = value
    root.liveValues = next
    var pending = Object.assign({}, root.pendingLive)
    pending[key] = value
    root.pendingLive = pending
    if (!liveTimer.running) liveTimer.start()
  }

  function commitLive(key, value) {
    var pending = Object.assign({}, root.pendingLive)
    delete pending[key]
    root.pendingLive = pending
    if (settings.get(key, null) !== value) root.set(key, value)
    var next = Object.assign({}, root.liveValues)
    delete next[key]
    root.liveValues = next
  }

  function flushLive() {
    liveTimer.stop()
    for (var key in root.pendingLive)
      if (settings.get(key, null) !== root.pendingLive[key]) root.set(key, root.pendingLive[key])
    root.pendingLive = ({})
    root.liveValues = ({})
  }

  Timer {
    id: liveTimer
    interval: 140
    onTriggered: {
      for (var key in root.pendingLive)
        if (settings.get(key, null) !== root.pendingLive[key]) settings.set(key, root.pendingLive[key])
      root.pendingLive = ({})
    }
  }

  Timer {
    id: reloadTimer
    interval: 450
    onTriggered: root.run(["hyprctl", "reload"])
  }

  Timer {
    id: barTimer
    interval: 450
    onTriggered: root.run(["pomar", "bar", "auto"])
  }

  // ---------------------------------------------------------------- comandos
  // Todo comando externo passa por aqui. Nos testes (POMAR_TEST=1) nenhum
  // roda: só aparece no log como POMAR_RUN (o harness não isola tudo do
  // sistema real). Fora dos testes, o hyprctl vai direto e os outros por um
  // bash de login (Util.execArgv), como o Omarchy faz: o PATH do shell pode
  // não ter ~/.local/bin nem os comandos do Omarchy.
  function run(argv) {
    if (root.testMode) {
      console.log("POMAR_RUN " + JSON.stringify(argv))
      return
    }
    if (argv[0] === "hyprctl") Quickshell.execDetached(argv)
    else Util.execArgv(argv)
  }

  // ---------------------------------------------------------------- aparência
  property string pendingTheme: ""
  readonly property string appearance: {
    var name = root.pendingTheme || settings.themeName
    // "pomar" e "pomar-escuro" são os nomes de antes do Pomarchy OS.
    if (name === "pomarchy" || name === "pomar") return "light"
    if (name === "pomarchy-escuro" || name === "pomar-escuro") return "dark"
    return ""
  }

  function chooseAppearance(dark) {
    var name = dark ? "pomarchy-escuro" : "pomarchy"
    if (name === settings.themeName && !root.pendingTheme) return
    root.pendingTheme = name
    pendingThemeTimer.restart()
    root.run(["omarchy", "theme", "set", name])
  }

  // Se a troca de tema não acontecer, a seleção volta ao tema real.
  Timer {
    id: pendingThemeTimer
    interval: 12000
    onTriggered: root.pendingTheme = ""
  }

  Connections {
    target: settings
    function onThemeNameChanged() {
      if (settings.themeName === root.pendingTheme) root.pendingTheme = ""
      Theme.reload()
      root.refreshWallpaper()
    }
    function onActiveChanged() {
      if (!settings.active && root.opened) inactiveTimer.restart()
      else inactiveTimer.stop()
    }
  }

  // Pomarchy desligado (tema de fora e sem "manter"): nada do Pomarchy na tela. A
  // espera cobre a troca de tema, em que o theme.name fica vazio por um instante.
  Timer {
    id: inactiveTimer
    interval: 1500
    onTriggered: if (!settings.active && root.opened) root.close()
  }

  // Primeira imagem de cada tema Pomarchy, para as miniaturas de aparência.
  function themeWallpaper(name) {
    var model = name === "pomarchy-escuro" ? darkBackgrounds : lightBackgrounds
    if (model.count > 0) return Util.fileUrl(model.get(0, "filePath"))
    return Theme.wallpaperUrl
  }

  FolderListModel {
    id: lightBackgrounds
    folder: Util.fileUrl(root.home + "/.config/omarchy/themes/pomarchy/backgrounds")
    nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
    showDirs: false
    sortField: FolderListModel.Name
  }

  FolderListModel {
    id: darkBackgrounds
    folder: Util.fileUrl(root.home + "/.config/omarchy/themes/pomarchy-escuro/backgrounds")
    nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
    showDirs: false
    sortField: FolderListModel.Name
  }

  // ---------------------------------------------------------------- papel de parede
  property alias wallpapers: wallpaperModel
  readonly property int wallpaperCount: wallpaperModel.count
  property string currentWallpaper: ""

  FolderListModel {
    id: wallpaperModel
    folder: Util.fileUrl(root.home + "/.local/state/omarchy/current/theme/backgrounds")
    nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG"]
    showDirs: false
    sortField: FolderListModel.Name
  }

  function isCurrentWallpaper(fileName) {
    var current = String(root.currentWallpaper || "")
    return current.length > 0 && current.split("/").pop() === String(fileName)
  }

  function chooseWallpaper(path) {
    if (!path) return
    root.currentWallpaper = String(path)
    Theme.wallpaperPath = String(path)
    root.run(["omarchy", "theme", "bg", "set", String(path)])
    wallpaperRecheck.restart()
  }

  function refreshWallpaper() {
    if (!wallpaperProc.running) wallpaperProc.running = true
  }

  Process {
    id: wallpaperProc
    command: ["readlink", "-f", root.home + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      onStreamFinished: {
        var path = String(text || "").trim()
        if (!path) return
        root.currentWallpaper = path
        Theme.wallpaperPath = path
      }
    }
  }

  Timer {
    id: wallpaperRecheck
    interval: 1500
    onTriggered: root.refreshWallpaper()
  }

  // ---------------------------------------------------------------- barra no estilo Mac
  // O comando `pomar` (bin/pomar, instalado em ~/.local/bin) troca o layout da
  // barra. O estado vem do shell.json do Omarchy: com o widget do Pomarchy na
  // barra, ela está no estilo Mac.
  property string cliPath: ""
  readonly property bool cliAvailable: cliPath !== ""
  property bool barMac: false
  property bool barPending: false

  FileView {
    id: cliProbe
    path: root.home + "/.local/bin/pomar"
    printErrors: false
    onLoaded: root.cliPath = path
    onLoadFailed: root.cliPath = ""
  }

  FileView {
    id: shellConfig
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.readBarState(text())
    onFileChanged: reload()
  }

  function readBarState(text) {
    var found = false
    try {
      var config = JSON.parse(String(text || "{}"))
      var layout = config && config.bar && config.bar.layout ? config.bar.layout : {}
      for (var section in layout) {
        var list = layout[section]
        if (!Array.isArray(list)) continue
        for (var i = 0; i < list.length; i++)
          if (list[i] && list[i].id === "pomar.menubar") found = true
      }
    } catch (error) {
      found = false
    }
    root.barMac = found
    root.barPending = false
  }

  function toggleBarMac() {
    if (!root.cliAvailable || root.barPending) return
    root.barPending = true
    barPendingTimer.restart()
    root.run([root.cliPath, "bar", root.barMac ? "restore" : "mac"])
  }

  Timer {
    id: barPendingTimer
    interval: 8000
    onTriggered: root.barPending = false
  }

  // ---------------------------------------------------------------- Dock
  readonly property var favorites: {
    var list = settings.get("dock.favorites", [])
    return Array.isArray(list) ? list : []
  }

  function appEntry(id) {
    return id === "pomar:launchpad" ? null : Apps.entryFor(DesktopEntries, id)
  }

  function appName(id, entry) {
    return id === "pomar:launchpad" ? I18n.tr(S.TABLE, "launchpad", root.lang) : Apps.displayName(entry, id)
  }

  function removeFavorite(index) {
    var list = root.favorites.slice()
    if (index < 0 || index >= list.length) return
    list.splice(index, 1)
    root.set("dock.favorites", list)
  }

  function moveFavorite(index, delta) {
    var list = root.favorites.slice()
    var target = index + delta
    if (index < 0 || index >= list.length || target < 0 || target >= list.length) return
    var item = list.splice(index, 1)[0]
    list.splice(target, 0, item)
    root.set("dock.favorites", list)
  }

  // ---------------------------------------------------------------- sobre
  property string installedVersion: ""
  readonly property string version: installedVersion || (manifest && manifest.version ? String(manifest.version) : "")
  readonly property string author: manifest && manifest.author ? String(manifest.author) : "Bruno Moniz"

  FileView {
    path: root.home + "/.local/share/pomar/current/VERSION"
    printErrors: false
    onLoaded: root.installedVersion = String(text() || "").trim()
  }

  function openProject() {
    root.run(["xdg-open", root.projectUrl])
  }

  // ---------------------------------------------------------------- telas
  property var targetScreen: null
  readonly property real screenWidth: targetScreen ? targetScreen.width : 1280
  readonly property real screenHeight: targetScreen ? targetScreen.height : 800
  readonly property int cardWidth: Math.round(Math.min(980, screenWidth - 48))
  readonly property int cardHeight: Math.round(Math.min(640, screenHeight - 72))

  function focusedScreen() {
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++)
      if (list[i].name === name) return list[i]
    return list.length > 0 ? list[0] : null
  }

  // Foco de teclado: um instante em Exclusive para pegar o teclado ao abrir
  // (mesmo reaproveitando a superfície), depois OnDemand para não prender
  // cliques do resto da tela. Mesmo esquema do KeyboardPanel do Omarchy.
  property bool focusPrimed: false
  readonly property int keyboardMode: root.opened
    ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  Timer {
    id: primeTimer
    interval: 75
    onTriggered: if (root.opened) root.focusPrimed = true
  }

  function focusContent() {
    if (!root.opened) return
    var view = root.mode === "welcome" ? welcomeLoader.item : settingsLoader.item
    if (view) view.forceActiveFocus()
  }

  onModeChanged: Qt.callLater(root.focusContent)

  // Depois do esmaecer, some com as superfícies e pede ao shell para
  // descarregar o painel (ele chama close() de novo, que já não faz nada).
  Timer {
    id: closeTimer
    interval: Tokens.motion.base + 60
    onTriggered: {
      root.surfacesVisible = false
      if (root.shell && typeof root.shell.hide === "function") {
        var id = root.pluginId
        var host = root.shell
        Qt.callLater(function() { host.hide(id) })
      }
    }
  }

  // ---------------------------------------------------------------- véu
  PanelWindow {
    id: veilWindow
    screen: root.targetScreen
    visible: root.surfacesVisible && root.mode === "settings"
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "pomar-settings-veil"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
      anchors.fill: parent
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Tokens.motion.base; easing.type: Easing.OutCubic } }

      Rectangle {
        anchors.fill: parent
        color: Tokens.scrim(Theme.dark, 0.6)
      }

      // Sombra da janela, aqui para não ganhar o desfoque da camada da janela.
      // Recortada no formato da janela: por baixo do vidro ela escureceria a
      // barra lateral.
      Item {
        id: veilShadow
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskInverted: true
          maskSource: veilHole
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
        }

        RectangularShadow {
          x: Math.round((parent.width - root.cardWidth) / 2)
          y: Math.round((parent.height - root.cardHeight) / 2)
          width: root.cardWidth
          height: root.cardHeight
          radius: Theme.windowRadius
          blur: 48
          spread: -6
          offset.y: 18
          color: Tokens.withAlpha(Theme.shadow, Theme.dark ? 0.75 : 0.42)
        }
      }

      Item {
        id: veilHole
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle {
          x: Math.round((parent.width - root.cardWidth) / 2)
          y: Math.round((parent.height - root.cardHeight) / 2)
          width: root.cardWidth
          height: root.cardHeight
          radius: Theme.windowRadius
          color: "black"
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  // ---------------------------------------------------------------- janela
  PanelWindow {
    id: cardWindow
    screen: root.targetScreen
    visible: veilWindow.visible
    color: "transparent"
    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "pomar-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.mode === "settings" ? root.keyboardMode : WlrKeyboardFocus.None

    // Só existe com a janela na tela: montar escondido deixaria a criação
    // pela metade (a janela invisível não desenha, e a criação assíncrona do
    // shell não termina).
    Loader {
      id: settingsLoader
      anchors.fill: parent
      focus: true
      active: cardWindow.visible
      sourceComponent: SettingsView {
        app: root
        focus: true
        opacity: root.opened ? 1 : 0
        scale: root.opened ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.base; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Tokens.motion.slow; easing.type: Easing.OutQuint } }
      }
      onLoaded: Qt.callLater(root.focusContent)
    }
  }

  // ---------------------------------------------------------------- boas-vindas
  PanelWindow {
    id: welcomeWindow
    screen: root.targetScreen
    visible: root.surfacesVisible && root.mode === "welcome"
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "pomar-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.mode === "welcome" ? root.keyboardMode : WlrKeyboardFocus.None

    Loader {
      id: welcomeLoader
      anchors.fill: parent
      focus: true
      active: welcomeWindow.visible
      sourceComponent: WelcomeView {
        app: root
        focus: true
      }
      onLoaded: Qt.callLater(root.focusContent)
    }
  }

  // ---------------------------------------------------------------- ganchos de teste
  // Clique não dá para simular no harness: estes ganchos fazem o mesmo que os
  // cliques e só existem com POMAR_TEST=1.
  IpcHandler {
    target: "pomar-settings-test"
    enabled: root.testMode

    function page(name: string): string {
      return root.open(JSON.stringify({ page: name }))
    }
    function scroll(y: real): string {
      var view = settingsLoader.item
      if (!view) return "-1"
      view.scrollTo(y)
      return String(view.page ? view.page.contentY : -1)
    }
    function step(index: int): string {
      root.goToStep(index)
      return String(root.step)
    }
    function next(): string {
      root.next()
      return String(root.step)
    }
    function back(): string {
      root.back()
      return String(root.step)
    }
    function set(key: string, json: string): string {
      var value = null
      try { value = JSON.parse(json) } catch (error) { return "bad json" }
      root.set(key, value)
      return JSON.stringify(settings.get(key, null))
    }
    function cli(path: string): string {
      root.cliPath = path
      return root.cliPath
    }
    function click(action: string): string {
      var parts = String(action).split(":")
      var verb = parts[0]
      var arg = parts.slice(1).join(":")
      if (verb === "close") root.close()
      else if (verb === "veil") root.close()
      else if (verb === "appearance") root.chooseAppearance(arg === "dark")
      else if (verb === "wallpaper") root.chooseWallpaper(wallpaperModel.get(Number(arg), "filePath"))
      else if (verb === "barMac") root.toggleBarMac()
      else if (verb === "welcome") root.openWelcome()
      else if (verb === "finish") root.finish(arg === "settings")
      else if (verb === "remove") root.removeFavorite(Number(arg))
      else if (verb === "move") root.moveFavorite(Number(parts[1]), Number(parts[2]))
      else if (verb === "project") root.openProject()
      else if (verb === "live") root.setLive(parts[1], Number(parts[2]))
      else if (verb === "commit") root.commitLive(parts[1], Number(parts[2]))
      else return "unknown"
      return "ok"
    }
    function state(): string {
      return JSON.stringify({
        opened: root.opened, visible: root.surfacesVisible, mode: root.mode, page: root.page,
        step: root.step, lang: root.lang, dark: Theme.dark, theme: settings.themeName,
        active: settings.active, welcomeSeen: settings.get("welcome.seen", false),
        cli: root.cliPath, barMac: root.barMac, wallpaper: root.currentWallpaper,
        wallpapers: wallpaperModel.count, version: root.version, favorites: root.favorites,
        gestures: settings.get("gestures", null), keys: settings.get("keys", null), appearance: root.appearance
      })
    }
  }
}
