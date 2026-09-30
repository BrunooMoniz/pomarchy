import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Ilustração animada de um gesto: à esquerda o trackpad com as pontas dos
// dedos se movendo, à direita a telinha mostrando o que acontece.
//   gesture: "spaces" (trocar de mesa), "mission" (para cima), "expose"
//            (para baixo), "launchpad" (pinça) ou "launchpadClose" (abrir dedos)
//   fingers: 3 ou 4 (a pinça usa sempre polegar + três dedos)
// Tudo é medido em `u` (a cena foi desenhada em 320 x 150) para a mesma
// ilustração servir no Trackpad e, maior, nas boas-vindas.
Item {
  id: scene

  property string gesture: "spaces"
  property int fingers: 3
  property bool active: true

  implicitWidth: 320
  implicitHeight: 150

  readonly property real u: Math.max(0.2, Math.min(width / 320, height / 150))
  readonly property bool pinch: gesture === "launchpad" || gesture === "launchpadClose"
  readonly property bool closing: gesture === "launchpadClose"
  readonly property bool animating: active && visible && width > 0

  // Estado da animação: dedos encostados (touch), percurso do gesto (travel),
  // resultado na telinha (effect) e sentido na troca de mesa (direction).
  property real touch: 0
  property real travel: 0
  property real effect: closing ? 1 : 0
  property int direction: 1

  readonly property real padW: 128 * u
  readonly property real padH: 90 * u
  readonly property real deskW: 150 * u
  readonly property real deskH: 96 * u
  readonly property real gap: 20 * u
  readonly property real originX: (width - padW - gap - deskW) / 2

  // ------------------------------------------------------------ dedos
  function points(t) {
    var out = []
    if (scene.pinch) {
      var spread = scene.closing ? Tokens.lerp(0.5, 1, t) : Tokens.lerp(1, 0.5, t)
      var base = [[-0.21, -0.15], [-0.03, -0.24], [0.16, -0.17], [-0.13, 0.26]]
      for (var i = 0; i < base.length; i++)
        out.push({ x: 0.52 + base[i][0] * spread, y: 0.5 + base[i][1] * spread, thumb: i === 3 })
      return out
    }
    var n = scene.fingers === 4 ? 4 : 3
    var xs = n === 4 ? [-1.5, -0.5, 0.5, 1.5] : [-1, 0, 1]
    var ys = n === 4 ? [0.07, -0.02, -0.04, 0.05] : [0.05, -0.04, 0.03]
    var cx = 0.5
    var cy = 0.5
    if (scene.gesture === "spaces") cx = 0.5 + 0.18 * scene.direction - 0.36 * scene.direction * t
    else if (scene.gesture === "mission") cy = 0.70 - 0.40 * t
    else if (scene.gesture === "expose") cy = 0.30 + 0.40 * t
    for (var j = 0; j < n; j++)
      out.push({ x: cx + xs[j] * 0.135, y: cy + ys[j], thumb: false })
    return out
  }

  readonly property var now: points(travel)
  readonly property var start: points(0)

  // ------------------------------------------------------------ linha do tempo
  function reset() {
    touch = 0
    travel = 0
    direction = 1
    effect = closing ? 1 : 0
  }

  onAnimatingChanged: if (!animating) reset()

  // Gestos de ida e volta pelo mesmo caminho (Mission, Exposé, Launchpad):
  // encosta, desliza, levanta, mostra o resultado e volta ao começo.
  SequentialAnimation {
    running: scene.animating && scene.gesture !== "spaces"
    loops: Animation.Infinite
    PropertyAction { target: scene; property: "travel"; value: 0 }
    PauseAnimation { duration: 260 }
    NumberAnimation { target: scene; property: "touch"; to: 1; duration: 240; easing.type: Easing.OutCubic }
    ParallelAnimation {
      NumberAnimation { target: scene; property: "travel"; to: 1; duration: 980; easing.type: Easing.InOutCubic }
      NumberAnimation { target: scene; property: "effect"; to: scene.closing ? 0 : 1; duration: 980; easing.type: Easing.InOutCubic }
    }
    NumberAnimation { target: scene; property: "touch"; to: 0; duration: 260; easing.type: Easing.InCubic }
    PauseAnimation { duration: 480 }
    NumberAnimation { target: scene; property: "effect"; to: scene.closing ? 1 : 0; duration: 520; easing.type: Easing.InOutQuad }
  }

  // Troca de mesa: vai para a mesa 2 deslizando para a esquerda e volta para
  // a 1 deslizando para a direita.
  SequentialAnimation {
    running: scene.animating && scene.gesture === "spaces"
    loops: Animation.Infinite
    PropertyAction { target: scene; property: "direction"; value: 1 }
    PropertyAction { target: scene; property: "travel"; value: 0 }
    NumberAnimation { target: scene; property: "touch"; to: 1; duration: 240; easing.type: Easing.OutCubic }
    ParallelAnimation {
      NumberAnimation { target: scene; property: "travel"; to: 1; duration: 900; easing.type: Easing.InOutCubic }
      NumberAnimation { target: scene; property: "effect"; to: 1; duration: 900; easing.type: Easing.InOutCubic }
    }
    NumberAnimation { target: scene; property: "touch"; to: 0; duration: 240; easing.type: Easing.InCubic }
    PauseAnimation { duration: 420 }
    PropertyAction { target: scene; property: "direction"; value: -1 }
    PropertyAction { target: scene; property: "travel"; value: 0 }
    NumberAnimation { target: scene; property: "touch"; to: 1; duration: 240; easing.type: Easing.OutCubic }
    ParallelAnimation {
      NumberAnimation { target: scene; property: "travel"; to: 1; duration: 900; easing.type: Easing.InOutCubic }
      NumberAnimation { target: scene; property: "effect"; to: 0; duration: 900; easing.type: Easing.InOutCubic }
    }
    NumberAnimation { target: scene; property: "touch"; to: 0; duration: 240; easing.type: Easing.InCubic }
    PauseAnimation { duration: 420 }
  }

  // ------------------------------------------------------------ trackpad
  RectangularShadow {
    anchors.fill: pad
    radius: pad.radius
    blur: 10 * scene.u
    offset.y: 3 * scene.u
    color: Tokens.withAlpha(Theme.shadow, Theme.dark ? 0.5 : 0.22)
  }

  Rectangle {
    id: pad
    x: scene.originX
    y: (scene.height - scene.padH) / 2
    width: scene.padW
    height: scene.padH
    radius: 11 * scene.u
    antialiasing: true
    gradient: Gradient {
      GradientStop { position: 0; color: Theme.dark ? Tokens.mix(Theme.card, Theme.white, 0.16) : Tokens.mix(Theme.card, Theme.label, 0.06) }
      GradientStop { position: 1; color: Theme.dark ? Tokens.mix(Theme.card, Theme.white, 0.08) : Tokens.mix(Theme.card, Theme.label, 0.13) }
    }
    border.width: 1
    border.color: Theme.dark ? Tokens.withAlpha(Theme.white, 0.16) : Tokens.withAlpha(Theme.label, 0.16)

    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: parent.radius - 1
      color: "transparent"
      border.width: 1
      border.color: Theme.highlight
      opacity: Theme.dark ? 0.35 : 0.9
    }
  }

  // Rastro de cada dedo: do ponto onde encostou até onde está agora.
  Repeater {
    model: 4
    Rectangle {
      id: trail
      required property int index
      readonly property var from: index < scene.start.length ? scene.start[index] : null
      readonly property var to: index < scene.now.length ? scene.now[index] : null
      readonly property real r: (to && to.thumb ? 9.5 : 8) * scene.u
      readonly property real ax: from ? pad.x + from.x * scene.padW : 0
      readonly property real ay: from ? pad.y + from.y * scene.padH : 0
      readonly property real bx: to ? pad.x + to.x * scene.padW : 0
      readonly property real by: to ? pad.y + to.y * scene.padH : 0
      readonly property real length: Math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))
      visible: to !== null && length > 1
      x: bx
      y: by - r
      width: length + r
      height: r * 2
      radius: r
      transformOrigin: Item.Left
      rotation: Math.atan2(ay - by, ax - bx) * 180 / Math.PI
      // Na pinça os rastros convergem e embolam: ficam mais leves.
      opacity: scene.touch * (scene.pinch ? 0.45 : 0.9)
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Tokens.withAlpha(Theme.accent, 0.30) }
        GradientStop { position: 1; color: Tokens.withAlpha(Theme.accent, 0.0) }
      }
    }
  }

  // Pontas dos dedos.
  Repeater {
    model: 4
    Item {
      id: finger
      required property int index
      readonly property var p: index < scene.now.length ? scene.now[index] : null
      readonly property real r: (p && p.thumb ? 9.5 : 8) * scene.u
      visible: p !== null
      x: p ? pad.x + p.x * scene.padW - r : 0
      y: p ? pad.y + p.y * scene.padH - r : 0
      width: r * 2
      height: r * 2
      opacity: scene.touch
      scale: 1.3 - 0.3 * scene.touch

      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 1.5
        height: width
        radius: width / 2
        color: Tokens.withAlpha(Theme.accent, 0.14)
      }

      RectangularShadow {
        anchors.fill: tip
        radius: tip.radius
        blur: 4 * scene.u
        offset.y: 1 * scene.u
        color: Tokens.withAlpha(Theme.shadow, 0.5)
      }

      Rectangle {
        id: tip
        anchors.fill: parent
        radius: width / 2
        antialiasing: true
        color: Theme.accent
        border.width: Math.max(1, 1.6 * scene.u)
        border.color: Theme.white
      }
    }
  }

  // ------------------------------------------------------------ telinha
  MiniDesktop {
    id: desk
    x: pad.x + scene.padW + scene.gap
    y: (scene.height - scene.deskH) / 2
    width: scene.deskW
    height: scene.deskH
    u: scene.u

    readonly property real e: scene.effect
    readonly property real k: scene.u
    readonly property bool spaces: scene.gesture === "spaces"
    readonly property bool mission: scene.gesture === "mission"
    readonly property bool expose: scene.gesture === "expose"

    pan: spaces ? e : 0
    dim: mission || expose ? 0.55 * e : (scene.pinch ? 0.75 * e : 0)
    menubarOpacity: spaces ? 1 : 1 - e

    function lerpRect(a, b, t) {
      return { x: Tokens.lerp(a[0], b[0], t) * k, y: Tokens.lerp(a[1], b[1], t) * k,
               w: Tokens.lerp(a[2], b[2], t) * k, h: Tokens.lerp(a[3], b[3], t) * k }
    }

    // Janelas da mesa 1. A e D são do mesmo app (mesma cor), B é de outro.
    readonly property var restA: [12, 15, 66, 46]
    readonly property var restB: [60, 27, 74, 50]
    readonly property var restD: [30, 44, 60, 36]
    readonly property var rectA: mission ? lerpRect(restA, [7, 36, 43, 30], e)
      : expose ? lerpRect(restA, [10, 30, 62, 42], e) : lerpRect(restA, restA, 0)
    readonly property var rectB: mission ? lerpRect(restB, [54, 36, 43, 30], e)
      : expose ? lerpRect(restB, [62, 60, 30, 20], e) : lerpRect(restB, restB, 0)
    readonly property var rectD: mission ? lerpRect(restD, [100, 36, 43, 30], e)
      : expose ? lerpRect(restD, [78, 30, 62, 42], e) : lerpRect(restD, restD, 0)
    readonly property real slide: spaces ? -e * scene.deskW : 0
    readonly property real windowsOpacity: scene.pinch ? 1 - e : 1

    MiniWindow {
      u: desk.k
      tint: Theme.blue
      x: desk.rectA.x + desk.slide
      y: desk.rectA.y
      width: desk.rectA.w
      height: desk.rectA.h
      opacity: desk.windowsOpacity
      scale: scene.pinch ? 1 - 0.06 * desk.e : 1
    }
    MiniWindow {
      u: desk.k
      tint: Theme.orange
      x: desk.rectB.x + desk.slide
      y: desk.rectB.y
      width: desk.rectB.w
      height: desk.rectB.h
      opacity: desk.expose ? 1 - desk.e : desk.windowsOpacity
      scale: scene.pinch ? 1 - 0.06 * desk.e : 1
    }
    MiniWindow {
      u: desk.k
      tint: Theme.blue
      lifted: desk.expose && desk.e > 0.5
      x: desk.rectD.x + desk.slide
      y: desk.rectD.y
      width: desk.rectD.w
      height: desk.rectD.h
      opacity: desk.windowsOpacity
      scale: scene.pinch ? 1 - 0.06 * desk.e : 1
    }
    // Mesa 2 (só aparece na troca de mesa).
    MiniWindow {
      visible: desk.spaces
      u: desk.k
      tint: Theme.green
      x: 36 * desk.k + scene.deskW + desk.slide
      y: 18 * desk.k
      width: 80 * desk.k
      height: 54 * desk.k
    }
  }

  // Barra das mesas que desce no Mission Control.
  Row {
    visible: desk.mission
    parent: desk.overlay
    anchors.horizontalCenter: parent.horizontalCenter
    y: Tokens.lerp(-22, 7, desk.e) * scene.u
    opacity: desk.e
    spacing: 6 * scene.u
    Repeater {
      model: 3
      Rectangle {
        required property int index
        width: 30 * scene.u
        height: 19 * scene.u
        radius: 2.4 * scene.u
        color: Tokens.withAlpha(Theme.white, index === 0 ? 0.55 : 0.28)
        border.width: index === 0 ? Math.max(1, 1.2 * scene.u) : 1
        border.color: index === 0 ? Theme.white : Tokens.withAlpha(Theme.white, 0.5)
      }
    }
  }

  // Grade de apps do Launchpad.
  Item {
    parent: desk.overlay
    visible: scene.pinch
    anchors.fill: parent
    opacity: desk.e
    scale: Tokens.lerp(1.18, 1, desk.e)

    Grid {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -4 * scene.u
      columns: 5
      spacing: 8 * scene.u
      Repeater {
        model: [Theme.blue, Theme.orange, Theme.green, Theme.purple, Theme.red,
                Theme.teal, Theme.gray, Theme.blue, Theme.green, Theme.orange,
                Theme.purple, Theme.red, Theme.gray, Theme.teal, Theme.blue]
        Rectangle {
          required property color modelData
          width: 12 * scene.u
          height: width
          radius: 3.2 * scene.u
          antialiasing: true
          gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(modelData, 1.15) }
            GradientStop { position: 1; color: modelData }
          }
        }
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 17 * scene.u
      spacing: 3 * scene.u
      Repeater {
        model: 2
        Rectangle {
          required property int index
          width: 3 * scene.u
          height: width
          radius: width / 2
          color: Theme.white
          opacity: index === 0 ? 0.9 : 0.4
        }
      }
    }
  }
}
