import QtQuick
import QtQuick.Effects
import "Tokens.js" as Tokens

// Material "vidro" do Pomarchy: preenchimento translúcido, filete claro por
// dentro e contorno fino por fora, com sombra macia. O desfoque do que está
// atrás vem do Hyprland (hl.layer_rule com blur nas camadas pomar-*), por isso
// o preenchimento nunca é opaco.
Item {
  id: root

  property bool dark: true
  property real radius: Tokens.radius.card
  property color fill: Tokens.glass(dark)
  property color stroke: Tokens.outline(dark)
  property color highlight: Tokens.hairline(dark)
  property bool shadow: true
  property real shadowBlur: 32
  property real shadowOffsetY: 10
  property color shadowColor: Tokens.shadow(dark)

  RectangularShadow {
    anchors.fill: body
    visible: root.shadow
    radius: root.radius
    blur: root.shadowBlur
    spread: -Math.min(8, root.radius / 3)
    offset.y: root.shadowOffsetY
    color: root.shadowColor
  }

  Rectangle {
    id: body
    anchors.fill: parent
    radius: root.radius
    color: root.fill
    border.width: 1
    border.color: root.stroke
    antialiasing: true
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: Math.max(0, root.radius - 1)
    color: "transparent"
    border.width: 1
    border.color: root.highlight
    antialiasing: true
  }
}
