import QtQuick
import Quickshell
import Quickshell.Io
import "shared/Apps.js" as Apps
import "Library.js" as Library

// Lista de apps do Launchpad: as entradas .desktop visíveis, sem o que o
// lançador do Omarchy esconde (launcher.hides e o hidden-entries.sh, como o
// AppLibrary do shell) e sem o que a pessoa ocultou no Launchpad. Montada uma
// vez na subida do shell e refeita só quando algo muda de verdade.
Item {
  id: catalog

  property string omarchyPath: "/usr/share/omarchy"
  // Ids ocultados pela pessoa (launchpad.hidden nos ajustes).
  property var hiddenIds: []

  property var items: []
  property string signature: ""
  property var configuredHides: ({})
  property var desktopHides: ({})
  property int builds: 0

  function schedule() {
    rebuildDelay.restart()
  }

  function rebuild() {
    var values = DesktopEntries.applications.values || []
    var hidden = Library.idSet(catalog.hiddenIds)
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay) continue
      var id = String(entry.id || "")
      if (!id || catalog.configuredHides[id] === true || catalog.desktopHides[id] === true || hidden[id] === true) continue
      if (!String(entry.name || "").trim()) continue
      out.push(Library.makeItem(entry, Apps.iconSource(Quickshell, entry, id)))
    }
    out = Library.sortItems(out)
    var next = Library.signature(out)
    if (next === catalog.signature) return
    catalog.signature = next
    catalog.items = out
    catalog.builds++
  }

  function scanHidden() {
    if (hiddenScan.running) hiddenScan.pending = true
    else hiddenScan.running = true
  }

  onHiddenIdsChanged: catalog.schedule()

  Timer {
    id: rebuildDelay
    interval: 150
    onTriggered: catalog.rebuild()
  }

  FileView {
    path: catalog.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: {
      catalog.configuredHides = Library.linesToSet(text())
      catalog.schedule()
    }
    onLoadFailed: {
      catalog.configuredHides = ({})
      catalog.schedule()
    }
    onFileChanged: reload()
  }

  // Shell sem login de propósito (bash, não bash -l): um shell de login mexe
  // em ~/.local/share e redispara o vigia das entradas .desktop em laço. O
  // mesmo cuidado do AppLibrary do Omarchy.
  Process {
    id: hiddenScan

    property bool pending: false

    command: ["bash", catalog.omarchyPath + "/shell/services/hidden-entries.sh",
      [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")]
        .filter(function(value) { return String(value || "").length > 0 }).join(":")]
    stdout: StdioCollector {
      onStreamFinished: {
        catalog.desktopHides = Library.linesToSet(text)
        catalog.schedule()
      }
    }
    onExited: {
      if (!hiddenScan.pending) return
      hiddenScan.pending = false
      hiddenScan.running = true
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      catalog.scanHidden()
      catalog.schedule()
    }
  }

  Component.onCompleted: {
    catalog.scanHidden()
    catalog.schedule()
  }
}
