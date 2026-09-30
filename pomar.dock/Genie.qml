import QtQuick
import Quickshell
import Quickshell.Wayland

// O efeito "gênio" do macOS ao minimizar e ao restaurar: a imagem ao vivo da
// janela escorre para o lugar dela no Dock (ou sai dele de volta). Fica numa
// camada própria por cima de tudo, sem mouse nem teclado; a janela de verdade
// sai de cena por baixo logo depois que o efeito começa.
PanelWindow {
  id: win

  property var toplevel: null
  // Retângulos em coordenadas da tela do Dock.
  property rect fromRect: Qt.rect(0, 0, 100, 100)
  property rect toRect: Qt.rect(0, 0, 54, 54)
  property real progress: 0
  property bool running: false
  property int duration: 560
  signal done(bool reversed)

  property bool reversed: false

  visible: running
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "pomar-genie"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {}

  // Janela -> Dock (minimizar) ou Dock -> janela (restaurar). O destino
  // (toRect) vem ligado ao lugar do item no Dock e acompanha se ele mudar.
  function play(toplevel, fromRect, reverse) {
    anim.stop()
    win.toplevel = toplevel
    win.fromRect = fromRect
    win.reversed = reverse === true
    win.progress = win.reversed ? 1 : 0
    win.running = true
    anim.from = win.progress
    anim.to = win.reversed ? 0 : 1
    anim.duration = win.duration
    anim.start()
  }

  function stop() {
    anim.stop()
    win.running = false
  }

  NumberAnimation {
    id: anim
    target: win
    property: "progress"
    easing.type: Easing.InOutSine
    onFinished: {
      win.running = false
      win.done(win.reversed)
    }
  }

  ScreencopyView {
    id: capture
    width: Math.max(1, win.fromRect.width)
    height: Math.max(1, win.fromRect.height)
    captureSource: win.running ? win.toplevel : null
    live: true
  }

  ShaderEffectSource {
    id: texture
    sourceItem: capture
    hideSource: true
    live: true
    smooth: true
  }

  ShaderEffect {
    anchors.fill: parent
    visible: capture.hasContent
    property variant source: texture
    property real progress: win.progress
    property real radius: 12
    property vector4d sourceRect: Qt.vector4d(win.fromRect.x, win.fromRect.y, win.fromRect.width, win.fromRect.height)
    property vector4d targetRect: Qt.vector4d(win.toRect.x, win.toRect.y, win.toRect.width, win.toRect.height)
    mesh: GridMesh { resolution: Qt.size(8, 48) }
    vertexShader: Qt.resolvedUrl("shaders/genie.vert.qsb")
    fragmentShader: Qt.resolvedUrl("shaders/genie.frag.qsb")
  }
}
