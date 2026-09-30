import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Barra de menus: prévia desenhada da barra no estilo Mac, a troca de barra
// (feita pelo comando `pomar`) e o menu do sistema.
Page {
  id: page

  title: app.t("page.barra")
  intro: app.t("intro.barra")
  glyph: "menubar"
  tint: Theme.teal

  Group {
    Item {
      width: parent.width
      height: 132

      Item {
        id: preview
        anchors.fill: parent
        anchors.margins: 12
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: previewMask
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
          source: Theme.wallpaperUrl
          fillMode: Image.PreserveAspectCrop
          sourceSize.width: 720
          asynchronous: true
          smooth: true
        }

        // A barra, em tamanho real, com o menu à esquerda e o relógio à direita.
        Rectangle {
          id: bar
          width: parent.width
          height: 30
          color: Tokens.glassStrong(Theme.dark)
          opacity: app.barMac ? 1 : 0.35
          Behavior on opacity { NumberAnimation { duration: Tokens.motion.base } }

          Row {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 16

            Glyph {
              anchors.verticalCenter: parent.verticalCenter
              size: 15
              name: "leaf"
              color: Theme.label
              opacity: app.get("menubar.enabled", true) === true ? 1 : 0.25
            }

            Label {
              anchors.verticalCenter: parent.verticalCenter
              text: app.t("barra.preview.app")
              font.weight: Font.Bold
              opacity: app.get("menubar.enabled", true) === true ? 1 : 0.25
            }

            Repeater {
              model: [app.t("barra.preview.file"), app.t("barra.preview.edit"), app.t("barra.preview.view")]
              Label {
                required property string modelData
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                opacity: app.get("menubar.enabled", true) === true ? 1 : 0.25
              }
            }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            Repeater {
              model: [0, 1]
              Rectangle {
                required property int modelData
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 10
                radius: 3
                color: Theme.label
                opacity: 0.55
              }
            }

            Label {
              anchors.verticalCenter: parent.verticalCenter
              text: new Date().toLocaleString(Qt.locale(app.lang === "pt" ? "pt_BR" : "en_US"), app.lang === "pt" ? "ddd d MMM  HH:mm" : "ddd MMM d  h:mm AP")
              font.weight: Font.Medium
            }
          }
        }

        // Janela de exemplo, para a barra ter contexto.
        MiniWindow {
          u: 2.2
          x: parent.width * 0.18
          y: 46
          width: parent.width * 0.42
          height: 110
          tint: Theme.blue
        }
      }

      Item {
        id: previewMask
        anchors.fill: preview
        layer.enabled: true
        visible: false
        Rectangle {
          anchors.fill: parent
          radius: 9
          color: "black"
        }
      }

      Rectangle {
        anchors.fill: preview
        radius: 9
        color: "transparent"
        border.width: 1
        border.color: Theme.outline
      }
    }
  }

  Group {
    footer: app.cliAvailable ? "" : app.t("barra.cliMissing")

    SwitchRow {
      label: app.t("barra.macStyle")
      description: !app.cliAvailable ? app.t("barra.macStyleHint")
        : (app.barPending ? app.t("barra.working")
        : (app.barMac ? app.t("barra.macStyleOnHint") : app.t("barra.macStyleHint")))
      glyph: "menubar"
      glyphColor: Theme.teal
      enabled: app.cliAvailable && !app.barPending
      checked: app.barMac
      onToggled: app.toggleBarMac()
    }
  }

  Group {
    SwitchRow {
      label: app.t("barra.systemMenu")
      description: app.t("barra.systemMenuHint")
      glyph: "leaf"
      glyphColor: Theme.green
      checked: app.get("menubar.enabled", true) === true
      onToggled: app.set("menubar.enabled", !checked)
    }
  }
}
