import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Telinha das ilustrações: papel de parede de verdade (o atual), barra de
// menus fina e um Dock pequeno, com cantos arredondados. As janelas entram
// como filhos. `pan` desliza o papel de parede para o lado (troca de mesa),
// `dim` escurece o fundo (Mission Control, Launchpad).
Item {
  id: desk

  property real u: 1
  property real pan: 0
  property real dim: 0
  property real menubarOpacity: 1
  property real dockOpacity: 1
  property bool showDock: true
  property alias overlay: overlayLayer
  default property alias content: contentLayer.data

  readonly property real radius: 7 * u

  Item {
    id: surface
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: roundMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }

    // Fundo de reserva quando não há imagem (vídeo ou tema sem papel de parede).
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0; color: Tokens.mix(Theme.blue, Theme.purple, 0.25) }
        GradientStop { position: 1; color: Tokens.mix(Theme.purple, Theme.orange, 0.35) }
      }
    }

    Image {
      id: paper
      x: -desk.pan * desk.width
      width: desk.width
      height: desk.height
      source: Theme.wallpaperUrl
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: 480
      asynchronous: true
      smooth: true
      cache: true
    }

    Image {
      visible: desk.pan !== 0
      x: paper.x + (desk.pan > 0 ? desk.width : -desk.width)
      width: desk.width
      height: desk.height
      source: paper.source
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: 480
      asynchronous: true
      smooth: true
    }

    Rectangle {
      anchors.fill: parent
      color: Tokens.scrim(Theme.dark, 1.3)
      opacity: desk.dim
    }

    Item {
      id: contentLayer
      anchors.fill: parent
    }

    Item {
      id: overlayLayer
      anchors.fill: parent
    }

    // Barra de menus.
    Rectangle {
      width: parent.width
      height: 6.5 * desk.u
      opacity: desk.menubarOpacity
      color: Tokens.glassStrong(Theme.dark)

      Rectangle {
        x: 4 * desk.u
        anchors.verticalCenter: parent.verticalCenter
        width: 3.2 * desk.u
        height: width
        radius: width / 2
        color: Theme.label
        opacity: 0.8
      }
      Row {
        x: 10 * desk.u
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * desk.u
        Repeater {
          model: [10, 7, 7, 6]
          Rectangle {
            required property real modelData
            width: modelData * desk.u
            height: 1.6 * desk.u
            radius: height / 2
            color: Theme.label
            opacity: 0.55
          }
        }
      }
      Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 4 * desk.u
        anchors.verticalCenter: parent.verticalCenter
        width: 14 * desk.u
        height: 1.6 * desk.u
        radius: height / 2
        color: Theme.label
        opacity: 0.55
      }
    }

    // Dock.
    Rectangle {
      visible: desk.showDock
      opacity: desk.dockOpacity
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 3 * desk.u
      width: dockRow.width + 5 * desk.u
      height: 10.5 * desk.u
      radius: 3.6 * desk.u
      color: Tokens.glass(Theme.dark)
      border.width: 1
      border.color: Tokens.withAlpha(Theme.white, Theme.dark ? 0.10 : 0.45)

      Row {
        id: dockRow
        anchors.centerIn: parent
        spacing: 2 * desk.u
        Repeater {
          model: [Theme.blue, Theme.orange, Theme.green, Theme.purple, Theme.red, Theme.teal, Theme.gray]
          Rectangle {
            required property color modelData
            width: 6.8 * desk.u
            height: width
            radius: 1.8 * desk.u
            color: modelData
          }
        }
      }
    }
  }

  Item {
    id: roundMask
    anchors.fill: parent
    layer.enabled: true
    visible: false
    Rectangle {
      anchors.fill: parent
      radius: desk.radius
      antialiasing: true
      color: "black"
    }
  }

  // Moldura por cima: contorno fino como o de uma tela.
  Rectangle {
    anchors.fill: parent
    radius: desk.radius
    color: "transparent"
    antialiasing: true
    border.width: 1
    border.color: Theme.outline
  }
}
