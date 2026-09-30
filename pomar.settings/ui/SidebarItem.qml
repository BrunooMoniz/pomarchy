import QtQuick
import "../shared/Tokens.js" as Tokens

// Item da barra lateral: quadradinho colorido + nome. O escolhido ganha o
// fundo no destaque do tema, como nos Ajustes do Sistema.
Item {
  id: item

  property string label: ""
  property string glyph: ""
  property color tint: Theme.gray
  property bool selected: false

  signal clicked()

  width: parent ? parent.width : 0
  height: 32

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: 10
    radius: Theme.itemRadius + 1
    antialiasing: true
    color: item.selected ? Theme.accent : (mouse.pressed ? Theme.pressed : (mouse.containsMouse ? Theme.hover : "transparent"))
    Behavior on color { ColorAnimation { duration: Tokens.motion.instant } }
  }

  IconTile {
    id: tile
    x: 18
    anchors.verticalCenter: parent.verticalCenter
    size: 22
    color: item.tint
    glyph: item.glyph
  }

  Label {
    anchors.left: tile.right
    anchors.leftMargin: 9
    anchors.right: parent.right
    anchors.rightMargin: 18
    anchors.verticalCenter: parent.verticalCenter
    text: item.label
    elide: Text.ElideRight
    color: item.selected ? Theme.accentText : Theme.label
    font.weight: item.selected ? Font.Medium : Font.Normal
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: item.clicked()
  }
}
