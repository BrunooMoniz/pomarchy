import QtQuick

// Grupo "inset grouped" dos Ajustes do Mac: título pequeno acima, cartão
// arredondado com as linhas (filete entre elas, desenhado por FormRow) e uma
// nota explicativa abaixo.
Column {
  id: root

  property string title: ""
  property string footer: ""
  property alias card: card
  default property alias rows: body.data

  width: parent ? parent.width : 0
  spacing: 7

  Label {
    visible: root.title !== ""
    x: 4
    width: root.width - 8
    text: root.title
    font.weight: Font.DemiBold
    elide: Text.ElideRight
  }

  Rectangle {
    id: card
    width: root.width
    height: body.implicitHeight
    radius: Theme.groupRadius
    color: Theme.card
    border.width: 1
    border.color: Theme.cardStroke
    antialiasing: true

    Column {
      id: body
      width: parent.width
    }
  }

  Label {
    visible: root.footer !== ""
    x: 4
    width: root.width - 8
    text: root.footer
    color: Theme.secondary
    font.pixelSize: Theme.small
    wrapMode: Text.WordWrap
    lineHeight: 1.15
  }
}
