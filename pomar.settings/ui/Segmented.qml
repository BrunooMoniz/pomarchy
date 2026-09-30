import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Controle segmentado do Mac ("3 dedos | 4 dedos"): trilho discreto e uma
// peça clara que desliza até a opção escolhida.
// `options` = [{ value, label }]; emite chosen(value).
Item {
  id: root

  property var options: []
  property var value
  property real segmentWidth: 0

  signal chosen(var value)

  readonly property int count: options.length
  readonly property int currentIndex: {
    for (var i = 0; i < options.length; i++)
      if (options[i].value === value) return i
    return -1
  }
  // Largura natural: a do maior rótulo (medido numa fileira escondida).
  readonly property real naturalSegment: {
    var widest = 0
    var list = measures.children
    for (var i = 0; i < list.length; i++)
      if (list[i].text !== undefined) widest = Math.max(widest, list[i].implicitWidth)
    return widest + 28
  }
  readonly property real cell: segmentWidth > 0 ? segmentWidth : naturalSegment

  implicitWidth: cell * count + 4
  implicitHeight: 28
  opacity: enabled ? 1 : 0.45

  // Mede os rótulos para todos os segmentos terem a largura do maior.
  Row {
    id: measures
    visible: false
    Repeater {
      model: root.options
      Label {
        required property var modelData
        text: modelData.label
        font.pixelSize: Theme.body
        font.weight: Font.DemiBold
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: 8
    color: Theme.track
  }

  RectangularShadow {
    anchors.fill: thumb
    visible: root.currentIndex >= 0
    radius: thumb.radius
    blur: 4
    offset.y: 1
    color: Tokens.withAlpha(Theme.shadow, Theme.dark ? 0.5 : 0.22)
  }

  Rectangle {
    id: thumb
    visible: root.currentIndex >= 0
    x: 2 + Math.max(0, root.currentIndex) * root.cell
    y: 2
    width: root.cell
    height: root.height - 4
    radius: 6
    antialiasing: true
    color: Theme.dark ? Tokens.withAlpha(Theme.white, 0.26) : Theme.card
    Behavior on x { NumberAnimation { duration: Tokens.motion.base; easing.type: Easing.OutCubic } }
  }

  Repeater {
    model: root.options
    delegate: Item {
      id: segment
      required property var modelData
      required property int index
      readonly property bool selected: index === root.currentIndex
      x: 2 + index * root.cell
      y: 2
      width: root.cell
      height: root.height - 4

      // Divisória fina entre opções que não estão escolhidas.
      Rectangle {
        visible: segment.index > 0 && !segment.selected && segment.index - 1 !== root.currentIndex
        width: 1
        height: parent.height - 12
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.separator
      }

      Label {
        anchors.centerIn: parent
        text: segment.modelData.label
        font.pixelSize: Theme.body
        font.weight: segment.selected ? Font.DemiBold : Font.Normal
        color: segment.selected ? Theme.label : Theme.secondary
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (!segment.selected) root.chosen(segment.modelData.value)
      }
    }
  }
}
