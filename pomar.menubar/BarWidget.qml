import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "shared"
import "shared/Tokens.js" as Tokens
import "shared/Apps.js" as Apps
import "shared/I18n.js" as I18n
import "Strings.js" as Strings

// Canto esquerdo da barra de menus do Mac: o logo abre o menu do sistema
// (sobre, ajustes, repouso, reiniciar, desligar) e o nome do app em uso, em
// negrito, abre o menu da janela (minimizar, tela cheia, mudar de mesa,
// fechar, encerrar). Sem janela em foco, mostra a mesa atual.
//
// Com o Pomarchy desligado (outro tema) ou a barra de menus desligada nos
// ajustes, vira o logo de sempre do Omarchy e abre o menu do Omarchy: a barra
// nunca fica sem menu.
BarWidget {
  id: root

  PomarSettings { id: settings }
  PomarEvents { id: events }

  readonly property bool shown: true
  readonly property bool macMode: settings.active && settings.get("menubar.enabled", true)
  readonly property string lang: I18n.resolve(settings.get("language", "auto"), Quickshell.env("LANG"))
  readonly property bool dark: Tokens.isDark(Color.background)
  readonly property var active: ToplevelManager.activeToplevel
  readonly property string appId: active ? String(active.appId || "") : ""
  readonly property var webIndex: Apps.webappIndex(DesktopEntries.applications.values)
  readonly property var entry: appId ? Apps.entryFor(DesktopEntries, appId, webIndex) : null
  readonly property int workspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
  readonly property string appName: appId ? Apps.displayName(entry, appId) : tr("desktopName", workspaceId)

  visible: shown
  implicitWidth: row.implicitWidth + 6
  implicitHeight: barSize

  function tr(key) {
    var args = [Strings.TABLE, key, root.lang]
    for (var i = 1; i < arguments.length; i++) args.push(arguments[i])
    return I18n.tr.apply(null, args)
  }

  function run(command) {
    Quickshell.execDetached(command)
  }

  function activeAddress() {
    var hyprActive = Hyprland.activeToplevel
    return hyprActive ? String(hyprActive.address || "").replace(/[^0-9a-fx]/gi, "") : ""
  }

  function workspaceItems() {
    var items = []
    var list = Hyprland.workspaces.values || []
    var ids = []
    for (var i = 0; i < list.length; i++) if (list[i].id > 0) ids.push(list[i].id)
    ids.sort(function(a, b) { return a - b })
    var next = 1
    while (ids.indexOf(next) !== -1) next++
    ids.forEach(function(id) {
      items.push({ label: tr("desktop", id), checked: id === root.workspaceId,
                   action: function() { events.dispatch('hl.dsp.window.move({ workspace = "' + id + '", follow = true })') } })
    })
    items.push({ separator: true })
    items.push({ label: tr("newDesktop"), action: function() {
      events.dispatch('hl.dsp.window.move({ workspace = "' + next + '", follow = true })')
    } })
    return items
  }

  readonly property var systemItems: [
    { label: tr("about"), action: function() { root.run(["omarchy-launch-about"]) } },
    { separator: true },
    { label: tr("pomarSettings"), action: function() { root.run(["omarchy-shell", "shell", "summon", "pomar.settings", '{"page":"geral"}']) } },
    { label: tr("welcome"), action: function() { root.run(["omarchy-shell", "shell", "summon", "pomar.settings", '{"page":"welcome"}']) } },
    { label: tr("omarchySettings"), action: function() { root.run(["omarchy", "menu", "summon", "setup"]) } },
    { separator: true },
    // O melhor do Omarchy à mão, com os atalhos de sempre.
    { label: tr("omarchyMenu"), shortcut: "⌘" + tr("space"), action: function() { root.run(["omarchy-menu", "toggle"]) } },
    { label: tr("keybindings"), shortcut: "⌘K", action: function() { root.run(["omarchy-menu-keybindings"]) } },
    { label: tr("capture"), shortcut: "⌘⌃C", action: function() { root.run(["omarchy-menu", "toggle", "capture"]) } },
    { separator: true },
    { label: "Launchpad", shortcut: "⌘⌥" + tr("space"), action: function() { events.send("launchpad", "toggle") } },
    { label: "Mission Control", shortcut: "⌘⌃↑", action: function() { events.send("mission", "toggle") } },
    { separator: true },
    { label: tr("sleep"), action: function() { root.run(["systemctl", "suspend"]) } },
    { label: tr("restart"), confirm: { title: tr("restartAsk"), button: tr("restartButton"), cancel: tr("cancel") },
      action: function() { root.run(["omarchy", "system", "reboot"]) } },
    { label: tr("shutdown"), confirm: { title: tr("shutdownAsk"), button: tr("shutdownButton"), cancel: tr("cancel") },
      action: function() { root.run(["omarchy", "system", "shutdown"]) } },
    { separator: true },
    { label: tr("lock"), shortcut: "⌘⌃L", action: function() { root.run(["omarchy", "system", "lock"]) } },
    { label: tr("logout"), confirm: { title: tr("logoutAsk"), button: tr("logoutButton"), cancel: tr("cancel") },
      action: function() { root.run(["omarchy", "system", "logout"]) } }
  ]

  function appItems() {
    var hasWindow = root.appId !== ""
    var address = root.activeAddress()
    var target = address ? '"address:' + address + '"' : "nil"
    var key = root.entry ? root.entry.id : root.appId
    return [
      { label: tr("newWindow"), enabled: !!root.entry, action: function() { Apps.launchGuarded(Quickshell, root.entry.id) } },
      { separator: true },
      { label: tr("minimize"), shortcut: "⌘M", enabled: hasWindow,
        // O Dock faz o "gênio" e tira a janela de cena.
        action: function() { events.send("dock", "minimize", address) } },
      { label: tr("fullscreen"), shortcut: "⌘F", enabled: hasWindow,
        action: function() { events.dispatch('hl.dsp.window.fullscreen({ window = ' + target + ' })') } },
      { label: tr("float"), shortcut: "⌘T", enabled: hasWindow,
        action: function() { events.dispatch('hl.dsp.window.float({ window = ' + target + ' })') } },
      { label: tr("moveTo"), enabled: hasWindow, submenu: root.workspaceItems() },
      { label: tr("allWindows"), shortcut: "⌘⌃↓", enabled: hasWindow, action: function() { events.send("mission", "expose", key) } },
      { separator: true },
      { label: tr("closeWindow"), shortcut: "⌘W", enabled: hasWindow,
        action: function() { events.dispatch('hl.dsp.window.close({ window = ' + target + ' })') } },
      { label: tr("quitApp", root.appName), enabled: hasWindow, action: function() { root.quitApp() } }
    ]
  }

  // Encerrar = fechar com educação todas as janelas do app (cada app decide se
  // pergunta antes de fechar, como no Mac).
  function quitApp() {
    var list = Hyprland.toplevels.values || []
    for (var i = 0; i < list.length; i++) {
      var w = list[i].wayland
      if (!w || Apps.appKey(DesktopEntries, w.appId, root.webIndex) !== Apps.appKey(DesktopEntries, root.appId, root.webIndex)) continue
      events.dispatch('hl.dsp.window.close({ window = "address:' + String(list[i].address).replace(/[^0-9a-fx]/gi, "") + '" })')
    }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    x: 2
    spacing: 2

    Item {
      id: logoButton
      width: logo.implicitWidth + 20
      height: root.barSize - 6
      anchors.verticalCenter: parent.verticalCenter
      Rectangle {
        anchors.fill: parent
        radius: 6
        color: Tokens.hover(root.dark)
        visible: systemMenu.visible || logoArea.containsMouse
      }
      Text {
        id: logo
        anchors.centerIn: parent
        text: ""
        font.family: "omarchy"
        font.pixelSize: 15
        color: Color.bar.text
      }
      MouseArea {
        id: logoArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
          if (!root.macMode) { root.run(["omarchy-menu", "toggle"]); return }
          systemMenu.visible ? systemMenu.closeMenu() : (appMenu.closeMenu(), systemMenu.openMenu())
        }
      }
    }

    Item {
      id: appButton
      visible: root.macMode
      width: appLabel.implicitWidth + 20
      height: root.barSize - 6
      anchors.verticalCenter: parent.verticalCenter
      Rectangle {
        anchors.fill: parent
        radius: 6
        color: Tokens.hover(root.dark)
        visible: appMenu.visible || appArea.containsMouse
      }
      Text {
        id: appLabel
        anchors.centerIn: parent
        text: root.appName
        color: Color.bar.text
        font.pixelSize: 13
        font.weight: Font.Bold
        font.family: Style.fontFamily
      }
      MouseArea {
        id: appArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
          if (appMenu.visible) { appMenu.closeMenu(); return }
          systemMenu.closeMenu()
          appMenu.items = root.appItems()
          appMenu.openMenu()
        }
      }
    }
  }

  MacMenu {
    id: systemMenu
    anchorItem: logoButton
    dark: root.dark
    items: root.systemItems
  }

  MacMenu {
    id: appMenu
    anchorItem: appButton
    dark: root.dark
  }

  IpcHandler {
    target: "pomar-menubar-test"
    enabled: Quickshell.env("POMAR_TEST") === "1"
    function openSystem(): void { appMenu.closeMenu(); systemMenu.openMenu() }
    function openApp(): void { systemMenu.closeMenu(); appMenu.items = root.appItems(); appMenu.openMenu() }
    function closeAll(): void { systemMenu.closeMenu(); appMenu.closeMenu() }
    function state(): string { return JSON.stringify({ shown: root.shown, macMode: root.macMode, app: root.appName, appId: root.appId }) }
  }
}
