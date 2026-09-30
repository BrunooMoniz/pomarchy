import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Botão do Mac. kind: "normal" (claro com contorno), "primary" (destaque do
// tema) ou "plain" (só texto). large = botões das boas-vindas.
Item {
  id: root

  property string text: ""
  property string glyph: ""
  property string kind: "normal"
  property bool large: false
  property real minWidth: large ? 150 : 0

  signal clicked()

  readonly property bool primary: kind === "primary"
  readonly property bool plain: kind === "plain"
  readonly property color textColor: primary ? Theme.accentText : (plain ? Theme.accent : Theme.label)

  implicitHeight: large ? 44 : 28
  implicitWidth: Math.max(minWidth, content.implicitWidth + (large ? 44 : 24))
  opacity: enabled ? 1 : 0.45

  RectangularShadow {
    anchors.fill: face
    visible: !root.plain
    radius: face.radius
    blur: root.large ? 10 : 3
    offset.y: root.large ? 3 : 1
    color: Tokens.withAlpha(Theme.shadow, root.primary ? 0.30 : 0.18)
  }

  Rectangle {
    id: face
    anchors.fill: parent
    visible: !root.plain
    radius: root.large ? height / 2 : 7
    antialiasing: true
    color: root.primary ? Theme.accent : Theme.control
    border.width: root.primary ? 0 : 1
    border.color: Theme.controlStroke
  }

  // Realce de passagem e de clique por cima de qualquer tipo.
  Rectangle {
    anchors.fill: parent
    radius: face.radius
    color: mouse.pressed ? Theme.pressed : (mouse.containsMouse ? Theme.hover : "transparent")
    Behavior on color { ColorAnimation { duration: Tokens.motion.instant } }
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 6

    Glyph {
      visible: root.glyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      name: root.glyph
      size: root.large ? 18 : 14
      color: root.textColor
    }

    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.textColor
      font.pixelSize: root.large ? Theme.subtitle : Theme.body
      font.weight: root.primary || root.large ? Font.DemiBold : Font.Medium
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
