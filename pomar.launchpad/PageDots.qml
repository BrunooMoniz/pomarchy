pragma ComponentBehavior: Bound

import QtQuick
import "shared/Tokens.js" as Tokens
import "shared/I18n.js" as I18n
import "Strings.js" as Strings

// Pontinhos de página embaixo da grade. O atual fica aceso; clicar num ponto
// vai direto para aquela página. Com uma página só, não aparecem.
Row {
  id: dots

  property int count: 1
  property int current: 0
  property real dotSize: 8
  property string lang: "en"

  signal picked(int index)

  visible: count > 1

  Repeater {
    model: dots.count

    delegate: Item {
      id: slot

      required property int index

      // Alvo de clique bem maior que o ponto.
      width: Math.round(dots.dotSize * 2.75)
      height: Math.round(dots.dotSize * 3.5)
      Accessible.role: Accessible.Button
      Accessible.name: I18n.tr(Strings.TABLE, "page", dots.lang, slot.index + 1, dots.count)

      Rectangle {
        anchors.centerIn: parent
        width: dots.dotSize
        height: dots.dotSize
        radius: dots.dotSize / 2
        color: Tokens.label(true)
        opacity: slot.index === dots.current ? 1 : 0.34
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic } }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: dots.picked(slot.index)
      }
    }
  }
}
