import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Geral: aparência (claro ou escuro), manter o Pomarchy em qualquer tema,
// idioma, papel de parede e a apresentação de novo.
Page {
  id: page

  title: app.t("page.geral")
  intro: app.t("intro.geral")
  glyph: "gear"
  tint: Theme.gray

  // Miniatura de aparência: uma telinha no modo claro ou escuro, desenhada
  // com as cores do Tokens para aquele modo (vale mesmo com o outro ativo).
  component AppearanceChoice: Item {
    id: choice

    property bool darkMode: false
    property string label: ""
    property bool selected: false
    property string wallpaper: ""

    signal clicked()

    width: 150
    height: 128

    Rectangle {
      id: ring
      x: -4
      y: -4
      width: shot.width + 8
      height: shot.height + 8
      radius: 13
      color: "transparent"
      border.width: 3
      border.color: choice.selected ? Theme.accent : "transparent"
      antialiasing: true
    }

    Item {
      id: shot
      width: 150
      height: 94
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: shotMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: Tokens.mix(Theme.blue, Theme.purple, 0.3) }
          GradientStop { position: 1; color: Tokens.mix(Theme.purple, Theme.orange, 0.4) }
        }
      }

      Image {
        anchors.fill: parent
        source: choice.wallpaper
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 320
        asynchronous: true
        smooth: true
      }

      // Barra de menus da miniatura.
      Rectangle {
        width: parent.width
        height: 9
        color: Tokens.glassStrong(choice.darkMode)
      }

      // Janela da miniatura.
      Rectangle {
        x: 22
        y: 20
        width: 92
        height: 58
        radius: 6
        antialiasing: true
        color: Tokens.glassStrong(choice.darkMode)
        border.width: 1
        border.color: Tokens.outline(choice.darkMode)

        Row {
          x: 6
          y: 5
          spacing: 3
          Repeater {
            model: [Theme.red, Theme.orange, Theme.green]
            Rectangle {
              required property color modelData
              width: 5
              height: 5
              radius: 2.5
              color: modelData
            }
          }
        }

        Column {
          x: 8
          y: 18
          spacing: 5
          Repeater {
            model: [58, 44, 66, 36]
            Rectangle {
              required property real modelData
              width: modelData
              height: 4
              radius: 2
              color: Tokens.secondaryLabel(choice.darkMode)
              opacity: 0.55
            }
          }
        }

        Rectangle {
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 7
          width: 22
          height: 8
          radius: 4
          color: Theme.accent
        }
      }

      // Dock da miniatura.
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        width: 64
        height: 11
        radius: 4
        color: Tokens.glass(choice.darkMode)
      }
    }

    Item {
      id: shotMask
      width: shot.width
      height: shot.height
      layer.enabled: true
      visible: false
      Rectangle {
        anchors.fill: parent
        radius: 9
        color: "black"
      }
    }

    Rectangle {
      width: shot.width
      height: shot.height
      radius: 9
      color: "transparent"
      border.width: 1
      border.color: Theme.outline
      antialiasing: true
    }

    Label {
      anchors.horizontalCenter: shot.horizontalCenter
      anchors.top: shot.bottom
      anchors.topMargin: 11
      text: choice.label
      font.weight: choice.selected ? Font.DemiBold : Font.Normal
      color: choice.selected ? Theme.label : Theme.secondary
    }

    MouseArea {
      anchors.fill: parent
      anchors.margins: -4
      cursorShape: Qt.PointingHandCursor
      onClicked: choice.clicked()
    }
  }

  Group {
    title: app.t("geral.appearance")
    footer: app.t("geral.appearanceHint")

    Item {
      width: parent.width
      height: 168

      Row {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 4
        spacing: 36

        AppearanceChoice {
          label: app.t("geral.light")
          darkMode: false
          selected: app.appearance === "light"
          wallpaper: app.themeWallpaper("pomarchy")
          onClicked: app.chooseAppearance(false)
        }

        AppearanceChoice {
          label: app.t("geral.dark")
          darkMode: true
          selected: app.appearance === "dark"
          wallpaper: app.themeWallpaper("pomarchy-escuro")
          onClicked: app.chooseAppearance(true)
        }
      }
    }
  }

  Group {
    SwitchRow {
      label: app.t("geral.alwaysOn")
      description: app.t("geral.alwaysOnHint")
      checked: app.get("alwaysOn", false) === true
      onToggled: app.set("alwaysOn", !checked)
    }
    SwitchRow {
      label: app.t("geral.windowControls")
      description: app.t("geral.windowControlsHint")
      checked: app.get("windowControls.enabled", true) === true
      onToggled: app.set("windowControls.enabled", !checked)
    }
  }

  Group {
    footer: app.t("geral.languageHint")

    FormRow {
      label: app.t("geral.language")

      Segmented {
        value: app.get("language", "auto")
        options: [
          { value: "auto", label: app.t("geral.langAuto") },
          { value: "pt", label: app.t("geral.langPt") },
          { value: "en", label: app.t("geral.langEn") }
        ]
        onChosen: function(value) { app.set("language", value) }
      }
    }
  }

  Group {
    title: app.t("geral.wallpaper")
    footer: app.wallpaperCount > 0 ? app.t("geral.wallpaperHint") : app.t("geral.wallpaperEmpty")

    Item {
      width: parent.width
      height: app.wallpaperCount > 0 ? grid.implicitHeight + 32 : 0
      visible: app.wallpaperCount > 0

      Flow {
        id: grid
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 14

        Repeater {
          model: app.wallpapers

          Item {
            id: thumb
            required property string filePath
            required property string fileName
            readonly property bool selected: app.isCurrentWallpaper(fileName)
            width: 128
            height: 80

            Rectangle {
              x: -4
              y: -4
              width: parent.width + 8
              height: parent.height + 8
              radius: 12
              color: "transparent"
              border.width: 3
              border.color: thumb.selected ? Theme.accent : "transparent"
              antialiasing: true
            }

            Item {
              id: picture
              anchors.fill: parent
              layer.enabled: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: thumbMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
              }

              Rectangle {
                anchors.fill: parent
                color: Theme.track
              }

              Image {
                anchors.fill: parent
                source: app.fileUrl(thumb.filePath)
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 256
                asynchronous: true
                smooth: true
              }
            }

            Item {
              id: thumbMask
              anchors.fill: parent
              layer.enabled: true
              visible: false
              Rectangle {
                anchors.fill: parent
                radius: 8
                color: "black"
              }
            }

            Rectangle {
              anchors.fill: parent
              radius: 8
              color: "transparent"
              border.width: 1
              border.color: Theme.outline
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: app.chooseWallpaper(thumb.filePath)
            }
          }
        }
      }
    }
  }

  Group {
    FormRow {
      label: app.t("geral.welcome")
      description: app.t("geral.welcomeHint")
      glyph: "sparkle"
      glyphColor: Theme.purple

      PushButton {
        text: app.t("geral.welcomeButton")
        onClicked: app.openWelcome()
      }
    }
  }
}
