import QtQuick
import "../shared/Tokens.js" as Tokens

// Os três botões do canto da janela. Só o vermelho faz algo (fecha); os
// outros dois aparecem apagados, como botões indisponíveis no Mac.
Row {
  id: root

  signal closeClicked()

  spacing: 8

  Rectangle {
    width: 12
    height: 12
    radius: 6
    antialiasing: true
    color: Theme.red
    border.width: 1
    border.color: Tokens.withAlpha(Qt.darker(Theme.red, 1.4), 0.55)

    Glyph {
      anchors.centerIn: parent
      visible: closeArea.containsMouse
      size: 9
      name: "close"
      weight: 3.2
      color: Tokens.withAlpha(Qt.darker(Theme.red, 2.6), 0.9)
    }

    MouseArea {
      id: closeArea
      anchors.fill: parent
      anchors.margins: -7
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeClicked()
    }
  }

  Repeater {
    model: 2
    Rectangle {
      width: 12
      height: 12
      radius: 6
      antialiasing: true
      color: Theme.dark ? Tokens.withAlpha(Theme.white, 0.13) : Tokens.withAlpha(Theme.label, 0.10)
      border.width: 1
      border.color: Theme.dark ? Tokens.withAlpha(Theme.white, 0.08) : Tokens.withAlpha(Theme.label, 0.08)
    }
  }
}
