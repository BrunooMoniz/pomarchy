import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "shared"
import "shared/Tokens.js" as Tokens
import "shared/Apps.js" as Apps
import "Strings.js" as Strings
import "shared/I18n.js" as I18n

// Uma janela no Mission Control: a imagem ao vivo da janela voa do lugar
// real (progress 0) para o lugar no arranjo (progress 1). Em 0 ela cobre a
// janela de verdade pixel a pixel, por isso o gesto parece mover as janelas.
Item {
  id: root

  property var client: null
  property var toplevel: null
  property var source: ({ x: 0, y: 0, w: 100, h: 100 })
  property var target: ({ x: 0, y: 0, w: 100, h: 100 })
  property real progress: 0
  property bool dark: true
  property bool selected: false
  property bool live: true
  property bool fadeFromTarget: false
  property string lang: "pt"
  property color accent: "#0a84ff"
  property var webIndex: ({})

  // Centro do X (em coordenadas da janela do Mission Control) e se está à vista.
  function closeInfo() {
    var p = closeButton.mapToItem(null, closeButton.width / 2, closeButton.height / 2)
    return { x: p.x, y: p.y, shown: closeButton.visible && closeButton.opacity > 0.9, hovered: root.hovered,
             address: client ? String(client.address) : "" }
  }

  signal activated()
  signal closeRequested()
  signal hoverChanged(bool isHovered)
  signal dragStarted(real x, real y)
  signal dragMoved(real x, real y)
  signal dragFinished(real x, real y)

  readonly property bool chrome: progress > 0.55
  readonly property bool ready: view.hasContent
  // Enquanto o Mission Control não está pronto, sem imagem não se desenha nada
  // (a janela de verdade continua visível atrás).
  property bool primed: true
  // O X fica no canto, metade para fora da miniatura e por cima dela: com o
  // cursor nele a miniatura continua "em hover", senão o X some antes do clique.
  readonly property bool hovered: (pointer.containsMouse || closeMouse.containsMouse) && chrome
  readonly property var entry: client ? Apps.entryFor(DesktopEntries, client["class"] || client.initialClass, webIndex) : null
  readonly property string appName: Apps.displayName(entry, client ? client["class"] : "")
  readonly property real t: Math.max(0, Math.min(1, progress))
  // Janela de outra mesa (App Exposé) não tem lugar real na tela: nasce já no
  // arranjo, pequena e transparente.
  readonly property real fx: fadeFromTarget ? target.x + target.w * 0.08 : source.x
  readonly property real fy: fadeFromTarget ? target.y + target.h * 0.08 : source.y
  readonly property real fw: fadeFromTarget ? target.w * 0.84 : source.w
  readonly property real fh: fadeFromTarget ? target.h * 0.84 : source.h
  readonly property real hoverLift: hovered || selected ? 1.025 : 1.0

  x: Tokens.lerp(fx, target.x, t)
  y: Tokens.lerp(fy, target.y, t)
  width: Math.max(8, Tokens.lerp(fw, target.w, t))
  height: Math.max(8, Tokens.lerp(fh, target.h, t))
  opacity: fadeFromTarget ? t : 1
  scale: hoverLift
  transformOrigin: Item.Center

  Behavior on scale { NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic } }

  RectangularShadow {
    anchors.fill: frame
    radius: frame.radius
    blur: 26
    spread: -4
    offset.y: 10
    color: Qt.rgba(0, 0, 0, 0.42 * root.t)
  }

  Item {
    id: frame
    property real radius: Tokens.lerp(12, 10, root.t)
    anchors.fill: parent

    Rectangle {
      id: placeholder
      anchors.fill: parent
      radius: frame.radius
      color: root.dark ? Qt.rgba(0.2, 0.2, 0.22, 0.9) : Qt.rgba(0.95, 0.95, 0.96, 0.92)
      visible: !view.hasContent && root.primed
      AppIconTile {
        anchors.centerIn: parent
        width: Math.min(64, parent.width * 0.4)
        height: width
        textureSize: 128
        source: Apps.iconSource(Quickshell, root.entry, root.client ? root.client["class"] : "")
        dark: root.dark
      }
    }

    ScreencopyView {
      id: view
      anchors.fill: parent
      captureSource: root.toplevel
      live: root.live
      visible: false
    }

    MultiEffect {
      anchors.fill: parent
      source: view
      visible: view.hasContent
      maskEnabled: true
      maskSource: mask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }

    Item {
      id: mask
      anchors.fill: parent
      layer.enabled: true
      visible: false
      Rectangle { anchors.fill: parent; radius: frame.radius; color: "black"; antialiasing: true }
    }

    // Anel de seleção (hover ou teclado), como o destaque azul do macOS.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -4
      radius: frame.radius + 4
      color: "transparent"
      border.width: 3
      border.color: root.accent
      opacity: (root.hovered || root.selected) && root.chrome ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Tokens.motion.fast } }
    }
  }

  // Ícone do app no pé da janela: ajuda a reconhecer cada uma de relance.
  AppIconTile {
    id: badge
    width: 40
    height: 40
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height - height * 0.6
    textureSize: 80
    source: Apps.iconSource(Quickshell, root.entry, root.client ? root.client["class"] : "")
    dark: root.dark
    opacity: root.chrome ? 1 : 0
    scale: root.chrome ? 1 : 0.6
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.base } }
    Behavior on scale { NumberAnimation { duration: Tokens.motion.base; easing.type: Easing.OutBack } }
  }

  // Título em pílula de vidro, só no hover.
  Item {
    id: titlePill
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height + 26
    width: Math.min(Math.max(parent.width, 180), titleText.implicitWidth + 28)
    height: 28
    opacity: root.hovered || root.selected ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.fast } }
    Glass { anchors.fill: parent; dark: root.dark; radius: height / 2; fill: Tokens.glassStrong(root.dark); shadowBlur: 16; shadowOffsetY: 4 }
    Text {
      id: titleText
      anchors.centerIn: parent
      width: parent.width - 24
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.client ? (root.client.title || root.appName) : ""
      color: Tokens.label(root.dark)
      font.pixelSize: 13
      font.weight: Font.Medium
    }
  }

  // Botão fechar no canto, como no Mission Control do macOS.
  Item {
    id: closeButton
    width: 26
    height: 26
    x: -9
    y: -9
    visible: opacity > 0
    opacity: root.hovered ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.fast } }
    Glass { anchors.fill: parent; dark: root.dark; radius: width / 2; fill: Tokens.glassStrong(root.dark); shadowBlur: 10; shadowOffsetY: 2 }
    Text {
      anchors.centerIn: parent
      text: "✕"
      color: closeMouse.containsMouse ? root.accent : Tokens.label(root.dark)
      font.pixelSize: 12
      font.bold: true
    }
    MouseArea {
      id: closeMouse
      anchors.fill: parent
      anchors.margins: -4
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested()
    }
    z: 2
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    property point pressPoint
    property bool dragging: false
    onContainsMouseChanged: root.hoverChanged(containsMouse)
    onPressed: function(event) { pressPoint = Qt.point(event.x, event.y); dragging = false }
    onPositionChanged: function(event) {
      if (!pressed || event.buttons !== Qt.LeftButton) return
      var moved = Math.abs(event.x - pressPoint.x) + Math.abs(event.y - pressPoint.y)
      var p = mapToItem(null, event.x, event.y)
      if (!dragging && moved > 10) { dragging = true; root.dragStarted(p.x, p.y) }
      else if (dragging) root.dragMoved(p.x, p.y)
    }
    onReleased: function(event) {
      var p = mapToItem(null, event.x, event.y)
      if (dragging) { dragging = false; root.dragFinished(p.x, p.y); return }
      if (event.button === Qt.MiddleButton) root.closeRequested()
      else root.activated()
    }
    z: 1
  }
}
