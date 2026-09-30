import QtQuick
import "../shared/Tokens.js" as Tokens

// Página dos Ajustes: rola sozinha, começa com o cartão de título (ícone
// grande, nome e uma frase simples explicando para que serve) e empilha os
// grupos abaixo com respiro constante.
Flickable {
  id: page

  property var app
  property string title: ""
  property string intro: ""
  property string glyph: ""
  property color tint: Theme.gray
  property bool showHeader: true
  default property alias body: column.data

  contentWidth: width
  contentHeight: column.implicitHeight + 36
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickDeceleration: 4000
  maximumFlickVelocity: 5000

  function scrollTo(y) {
    page.contentY = Tokens.clamp(y, 0, Math.max(0, page.contentHeight - page.height))
  }

  Column {
    id: column
    x: Theme.pagePadX
    width: page.width - Theme.pagePadX * 2
    topPadding: 4
    spacing: 22

    Rectangle {
      visible: page.showHeader
      width: parent.width
      height: header.implicitHeight + 36
      radius: Theme.groupRadius
      color: Theme.card
      border.width: 1
      border.color: Theme.cardStroke
      antialiasing: true

      Row {
        id: header
        x: 18
        width: parent.width - 36
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        IconTile {
          id: bigTile
          anchors.verticalCenter: parent.verticalCenter
          size: 58
          color: page.tint
          glyph: page.glyph
        }

        Column {
          width: parent.width - bigTile.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4

          Label {
            width: parent.width
            text: page.title
            font.pixelSize: Theme.display
            font.weight: Font.Bold
            elide: Text.ElideRight
          }

          Label {
            width: parent.width
            visible: page.intro !== ""
            text: page.intro
            color: Theme.secondary
            wrapMode: Text.WordWrap
            lineHeight: 1.12
          }
        }
      }
    }
  }

  // Indicador de rolagem fino, só enquanto rola (como no Mac).
  Rectangle {
    readonly property real ratio: page.height / Math.max(page.height, page.contentHeight)
    visible: ratio < 1
    parent: page
    x: page.width - 7
    width: 4
    radius: 2
    height: Math.max(28, page.height * ratio - 8)
    y: 4 + (page.height - 8 - height) * (page.contentY / Math.max(1, page.contentHeight - page.height))
    color: Theme.secondary
    opacity: page.moving || scrollHold.running ? 0.55 : 0
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.slow } }
  }

  Timer {
    id: scrollHold
    interval: 700
  }

  onContentYChanged: scrollHold.restart()
}
