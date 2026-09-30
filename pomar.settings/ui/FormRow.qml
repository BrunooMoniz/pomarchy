import QtQuick
import "../shared/Tokens.js" as Tokens

// Linha de um grupo: ícone opcional, rótulo e explicação à esquerda, controle
// à direita (filhos vão para o espaço do controle). O filete de cima só
// aparece a partir da segunda linha visível: na Column do grupo, a primeira
// fica em y = 0.
Item {
  id: row

  property string label: ""
  property string description: ""
  property string glyph: ""
  property color glyphColor: Theme.gray
  property bool clickable: false
  property real minHeight: Theme.rowHeight
  property alias trailing: trailingSlot
  property alias labelItem: labelText
  default property alias controls: trailingSlot.data

  signal clicked()

  width: parent ? parent.width : 0
  implicitHeight: Math.max(minHeight, texts.implicitHeight + 22)
  opacity: enabled ? 1 : 0.5

  Rectangle {
    visible: row.y > 0
    x: Theme.rowPadX
    width: row.width - Theme.rowPadX * 2
    height: 1
    color: Theme.separator
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: 4
    radius: Theme.itemRadius
    visible: row.clickable
    color: tap.pressed ? Theme.pressed : (tap.containsMouse ? Tokens.withAlpha(Theme.hover, Theme.hover.a * 0.6) : "transparent")
    Behavior on color { ColorAnimation { duration: Tokens.motion.instant } }
  }

  IconTile {
    id: tile
    visible: row.glyph !== ""
    x: Theme.rowPadX
    anchors.verticalCenter: parent.verticalCenter
    size: 26
    color: row.glyphColor
    glyph: row.glyph
  }

  Column {
    id: texts
    x: tile.visible ? tile.x + tile.width + 12 : Theme.rowPadX
    width: Math.max(40, row.width - x - Theme.rowPadX - (trailingSlot.width > 0 ? trailingSlot.width + 16 : 0))
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Label {
      id: labelText
      width: parent.width
      text: row.label
      wrapMode: Text.WordWrap
    }

    Label {
      visible: row.description !== ""
      width: parent.width
      text: row.description
      color: Theme.secondary
      font.pixelSize: Theme.small
      wrapMode: Text.WordWrap
      lineHeight: 1.1
    }
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    enabled: row.clickable
    hoverEnabled: row.clickable
    cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: row.clicked()
  }

  Row {
    id: trailingSlot
    anchors.right: parent.right
    anchors.rightMargin: Theme.rowPadX
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8
  }
}
