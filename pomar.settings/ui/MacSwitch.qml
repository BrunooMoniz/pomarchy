import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Chave liga/desliga no estilo do Mac: trilho no destaque do tema quando
// ligada, bolinha clara com sombra. O chamador guarda o valor e responde a
// toggled(); a chave só desenha.
Item {
  id: root

  property bool checked: false
  // Falso quando a linha inteira já é clicável (SwitchRow).
  property bool interactive: true

  signal toggled()

  implicitWidth: 40
  implicitHeight: 24
  opacity: enabled ? 1 : 0.45

  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    antialiasing: true
    color: root.checked ? Theme.accent : Theme.track
    Behavior on color { ColorAnimation { duration: Tokens.motion.fast } }
  }

  RectangularShadow {
    anchors.fill: knob
    radius: knob.radius
    blur: 4
    offset.y: 1
    color: Tokens.withAlpha(Theme.shadow, 0.35)
  }

  Rectangle {
    id: knob
    width: root.height - 4
    height: width
    radius: width / 2
    y: 2
    x: root.checked ? root.width - width - 2 : 2
    antialiasing: true
    color: Theme.white
    Behavior on x { NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic } }
  }

  MouseArea {
    anchors.fill: parent
    anchors.margins: -8
    enabled: root.interactive
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }
}
