import QtQuick
import Quickshell
import Quickshell.Io
import "Defaults.js" as Defaults

// Ajustes do Pomarchy: um único JSON em ~/.config/pomar/settings.json, lido por
// todos os plugins e pelo hypr/pomar.lua. Quem muda um valor regrava o arquivo
// inteiro; os outros plugins recarregam pelo watchChanges.
//
// `active` diz se o Pomarchy deve aparecer: o tema atual do Omarchy começa com
// "pomar" ou o usuário pediu "manter ligado em qualquer tema".
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: Quickshell.env("POMAR_CONFIG_DIR") || (home + "/.config/pomar")
  readonly property string path: configDir + "/settings.json"
  readonly property string themeNamePath: home + "/.local/state/omarchy/current/theme.name"

  property var data: Defaults.merged(null)
  property string themeName: ""
  property bool loaded: false

  readonly property bool themeActive: themeName.indexOf("pomar") === 0
  readonly property bool active: themeActive || data.alwaysOn === true

  function get(keyPath, fallback) {
    return Defaults.lookup(root.data, keyPath, fallback)
  }

  function set(keyPath, value) {
    var next = Defaults.clone(root.data)
    Defaults.assign(next, keyPath, value)
    root.data = Defaults.merged(next)
    root.write()
  }

  function toggle(keyPath) {
    root.set(keyPath, !root.get(keyPath, false))
  }

  function write() {
    settingsFile.setText(JSON.stringify(root.data, null, 2) + "\n")
  }

  function parse(text) {
    root.data = Defaults.merged(Defaults.parse(text))
    root.loaded = true
  }

  FileView {
    id: settingsFile
    path: root.path
    watchChanges: true
    printErrors: false
    onLoaded: root.parse(text())
    onLoadFailed: {
      root.data = Defaults.merged(null)
      root.loaded = true
    }
    onFileChanged: reload()
  }

  FileView {
    id: themeFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: root.themeName = String(text() || "").trim()
    onLoadFailed: root.themeName = ""
    onFileChanged: reload()
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.configDir])
}
