import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Legendas e ilustração de gestos para o vídeo de demonstração do Pomarchy
// OS. Roda só no Hyprland de teste, como uma segunda instância do Quickshell,
// e é comandada por IPC (qs ipc -p tools/demo/hud call hud ...).
ShellRoot {
  id: hud

  property string title: ""
  property string subtitle: ""
  property bool card: false
  property string gesture: ""       // up, down, left, right, pinch, spread
  property int fingers: 3
  property var keys: []
  property real gestureProgress: 0

  IpcHandler {
    target: "hud"
    function caption(title: string, subtitle: string): void { hud.title = title; hud.subtitle = subtitle }
    function clear(): void { hud.title = ""; hud.subtitle = ""; hud.gesture = ""; hud.keys = [] }
    function showCard(title: string, subtitle: string): void { hud.card = true; hud.title = title; hud.subtitle = subtitle }
    function hideCard(): void { hud.card = false }
    function showGesture(kind: string, fingers: int, ms: int): void {
      hud.gesture = kind; hud.fingers = fingers; gestureAnim.duration = ms; gestureAnim.restart()
    }
    function hideGesture(): void { hud.gesture = "" }
    function showKeys(list: string): void { hud.keys = list.length ? list.split("+") : [] }
  }

  NumberAnimation { id: gestureAnim; target: hud; property: "gestureProgress"; from: 0; to: 1; easing.type: Easing.InOutSine }

  PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "demo-hud"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    // Cartão de abertura e fechamento.
    Rectangle {
      anchors.fill: parent
      visible: opacity > 0
      opacity: hud.card ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 500 } }
      gradient: Gradient {
        GradientStop { position: 0; color: "#0b1a3a" }
        GradientStop { position: 1; color: "#3a1d4f" }
      }
      Column {
        anchors.centerIn: parent
        spacing: 18
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: hud.title; color: "white"; font.pixelSize: 76; font.weight: Font.Bold; font.family: "Adwaita Sans" }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: hud.subtitle; color: Qt.rgba(1, 1, 1, 0.75); font.pixelSize: 30; font.family: "Adwaita Sans" }
      }
    }

    // Legenda no alto, abaixo da barra.
    Item {
      visible: !hud.card && hud.title !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      y: 58
      width: captionColumn.implicitWidth + 56
      height: captionColumn.implicitHeight + 28
      RectangularShadow { anchors.fill: pill; radius: pill.radius; blur: 30; offset.y: 8; color: Qt.rgba(0, 0, 0, 0.35) }
      Rectangle { id: pill; anchors.fill: parent; radius: 22; color: Qt.rgba(0.08, 0.08, 0.1, 0.86); border.color: Qt.rgba(1, 1, 1, 0.12) }
      Column {
        id: captionColumn
        anchors.centerIn: parent
        spacing: 4
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: hud.title; color: "white"; font.pixelSize: 26; font.weight: Font.DemiBold; font.family: "Adwaita Sans" }
        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: text !== ""; text: hud.subtitle; color: Qt.rgba(1, 1, 1, 0.72); font.pixelSize: 17; font.family: "Adwaita Sans" }
      }
    }

    // Trackpad com os dedos, no canto de baixo à esquerda.
    Item {
      id: pad
      visible: hud.gesture !== "" && !hud.card
      x: 36
      y: parent.height - height - 36
      width: 260
      height: 170
      RectangularShadow { anchors.fill: padBody; radius: 18; blur: 28; offset.y: 8; color: Qt.rgba(0, 0, 0, 0.4) }
      Rectangle { id: padBody; anchors.fill: parent; radius: 18; color: Qt.rgba(0.1, 0.1, 0.12, 0.88); border.color: Qt.rgba(1, 1, 1, 0.18) }
      Repeater {
        model: hud.fingers
        delegate: Rectangle {
          required property int index
          readonly property real t: hud.gestureProgress
          readonly property real spread: (index - (hud.fingers - 1) / 2) * 36
          readonly property real dx: hud.gesture === "left" ? -70 * t : hud.gesture === "right" ? 70 * t : 0
          readonly property real dy: hud.gesture === "up" ? -45 * t : hud.gesture === "down" ? 45 * t : 0
          readonly property real pinchScale: hud.gesture === "pinch" ? 1 - 0.65 * t : hud.gesture === "spread" ? 0.35 + 0.65 * t : 1
          width: 30; height: 30; radius: 15
          color: Qt.rgba(1, 1, 1, 0.92)
          x: pad.width / 2 - 15 + spread * pinchScale + dx
          y: pad.height / 2 - 15 + dy + (hud.gesture === "pinch" || hud.gesture === "spread" ? (index % 2 ? 18 : -18) * pinchScale : 0)
          opacity: 0.35 + 0.65 * Math.min(1, t * 4)
        }
      }
    }

    // Teclas pressionadas, no canto de baixo à direita.
    Row {
      visible: hud.keys.length > 0 && !hud.card
      spacing: 10
      x: parent.width - width - 40
      y: parent.height - height - 40
      Repeater {
        model: hud.keys
        delegate: Rectangle {
          required property string modelData
          width: Math.max(64, keyText.implicitWidth + 30); height: 58; radius: 12
          color: Qt.rgba(0.1, 0.1, 0.12, 0.9); border.color: Qt.rgba(1, 1, 1, 0.25); border.width: 1
          Text { id: keyText; anchors.centerIn: parent; text: modelData; color: "white"; font.pixelSize: 22; font.weight: Font.DemiBold; font.family: "Adwaita Sans" }
        }
      }
    }
  }
}
