import QtQuick
import Quickshell
import qs.Commons
import "shared"
import "shared/Tokens.js" as Tokens

// Base do Pomarchy. Enquanto um tema Pomarchy está ativo:
// - a tipografia do shell inteiro (barra, menus, avisos) vira a fonte de
//   interface mais próxima da do Mac que a máquina tiver;
// - na primeira vez, abre a tela de boas-vindas.
Item {
  id: root

  PomarSettings { id: settings }

  readonly property string family: Tokens.uiFont(Qt.fontFamilies())

  Binding {
    target: Style
    property: "fontFamily"
    value: root.family
    when: settings.active
    restoreMode: Binding.RestoreBindingOrValue
  }

  function maybeWelcome() {
    if (settings.loaded && settings.active && !settings.get("welcome.seen", false)) welcomeDelay.restart()
  }

  Timer {
    id: welcomeDelay
    interval: 2500
    onTriggered: {
      if (!settings.active || settings.get("welcome.seen", false)) return
      Quickshell.execDetached(["omarchy-shell", "shell", "summon", "pomar.settings", JSON.stringify({ page: "welcome" })])
    }
  }

  Connections {
    target: settings
    function onActiveChanged() { root.maybeWelcome() }
    function onLoadedChanged() { root.maybeWelcome() }
  }
}
