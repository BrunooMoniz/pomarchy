import QtQuick
import QtQuick.Effects
import "Tokens.js" as Tokens
import "IconShapes.js" as IconShapes

// Ícone de app normalizado em quadrado de cantos arredondados, como os do
// macOS, para Dock, Launchpad, alternador e Mission Control ficarem iguais.
// Ícone que já é um quadrado cheio só ganha os cantos (ampliado para cobrir a
// margem transparente que muitos trazem); ícone redondo ou de formato livre
// vai para dentro de uma placa arredondada, clara no tema claro e grafite no
// escuro. O formato é medido uma vez por ícone (IconShapes.js).
Item {
  id: root

  property url source
  property bool dark: false
  // false = ícone cru, sem placa nem recorte (ex.: a Lixeira, que é um desenho).
  property bool normalize: true
  // Escurece como o ícone apertado no Dock do Mac.
  property bool pressed: false
  property real textureSize: Math.max(64, Math.round(width * 2))
  property int measured: 0

  readonly property string sourceText: String(source || "")
  readonly property string shape: normalize ? IconShapes.lookup(sourceText, measured) : "raw"
  readonly property var crop: IconShapes.box(sourceText, measured)
  readonly property real cornerRadius: width * 0.2237

  implicitWidth: 64
  implicitHeight: 64

  layer.enabled: root.pressed
  layer.effect: MultiEffect { brightness: -0.28 }

  // Placa para os ícones de formato livre.
  Rectangle {
    anchors.fill: parent
    visible: root.shape === "free"
    radius: root.cornerRadius
    antialiasing: true
    gradient: Gradient {
      GradientStop { position: 0.0; color: root.dark ? "#4a4b51" : "#ffffff" }
      GradientStop { position: 1.0; color: root.dark ? "#2c2d32" : "#eceef2" }
    }
    border.width: 1
    border.color: root.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
  }

  // Ícone cru, ou dentro da placa (menor, com respiro). Enquanto o formato não
  // foi medido, aparece cru no tamanho cheio: nada pisca vazio.
  Image {
    anchors.centerIn: parent
    visible: root.shape !== "full"
    width: root.shape === "free" ? parent.width * 0.72 : parent.width
    height: width
    source: root.source
    sourceSize: Qt.size(root.textureSize, root.textureSize)
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    asynchronous: true
  }

  // Quadrado cheio: ampliado para a parte opaca ocupar a placa toda e recortado
  // nos cantos do Pomarchy.
  Item {
    id: fullBox
    anchors.fill: parent
    visible: root.shape === "full"
    layer.enabled: visible
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: cornerMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
    Image {
      readonly property real spanX: Math.max(0.5, root.crop.x1 - root.crop.x0)
      readonly property real spanY: Math.max(0.5, root.crop.y1 - root.crop.y0)
      width: fullBox.width / spanX
      height: fullBox.height / spanY
      x: -root.crop.x0 * width
      y: -root.crop.y0 * height
      source: root.source
      sourceSize: Qt.size(root.textureSize, root.textureSize)
      fillMode: Image.Stretch
      smooth: true
      mipmap: true
      asynchronous: true
    }
  }

  Item {
    id: cornerMask
    anchors.fill: parent
    layer.enabled: true
    visible: false
    Rectangle { anchors.fill: parent; radius: root.cornerRadius; color: "black"; antialiasing: true }
  }

  // Filete fino por cima, como a borda dos ícones do Mac.
  Rectangle {
    anchors.fill: parent
    visible: root.shape === "full"
    radius: root.cornerRadius
    color: "transparent"
    antialiasing: true
    border.width: 1
    border.color: root.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
  }

  // Medição do formato, uma vez por ícone. Canvas invisível também desenha.
  Canvas {
    id: probe
    width: 32
    height: 32
    visible: false
    readonly property string src: root.normalize ? root.sourceText : ""
    function measure() {
      if (!src || IconShapes.known(src)) return
      if (isImageLoaded(src)) requestPaint()
      else loadImage(src)
    }
    onSrcChanged: measure()
    Component.onCompleted: measure()
    onImageLoaded: requestPaint()
    onPaint: {
      if (!src || !isImageLoaded(src)) return
      if (!IconShapes.known(src)) {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, 32, 32)
        ctx.drawImage(src, 0, 0, 32, 32)
        IconShapes.remember(src, ctx.getImageData(0, 0, 32, 32).data, 32)
      }
      root.measured++
    }
  }
}
