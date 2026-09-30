import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Boas-vindas: tela quase cheia sobre o papel de parede desfocado, com um
// cartão de vidro e seis passos. Cada passo entra deslizando e aparecendo;
// as ilustrações são as mesmas do Trackpad, com o número de dedos escolhido.
FocusScope {
  id: view

  property var app
  readonly property int step: app.step
  readonly property int count: app.stepCount
  readonly property bool shown: app.opened

  // Tela pequena (notebook com escala alta): tudo encolhe um pouco.
  readonly property bool compact: card.height < 640

  readonly property int spacesFingers: app.get("gestures.spacesFingers", 3)
  readonly property int missionFingers: app.get("gestures.missionFingers", 3)

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      view.app.close()
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      view.app.next()
      event.accepted = true
    } else if (event.key === Qt.Key_Left) {
      view.app.back()
      event.accepted = true
    }
  }

  // ------------------------------------------------------------ fundo
  Rectangle {
    anchors.fill: parent
    color: Theme.windowFill
    opacity: view.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.slow; easing.type: Easing.OutCubic } }
  }

  Item {
    id: backdrop
    anchors.fill: parent
    opacity: view.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.slow; easing.type: Easing.OutCubic } }

    // Papel de parede reduzido e desfocado: a redução já espalha as cores e o
    // desfoque termina o serviço sem pesar.
    Image {
      id: paper
      anchors.fill: parent
      source: Theme.wallpaperUrl
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: 480
      asynchronous: true
      smooth: true
      visible: false
    }

    MultiEffect {
      anchors.fill: parent
      source: paper
      visible: paper.status === Image.Ready
      autoPaddingEnabled: false
      blurEnabled: true
      blur: 1.0
      blurMax: 48
      saturation: 0.15
    }

    Rectangle {
      anchors.fill: parent
      color: Tokens.scrim(Theme.dark, Theme.dark ? 0.9 : 0.5)
    }
  }

  // ------------------------------------------------------------ cartão
  Item {
    id: card
    width: Math.min(1120, parent.width - 96)
    height: Math.min(760, parent.height - 96)
    anchors.centerIn: parent
    opacity: view.shown ? 1 : 0
    scale: view.shown ? 1 : 0.97
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.slow; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: Tokens.motion.slow; easing.type: Easing.OutQuint } }

    // Sombra só do lado de fora: o vidro é translúcido e a sombra por baixo
    // apareceria como uma mancha no meio do cartão.
    Item {
      id: outerShadow
      anchors.fill: parent
      anchors.margins: -120
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskInverted: true
        maskSource: cardSilhouette
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      RectangularShadow {
        x: 120
        y: 120
        width: card.width
        height: card.height
        radius: 30
        blur: 60
        offset.y: 24
        spread: -12
        color: Tokens.withAlpha(Theme.shadow, Theme.dark ? 0.8 : 0.5)
      }
    }

    Item {
      id: cardSilhouette
      anchors.fill: outerShadow
      layer.enabled: true
      visible: false
      Rectangle {
        x: 120
        y: 120
        width: card.width
        height: card.height
        radius: 30
        color: "black"
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: 30
      antialiasing: true
      color: Tokens.glassStrong(Theme.dark)
      border.width: 1
      border.color: Theme.outline

      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 29
        color: "transparent"
        border.width: 1
        border.color: Theme.highlight
        opacity: Theme.dark ? 0.45 : 0.9
      }
    }

    PushButton {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 20
      kind: "plain"
      text: view.app.t("w.skip")
      visible: view.step < view.count - 1
      onClicked: view.app.close()
    }

    // Área dos passos.
    Item {
      id: stage
      anchors.fill: parent
      anchors.topMargin: view.compact ? 34 : 56
      anchors.bottomMargin: footer.height + (view.compact ? 22 : 34)
      anchors.leftMargin: 56
      anchors.rightMargin: 56
      clip: true

      Repeater {
        model: view.count

        Item {
          id: slide
          required property int index
          readonly property bool current: index === view.step
          width: stage.width
          height: stage.height
          x: (index - view.step) * 90
          opacity: current ? 1 : 0
          visible: opacity > 0.01
          Behavior on x { NumberAnimation { duration: Tokens.motion.slow + 60; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: Tokens.motion.base + 60; easing.type: Easing.OutCubic } }

          Loader {
            anchors.fill: parent
            active: slide.visible
            sourceComponent: [heroStep, dockStep, launchpadStep, missionStep, spacesStep, doneStep][slide.index]
          }
        }
      }
    }

    // Rodapé: Voltar, bolinhas de progresso e Continuar.
    Item {
      id: footer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: 40
      anchors.rightMargin: 40
      anchors.bottomMargin: view.compact ? 22 : 34
      height: 44

      PushButton {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        large: true
        minWidth: 130
        text: view.step === view.count - 1 ? view.app.t("w.openSettings") : view.app.t("w.back")
        visible: view.step > 0
        onClicked: view.step === view.count - 1 ? view.app.finish(true) : view.app.back()
      }

      Row {
        anchors.centerIn: parent
        spacing: 8

        Repeater {
          model: view.count
          Rectangle {
            required property int index
            readonly property bool current: index === view.step
            anchors.verticalCenter: parent.verticalCenter
            width: current ? 22 : 8
            height: 8
            radius: 4
            color: current ? Theme.accent : Theme.tertiary
            Behavior on width { NumberAnimation { duration: Tokens.motion.base; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Tokens.motion.base } }

            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: view.app.goToStep(parent.index)
            }
          }
        }
      }

      PushButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        large: true
        kind: "primary"
        minWidth: 150
        text: view.step === view.count - 1 ? view.app.t("w.start") : view.app.t("w.continue")
        onClicked: view.step === view.count - 1 ? view.app.finish(false) : view.app.next()
      }
    }
  }

  // ------------------------------------------------------------ passos
  // Molde de passo: título e texto embaixo, na altura que precisarem; a
  // ilustração ocupa o resto, então nada encavala em tela pequena.
  component StepLayout: Item {
    id: layout

    property string title: ""
    property string body: ""
    property real titleSize: Math.round(Theme.displayLarge * (view.compact ? 1.0 : 1.2))
    default property alias illustration: artSlot.data
    property alias extra: extraSlot.data

    Item {
      id: artSlot
      anchors.top: parent.top
      anchors.bottom: texts.top
      anchors.bottomMargin: view.compact ? 12 : 22
      width: parent.width
    }

    Column {
      id: texts
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width, 660)
      spacing: view.compact ? 8 : 12

      Label {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: layout.title
        font.pixelSize: layout.titleSize
        font.weight: Font.Bold
        wrapMode: Text.WordWrap
      }

      Label {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: layout.body
        color: Theme.secondary
        font.pixelSize: view.compact ? Theme.subtitle : Theme.heading
        wrapMode: Text.WordWrap
        lineHeight: 1.18
      }

      Item {
        id: extraSlot
        width: parent.width
        height: childrenRect.height
      }
    }
  }

  // Teclas com um rótulo "No teclado" ao lado.
  component KeysHint: Row {
    property var keys: []
    property var pressed: []
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    spacing: 12

    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: view.app.t("w.keys")
      color: Theme.secondary
      font.pixelSize: Theme.subtitle
    }

    KeyCombo {
      keys: parent.keys
      pressed: parent.pressed
      size: view.compact ? 26 : 30
    }
  }

  Component {
    id: heroStep

    Item {
      Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: view.compact ? 0 : -12
        spacing: view.compact ? 12 : 22

        Item {
          id: heroArt
          readonly property real tile: view.compact ? 92 : 132
          anchors.horizontalCenter: parent.horizontalCenter
          width: tile + 18
          height: tile + 18

          // Sombra de ícone do macOS: neutra, macia e caindo para baixo.
          RectangularShadow {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -4 * heroPulse.lift + 12
            width: heroArt.tile
            height: heroArt.tile
            radius: heroArt.tile * 0.24
            blur: 34
            spread: -6
            color: Qt.rgba(0, 0, 0, Theme.dark ? 0.5 : 0.24)
            scale: heroPulse.value
          }

          IconTile {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -4 * heroPulse.lift
            size: heroArt.tile
            color: Theme.green
            glyph: "leaf"
          }

          QtObject {
            id: heroPulse
            property real value: 1
            property real lift: 0
          }

          SequentialAnimation {
            running: view.visible && view.step === 0
            loops: Animation.Infinite
            ParallelAnimation {
              NumberAnimation { target: heroPulse; property: "value"; to: 1.08; duration: 1400; easing.type: Easing.InOutSine }
              NumberAnimation { target: heroPulse; property: "lift"; to: 1; duration: 1400; easing.type: Easing.InOutSine }
            }
            ParallelAnimation {
              NumberAnimation { target: heroPulse; property: "value"; to: 1; duration: 1400; easing.type: Easing.InOutSine }
              NumberAnimation { target: heroPulse; property: "lift"; to: 0; duration: 1400; easing.type: Easing.InOutSine }
            }
          }
        }

        Label {
          anchors.horizontalCenter: parent.horizontalCenter
          text: view.app.t("w.1.title")
          font.pixelSize: Math.round(Theme.displayLarge * (view.compact ? 1.25 : 1.6))
          font.weight: Font.Bold
        }

        Label {
          anchors.horizontalCenter: parent.horizontalCenter
          text: view.app.t("w.1.body")
          font.pixelSize: Math.round(Theme.displayLarge * (view.compact ? 0.66 : 0.8))
          font.weight: Font.Medium
          color: Theme.secondary
        }

        Label {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(560, view.width * 0.5)
          horizontalAlignment: Text.AlignHCenter
          text: view.app.t("w.1.more")
          font.pixelSize: view.compact ? Theme.subtitle : Theme.heading
          color: Theme.secondary
          wrapMode: Text.WordWrap
          lineHeight: 1.18
        }

        // Idioma logo na entrada: com o sistema em inglês, quem fala
        // português já troca aqui, sem procurar nos Ajustes.
        Segmented {
          anchors.horizontalCenter: parent.horizontalCenter
          value: view.app.lang
          options: [
            { value: "pt", label: view.app.t("geral.langPt") },
            { value: "en", label: view.app.t("geral.langEn") }
          ]
          onChosen: function(value) { view.app.set("language", value) }
        }
      }
    }
  }

  Component {
    id: dockStep

    StepLayout {
      title: view.app.t("w.2.title")
      body: view.app.t("w.2.body")

      DockScene {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.86, parent.height * 560 / 240, 720)
        height: width * 240 / 560
        active: view.step === 1
        demo: true
        iconSize: 54
        magnifiedSize: 82
        magnification: true
      }
    }
  }

  Component {
    id: launchpadStep

    StepLayout {
      title: view.app.t("w.3.title")
      body: view.app.t("w.3.body")

      GestureScene {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height * 320 / 150, 760)
        height: width * 150 / 320
        gesture: "launchpad"
        active: view.step === 2
      }

      extra: KeysHint {
        keys: ["⌘", "⌥", view.app.t("keys.space")]
      }
    }
  }

  Component {
    id: missionStep

    StepLayout {
      title: view.app.t("w.4.title")
      body: view.app.t("w.4.body", view.app.fingersText(view.missionFingers))

      GestureScene {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height * 320 / 150, 760)
        height: width * 150 / 320
        gesture: "mission"
        fingers: view.missionFingers
        active: view.step === 3
      }

      extra: KeysHint {
        keys: ["⌘", "⌃", "↑"]
      }
    }
  }

  Component {
    id: spacesStep

    StepLayout {
      id: spacesLayout
      title: view.app.t("w.5.title")
      body: view.app.t("w.5.body", view.app.fingersText(view.spacesFingers))

      GestureScene {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height * 320 / 150, 760)
        height: width * 150 / 320
        gesture: "spaces"
        fingers: view.spacesFingers
        active: view.step === 4
      }

      // A tecla Tab afunda de tempos em tempos, com o Alt segurado.
      extra: KeysHint {
        id: tabHint
        keys: ["⌥", view.app.t("keys.tab")]
        pressed: tabTap.down ? [0, 1] : [0]

        QtObject {
          id: tabTap
          property bool down: false
        }

        SequentialAnimation {
          running: view.step === 4
          loops: Animation.Infinite
          PauseAnimation { duration: 700 }
          PropertyAction { target: tabTap; property: "down"; value: true }
          PauseAnimation { duration: 180 }
          PropertyAction { target: tabTap; property: "down"; value: false }
          PauseAnimation { duration: 320 }
          PropertyAction { target: tabTap; property: "down"; value: true }
          PauseAnimation { duration: 180 }
          PropertyAction { target: tabTap; property: "down"; value: false }
        }
      }
    }
  }

  Component {
    id: doneStep

    Item {
      Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: view.compact ? 0 : -8
        spacing: view.compact ? 14 : 20

        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          width: view.compact ? 96 : 128
          height: width

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            antialiasing: true
            gradient: Gradient {
              GradientStop { position: 0; color: Qt.lighter(Theme.green, 1.12) }
              GradientStop { position: 1; color: Theme.green }
            }
            scale: doneBounce.value
          }

          Glyph {
            anchors.centerIn: parent
            size: parent.width * 0.56
            name: "check"
            weight: 2.6
            color: Theme.white
            scale: doneBounce.value
          }

          QtObject {
            id: doneBounce
            property real value: 0.6
          }

          NumberAnimation {
            running: view.step === 5
            target: doneBounce
            property: "value"
            from: 0.6
            to: 1
            duration: Tokens.motion.bounce
            easing.type: Easing.OutBack
            easing.overshoot: 1.6
          }
        }

        Label {
          anchors.horizontalCenter: parent.horizontalCenter
          text: view.app.t("w.6.title")
          font.pixelSize: Math.round(Theme.displayLarge * (view.compact ? 1.15 : 1.4))
          font.weight: Font.Bold
        }

        Label {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(560, view.width * 0.5)
          horizontalAlignment: Text.AlignHCenter
          text: view.app.t("w.6.body")
          font.pixelSize: view.compact ? Theme.subtitle : Theme.heading
          color: Theme.secondary
          wrapMode: Text.WordWrap
          lineHeight: 1.18
        }
      }
    }
  }
}
