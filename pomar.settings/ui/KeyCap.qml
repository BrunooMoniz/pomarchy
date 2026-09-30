import QtQuick
import "../shared/Tokens.js" as Tokens

// Tecla desenhada: tampo claro, borda de baixo mais funda (dá volume) e o
// símbolo do Mac no meio. `down` afunda a tecla (usado nas animações).
Item {
  id: root

  property string text: ""
  property real size: 26
  property bool down: false

  readonly property bool symbol: text.length === 1
  readonly property real depth: Math.max(2, Math.round(size * 0.09))

  implicitHeight: size
  implicitWidth: Math.max(size, caption.implicitWidth + size * 0.62)

  // Base (a "parede" da tecla).
  Rectangle {
    anchors.fill: parent
    radius: Math.round(root.size * 0.22)
    antialiasing: true
    color: Theme.dark ? Tokens.mix(Theme.card, Theme.white, 0.04) : Tokens.mix(Theme.card, Theme.label, 0.13)
  }

  // Tampo.
  Rectangle {
    id: face
    x: 0
    width: parent.width
    y: root.down ? root.depth - 1 : 0
    height: parent.height - root.depth
    radius: Math.round(root.size * 0.2)
    antialiasing: true
    color: Theme.dark ? Tokens.mix(Theme.card, Theme.white, 0.13) : Theme.card
    border.width: 1
    border.color: Theme.dark ? Tokens.withAlpha(Theme.white, 0.08) : Tokens.withAlpha(Theme.label, 0.10)
    Behavior on y { NumberAnimation { duration: Tokens.motion.instant; easing.type: Easing.OutCubic } }

    Label {
      id: caption
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.symbol ? -0.5 : 0
      text: root.text
      font.pixelSize: Math.round(root.symbol ? root.size * 0.5 : root.size * 0.42)
      font.weight: Font.Medium
      color: Theme.label
    }
  }
}
