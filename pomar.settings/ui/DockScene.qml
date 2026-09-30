import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Ilustração do Dock: telinha com o Dock embaixo e um ponteiro que passa
// pelos ícones. Com ampliação ligada os ícones crescem em sino, como no Mac.
// Em `demo` o ponteiro clica num app: o ícone quica e a janela abre.
// Na página do Dock ela acompanha o tamanho e a ampliação escolhidos.
Item {
  id: scene

  property bool active: true
  property bool demo: true
  // Medidas do Dock de verdade, em px; a cena reduz pela escala `zoom`.
  property real iconSize: 54
  property real magnifiedSize: 82
  property bool magnification: true
  property bool showTrash: true

  implicitWidth: 560
  implicitHeight: 240

  readonly property bool animating: active && visible && width > 0
  readonly property real u: Math.max(0.2, Math.min(width / 560, height / 240))
  // Px da cena por px do Dock de verdade.
  property real zoom: 0.62 * u
  readonly property real base: iconSize * zoom
  readonly property real peak: (magnification ? Math.max(iconSize, magnifiedSize) : iconSize) * zoom
  readonly property real spacing: Math.max(3, base * 0.14)

  // 0..1 ao longo do Dock; negativo = ponteiro fora do Dock.
  property real pointer: -1
  property real bounce: 0
  property real windowOpen: 0

  readonly property var tints: [Theme.blue, Theme.orange, Theme.green, Theme.purple, Theme.red, Theme.teal, Theme.gray]
  readonly property var glyphs: ["launchpad", "sparkle", "leaf", "mission", "keyboard", "trackpad", "gear"]
  readonly property int clickIndex: 2
  readonly property int count: tints.length + (showTrash ? 1 : 0)

  function reset() {
    pointer = -1
    bounce = 0
    windowOpen = 0
  }

  onAnimatingChanged: if (!animating) reset()

  // Tamanho de cada ícone para o ponteiro na posição atual.
  function sizeAt(index) {
    if (!magnification || pointer < 0) return base
    var restWidth = count * base + (count - 1) * spacing
    var center = index * (base + spacing) + base / 2
    var distance = Math.abs(center - pointer * restWidth)
    return base + (peak - base) * Tokens.magnify(distance, base * 2.6)
  }

  SequentialAnimation {
    running: scene.animating
    loops: Animation.Infinite
    PropertyAction { target: scene; property: "pointer"; value: 0.02 }
    NumberAnimation { target: scene; property: "pointer"; to: 0.96; duration: 1700; easing.type: Easing.InOutSine }
    NumberAnimation {
      target: scene; property: "pointer"
      to: (scene.clickIndex + 0.5) / scene.count
      duration: 900; easing.type: Easing.InOutSine
    }
    PauseAnimation { duration: 160 }
    // Clique: o ícone quica e a janela do app abre saindo do Dock.
    ScriptAction { script: if (!scene.demo) scene.bounce = 0 }
    SequentialAnimation {
      NumberAnimation { target: scene; property: "bounce"; to: scene.demo ? 1 : 0; duration: 230; easing.type: Easing.OutQuad }
      NumberAnimation { target: scene; property: "bounce"; to: 0; duration: 260; easing.type: Easing.InQuad }
    }
    NumberAnimation { target: scene; property: "windowOpen"; to: scene.demo ? 1 : 0; duration: 420; easing.type: Easing.OutCubic }
    PauseAnimation { duration: 400 }
    NumberAnimation { target: scene; property: "pointer"; to: 1.25; duration: 420; easing.type: Easing.InCubic }
    PauseAnimation { duration: 420 }
    NumberAnimation { target: scene; property: "windowOpen"; to: 0; duration: 380; easing.type: Easing.InOutQuad }
  }

  MiniDesktop {
    id: desk
    anchors.fill: parent
    u: scene.u * 1.9
    showDock: false

    // Janela que abre com o clique.
    MiniWindow {
      u: desk.u
      tint: scene.tints[scene.clickIndex]
      width: parent.width * 0.46
      height: parent.height * 0.5
      x: (parent.width - width) / 2
      y: Tokens.lerp(parent.height * 0.62, parent.height * 0.14, scene.windowOpen)
      scale: Tokens.lerp(0.2, 1, scene.windowOpen)
      opacity: scene.windowOpen
      lifted: true
    }
  }

  // Dock por cima da telinha (fica fora do recorte para os ícones ampliados
  // poderem passar do topo do vidro, como no Mac).
  Item {
    id: dock
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 8 * scene.u
    width: row.width + scene.base * 0.36
    height: scene.base + scene.base * 0.30

    Rectangle {
      anchors.fill: parent
      radius: Math.min(22 * scene.u, height * 0.36)
      antialiasing: true
      color: Tokens.glass(Theme.dark)
      border.width: 1
      border.color: Tokens.withAlpha(Theme.white, Theme.dark ? 0.12 : 0.55)
    }

    Row {
      id: row
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: scene.base * 0.15
      spacing: scene.spacing

      Repeater {
        model: scene.count
        Item {
          id: slot
          required property int index
          readonly property bool trash: index >= scene.tints.length
          readonly property real size: scene.sizeAt(index)
          width: size
          height: size
          anchors.bottom: parent.bottom

          IconTile {
            width: slot.size
            height: slot.size
            size: slot.size
            y: slot.index === scene.clickIndex ? -scene.bounce * scene.base * 0.55 : 0
            color: slot.trash ? Theme.gray : scene.tints[slot.index]
            glyph: slot.trash ? "trash" : scene.glyphs[slot.index]
            glyphScale: 0.56
          }

          // Bolinha de app aberto.
          Rectangle {
            visible: slot.index === 0 || slot.index === 3 || (slot.index === scene.clickIndex && scene.windowOpen > 0.5)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: Math.max(1, scene.base * 0.05)
            width: Math.max(3, scene.base * 0.08)
            height: width
            radius: width / 2
            color: Theme.label
            opacity: 0.75
          }
        }
      }
    }
  }

  // Ponteiro.
  Item {
    visible: scene.pointer >= 0 && scene.pointer <= 1.2
    readonly property real restWidth: scene.count * scene.base + (scene.count - 1) * scene.spacing
    x: dock.x + (dock.width - restWidth) / 2 + scene.pointer * restWidth - 4 * scene.u
    y: dock.y + dock.height * 0.42
    width: 26 * scene.u
    height: width

    Glyph {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: 0.8 * scene.u
      anchors.verticalCenterOffset: 1.4 * scene.u
      size: parent.width
      name: "pointer"
      color: Tokens.withAlpha(Theme.shadow, 0.35)
      strokeColor: Tokens.withAlpha(Theme.shadow, 0.35)
      weight: 2.4
    }
    // Ponteiro do Mac: preto com contorno branco, nos dois modos.
    Glyph {
      anchors.fill: parent
      size: parent.width
      name: "pointer"
      color: Tokens.label(false)
      strokeColor: Tokens.label(true)
      weight: 2.2
    }
  }
}
