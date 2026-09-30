import QtQuick
import "../shared/Tokens.js" as Tokens

// Quadradinho colorido com glifo branco, como os ícones dos Ajustes do Mac:
// leve degradê de cima para baixo e um filete de luz na borda.
Item {
  id: root

  property color color: Theme.gray
  property string glyph: ""
  property real size: 22
  property real glyphScale: 0.66

  implicitWidth: size
  implicitHeight: size

  Rectangle {
    anchors.fill: parent
    radius: Math.round(root.size * 0.24)
    antialiasing: true
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.lighter(root.color, 1.16) }
      GradientStop { position: 1.0; color: Qt.darker(root.color, 1.06) }
    }

    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      color: "transparent"
      antialiasing: true
      border.width: 1
      border.color: Tokens.withAlpha(Theme.white, 0.16)
    }
  }

  Glyph {
    anchors.centerIn: parent
    size: Math.round(root.size * root.glyphScale)
    name: root.glyph
    color: Theme.white
    weight: 2.1
  }
}
