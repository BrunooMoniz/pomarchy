import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "shared"
import "shared/Tokens.js" as Tokens

// Um item do Dock: app, Launchpad, janela minimizada, Lixeira ou separador.
// Só desenha. Posição e tamanho vêm do layout calculado no Dock, e o mouse é
// tratado numa área única lá, que sabe qual item está sob o cursor. Os filhos
// ficam em coordenadas da janela do Dock.
Item {
  id: cell

  required property var dock
  required property var modelData

  readonly property string key: modelData ? String(modelData.key || "") : ""
  readonly property var info: dock.itemData[key] || ({})
  readonly property var slot: dock.layout.items[key] || null
  readonly property string kind: info.kind || ""
  readonly property real presence: slot ? slot.presence : 0
  // Entra e sai crescendo a partir do centro do próprio lugar.
  readonly property real size: slot ? slot.size * presence : 0
  readonly property real center: slot ? slot.center : 0
  readonly property bool concealed: dock.dragKey === key || dock.settlingKey === key || dock.genieKey === key
  readonly property bool pressed: dock.pressedKey === key && !dock.dragActive
  readonly property bool bouncing: dock.launching[key] !== undefined
  readonly property string iconSource: kind === "trash" ? dock.trashIcon : String(info.icon || "")

  // Altura do pulo ao abrir um app (quicar do Mac).
  property real lift: 0

  visible: slot !== null && presence > 0.002

  onBouncingChanged: if (bouncing && !bounce.running) bounce.start()

  SequentialAnimation {
    id: bounce
    NumberAnimation {
      target: cell; property: "lift"; from: 0; to: cell.dock.bounceHeight
      duration: Tokens.motion.bounce / 2; easing.type: Easing.OutQuad
    }
    NumberAnimation {
      target: cell; property: "lift"; to: 0
      duration: Tokens.motion.bounce / 2; easing.type: Easing.InQuad
    }
    // Sempre termina o pulo no chão; só recomeça se o app ainda não abriu.
    onFinished: if (cell.bouncing) Qt.callLater(function() { if (cell.bouncing && !bounce.running) bounce.start() })
  }

  // Ícone de app, Launchpad e Lixeira. Apps em quadrado arredondado (como no
  // Mac); a Lixeira é um desenho e fica como está.
  AppIconTile {
    id: image
    visible: cell.kind !== "separator" && cell.kind !== "minimized"
    x: cell.center - cell.size / 2
    y: cell.dock.baselineY - cell.size - cell.lift
    width: cell.size
    height: cell.size
    source: cell.iconSource
    textureSize: cell.dock.textureSize
    dark: cell.dock.dark
    normalize: cell.kind !== "trash"
    opacity: cell.concealed ? 0 : Math.min(1, cell.presence * 1.4)
    // Escurece enquanto o botão está apertado, como no Mac.
    pressed: cell.pressed
  }

  // Separador fino antes das minimizadas e da Lixeira.
  Rectangle {
    visible: cell.kind === "separator"
    width: 1
    height: Math.round(cell.dock.bodyHeight * 0.62)
    x: Math.round(cell.center)
    y: Math.round(cell.dock.bodyY + (cell.dock.bodyHeight - height) / 2)
    color: Tokens.separator(cell.dock.dark)
    opacity: cell.presence
  }

  // Ponto de app aberto.
  Rectangle {
    visible: cell.kind === "app" && cell.info.running === true && !cell.concealed
    width: cell.dock.dotSize
    height: width
    radius: width / 2
    x: cell.center - width / 2
    y: cell.dock.bodyY + cell.dock.bodyHeight - cell.dock.dotInset - height
    color: Tokens.label(cell.dock.dark)
    opacity: 0.72 * cell.presence
  }

  // Janela minimizada: miniatura com o selo do app.
  Loader {
    active: cell.kind === "minimized"
    // Durante o "gênio", quem aparece no lugar é a própria janela escorrendo.
    visible: !cell.concealed
    sourceComponent: thumbnail
  }

  Component {
    id: thumbnail

    Item {
      id: box
      readonly property real side: cell.size
      x: cell.center - side / 2
      y: cell.dock.baselineY - side
      width: side
      height: side
      opacity: cell.concealed ? 0 : Math.min(1, cell.presence * 1.4)

      // Entrada: a janela "cai" no Dock, de cima e maior, e assenta.
      property real entry: 1
      transform: [
        Scale { origin.x: box.width / 2; origin.y: box.height; xScale: 1 + 0.9 * (1 - box.entry); yScale: 1 + 0.9 * (1 - box.entry) },
        Translate { y: -70 * (1 - box.entry) }
      ]
      NumberAnimation on entry { id: entryAnim; running: false; from: 0; to: 1; duration: Tokens.motion.slow; easing.type: Easing.OutCubic }
      Component.onCompleted: if (cell.dock.settled) entryAnim.start()

      readonly property var source: cell.dock.toplevelFor(cell.info.address, cell.dock.clientSerial)
      readonly property real ratio: view.hasContent && view.sourceSize.height > 0 ? view.sourceSize.width / view.sourceSize.height : 1.5
      readonly property real viewWidth: ratio >= 1 ? side * 0.94 : side * 0.94 * ratio
      readonly property real viewHeight: ratio >= 1 ? side * 0.94 / ratio : side * 0.94

      RectangularShadow {
        visible: view.hasContent
        anchors.fill: view
        radius: 4
        blur: 10
        offset.y: 2
        color: Tokens.shadow(cell.dock.dark)
      }

      ScreencopyView {
        id: view
        width: box.viewWidth
        height: box.viewHeight
        anchors.centerIn: parent
        captureSource: box.source
        live: false
        paintCursor: false
        visible: hasContent
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: roundMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
        }
      }

      Item {
        id: roundMask
        width: view.width
        height: view.height
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: Math.max(3, parent.width * 0.06) }
      }

      // Sem imagem da janela, o próprio ícone do app ocupa o lugar.
      AppIconTile {
        readonly property real badge: view.hasContent ? box.side * 0.46 : box.side
        width: badge
        height: badge
        x: view.hasContent ? box.side - badge * 0.92 : 0
        y: view.hasContent ? box.side - badge * 0.92 : 0
        source: String(cell.info.icon || "")
        textureSize: cell.dock.textureSize
        dark: cell.dock.dark
      }

      // Miniatura parada (live: false); o Dock pede um quadro novo ao passar o
      // mouse e quando a janela acaba de ser minimizada.
      Connections {
        target: cell.dock
        function onThumbRequestChanged() {
          if (box.source) view.captureFrame()
        }
      }
    }
  }
}
