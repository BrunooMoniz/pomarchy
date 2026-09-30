import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "shared"
import "shared/Tokens.js" as Tokens
import "shared/Apps.js" as Apps

// Miniatura de uma mesa na faixa de cima do Mission Control: papel de parede
// e as janelas dela no lugar certo, em escala. Clicar vai para a mesa; soltar
// uma janela arrastada aqui muda a janela de mesa.
Item {
  id: root

  property var workspace: null
  property var windows: []
  property var clients: null            // HyprClients, para achar o Toplevel
  property real monitorWidth: 1920
  property real monitorHeight: 1200
  property real monitorX: 0
  property real monitorY: 0
  property string wallpaper: ""
  property bool current: false
  property bool dropTarget: false
  property bool dark: true
  property color accent: "#0a84ff"
  property string label: ""
  property bool isNew: false            // o botão "+ Nova mesa"

  signal clicked()

  readonly property real ratio: height > 0 ? thumb.height / monitorHeight : 0.1
  readonly property bool hovered: pointer.containsMouse

  width: Math.round((height - 24) * monitorWidth / Math.max(1, monitorHeight))

  function hit(sceneX, sceneY) {
    var p = root.mapFromItem(null, sceneX, sceneY)
    return p.x >= 0 && p.y >= 0 && p.x <= root.width && p.y <= thumb.height
  }

  Item {
    id: thumb
    width: parent.width
    height: parent.height - 24
    scale: root.hovered || root.dropTarget ? 1.05 : 1.0
    Behavior on scale { NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic } }

    RectangularShadow {
      anchors.fill: card
      radius: 9
      blur: 18
      offset.y: 6
      color: Qt.rgba(0, 0, 0, 0.35)
      visible: !root.isNew
    }

    Item {
      id: card
      anchors.fill: parent
      visible: !root.isNew
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: cardMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      Rectangle { anchors.fill: parent; color: root.dark ? "#1b2440" : "#c9d8f0" }
      Image {
        anchors.fill: parent
        source: root.wallpaper ? "file://" + root.wallpaper : ""
        sourceSize: Qt.size(480, 300)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
      }

      Repeater {
        model: root.windows
        delegate: Item {
          required property var modelData
          x: (modelData.at[0] - root.monitorX) * root.ratio
          y: (modelData.at[1] - root.monitorY) * root.ratio
          width: Math.max(4, modelData.size[0] * root.ratio)
          height: Math.max(4, modelData.size[1] * root.ratio)
          z: 1000 - (modelData.focusHistoryID || 0)
          Rectangle {
            anchors.fill: parent
            radius: 3
            color: root.dark ? Qt.rgba(0.25, 0.25, 0.28, 1) : Qt.rgba(0.97, 0.97, 0.98, 1)
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.18)
          }
          ScreencopyView {
            anchors.fill: parent
            captureSource: root.clients ? root.clients.toplevelFor(modelData.address) : null
            live: false
          }
        }
      }
    }

    Item {
      id: cardMask
      anchors.fill: parent
      layer.enabled: true
      visible: false
      Rectangle { anchors.fill: parent; radius: 9; color: "black"; antialiasing: true }
    }

    // Mesa atual ou alvo de soltura: contorno na cor de destaque.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -3
      radius: 12
      color: "transparent"
      border.width: 3
      border.color: root.accent
      visible: !root.isNew && (root.current || root.dropTarget)
      opacity: root.dropTarget ? 1 : 0.9
    }

    // "+ Nova mesa"
    Item {
      anchors.fill: parent
      visible: root.isNew
      // Discreto como o "+" do Mission Control: quase só o contorno, e ganha
      // corpo no hover ou quando uma janela é arrastada até ele.
      Glass {
        anchors.fill: parent
        dark: root.dark
        radius: 12
        fill: root.hovered || root.dropTarget ? Tokens.glassStrong(root.dark) : Qt.rgba(1, 1, 1, root.dark ? 0.08 : 0.22)
        shadow: root.hovered || root.dropTarget
        shadowBlur: 14
        shadowOffsetY: 4
      }
      Text {
        anchors.centerIn: parent
        text: "+"
        color: root.hovered || root.dropTarget ? Tokens.label(root.dark) : "white"
        font.pixelSize: Math.round(parent.height * 0.42)
        font.weight: Font.Light
      }
      Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: 14
        color: "transparent"
        border.width: 3
        border.color: root.accent
        visible: root.dropTarget
      }
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    text: root.label
    color: "white"
    font.pixelSize: 12
    font.weight: root.current ? Font.DemiBold : Font.Normal
    style: Text.Raised
    styleColor: Qt.rgba(0, 0, 0, 0.35)
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
