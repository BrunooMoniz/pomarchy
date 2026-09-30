import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Janelinha das ilustrações: barra de título com os três pontinhos, uma
// coluna na cor do "app" e linhas de conteúdo. `u` é a unidade da cena.
Item {
  id: win

  property real u: 1
  property color tint: Theme.blue
  property bool lifted: false

  RectangularShadow {
    anchors.fill: body
    radius: body.radius
    blur: (win.lifted ? 10 : 6) * win.u
    offset.y: (win.lifted ? 3 : 2) * win.u
    color: Tokens.withAlpha(Theme.shadow, Theme.dark ? 0.55 : 0.28)
  }

  Rectangle {
    id: body
    anchors.fill: parent
    radius: 3.4 * win.u
    antialiasing: true
    color: Theme.card
    border.width: 1
    border.color: Theme.outline

    Row {
      x: 3.2 * win.u
      y: 2.4 * win.u
      spacing: 1.4 * win.u
      Repeater {
        model: [Theme.red, Theme.orange, Theme.green]
        Rectangle {
          required property color modelData
          width: 2.4 * win.u
          height: width
          radius: width / 2
          color: modelData
        }
      }
    }

    Rectangle {
      x: 3.2 * win.u
      y: 7.4 * win.u
      width: Math.max(2, parent.width * 0.26)
      height: Math.max(2, parent.height - 10.6 * win.u)
      radius: 1.6 * win.u
      color: Tokens.withAlpha(win.tint, Theme.dark ? 0.55 : 0.30)
    }

    Column {
      x: parent.width * 0.26 + 6.4 * win.u
      y: 8.2 * win.u
      spacing: 2.6 * win.u
      Repeater {
        model: [0.62, 0.48, 0.56, 0.34]
        Rectangle {
          required property real modelData
          width: Math.max(2, (body.width - body.width * 0.26 - 10 * win.u) * modelData)
          height: 1.6 * win.u
          radius: height / 2
          color: Theme.separator
          visible: y + height < body.height - 9 * win.u
        }
      }
    }
  }
}
