import QtQuick
import QtQuick.Effects
import qs.Commons
import "shared"
import "shared/Tokens.js" as Tokens

// Um app na grade: ícone grande, nome embaixo numa linha só (com reticências)
// e, na busca, o anel de seleção. Escurece enquanto está pressionado, como no
// Mac. Clique direito (ou tocar e segurar) pede o menu do app.
Item {
  id: cell

  required property var modelData
  required property int index

  property int globalIndex: 0
  property real iconSize: 96
  property real labelGap: 10
  property real devicePixelRatio: 1
  property bool selected: false

  signal activated(int globalIndex)
  signal menuRequested(int globalIndex, real sceneX, real sceneY)

  // A grade troca de modelo a cada tecla na busca; um delegate prestes a sair
  // pode ver o modelData vazio por um instante.
  readonly property var app: modelData || ({})
  readonly property real blockHeight: iconSize + labelGap + label.height
  readonly property real blockTop: Math.round((height - blockHeight) / 2)
  // Largura fixa da "vaga" do app: o anel de seleção tem sempre o mesmo
  // tamanho e nomes longos ganham reticências dentro dela, como no Mac.
  readonly property real blockWidth: Math.min(width - 8, Math.max(Math.round(iconSize * 1.72), Math.round(width * 0.86)))

  Rectangle {
    id: ring
    x: Math.round((cell.width - width) / 2)
    y: cell.blockTop - 12
    width: cell.blockWidth
    height: cell.blockHeight + 22
    radius: Tokens.radius.card
    color: Tokens.pressed(true)
    border.width: 1
    border.color: Tokens.hairline(true)
    opacity: cell.selected ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.instant; easing.type: Easing.OutCubic } }
  }

  // Quadrado arredondado como os ícones do Mac (shared/AppIconTile.qml).
  AppIconTile {
    id: icon
    x: Math.round((cell.width - cell.iconSize) / 2)
    y: cell.blockTop
    width: cell.iconSize
    height: cell.iconSize
    source: cell.app.icon || ""
    textureSize: Math.round(cell.iconSize * cell.devicePixelRatio)
    // A grade fica sobre o papel de parede escurecido: placa clara nos dois temas
    // lê melhor, como no Launchpad do Mac.
    dark: false
    // Escurece só enquanto o dedo/botão está em cima: nenhum custo em repouso.
    pressed: hit.pressed && hit.containsMouse
  }

  // Sombra suave do nome, como no Mac: uma cópia escura e mais grossa do
  // texto, desfocada numa camada do tamanho do rótulo (calculada uma vez). O
  // nome branco fica fora da camada, nítido, sem franja colorida.
  Item {
    id: labelShadow

    readonly property int pad: 5

    x: label.x - pad
    y: label.y - pad + 1
    width: label.width + pad * 2
    height: label.height + pad * 2
    layer.enabled: true
    layer.effect: MultiEffect {
      autoPaddingEnabled: false
      blurEnabled: true
      blur: 1.0
      blurMax: 6
    }

    Text {
      x: labelShadow.pad
      y: labelShadow.pad
      width: label.width
      text: label.text
      textFormat: Text.PlainText
      color: Tokens.shadow(true)
      style: Text.Outline
      styleColor: Tokens.shadow(true)
      font: label.font
      elide: Text.ElideRight
      maximumLineCount: 1
      wrapMode: Text.NoWrap
      horizontalAlignment: Text.AlignHCenter
    }
  }

  Text {
    id: label
    x: Math.round((cell.width - width) / 2)
    y: icon.y + cell.iconSize + cell.labelGap
    width: cell.blockWidth - 12
    text: cell.app.name || ""
    textFormat: Text.PlainText
    color: Tokens.label(true)
    font.family: Style.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    maximumLineCount: 1
    wrapMode: Text.NoWrap
    horizontalAlignment: Text.AlignHCenter
  }

  MouseArea {
    id: hit
    x: Math.round((cell.width - cell.blockWidth) / 2)
    y: cell.blockTop - 8
    width: cell.blockWidth
    height: cell.blockHeight + 14
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    Accessible.role: Accessible.Button
    Accessible.name: label.text
    onPressed: function(mouse) {
      if (mouse.button !== Qt.RightButton) return
      var point = hit.mapToItem(null, mouse.x, mouse.y)
      cell.menuRequested(cell.globalIndex, point.x, point.y)
    }
    onClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton) cell.activated(cell.globalIndex)
    }
    onPressAndHold: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      var point = hit.mapToItem(null, mouse.x, mouse.y)
      cell.menuRequested(cell.globalIndex, point.x, point.y)
    }
  }
}
