import QtQuick

// Trackpad: o coração didático. Cada gesto tem a própria ilustração em
// movimento, com o número de dedos escolhido, e o controle ao lado.
Page {
  id: page

  title: app.t("page.trackpad")
  intro: app.t("intro.trackpad")
  glyph: "trackpad"
  tint: Theme.orange

  readonly property bool gestures: app.get("gestures.enabled", true) === true
  readonly property int spaces: app.get("gestures.spacesFingers", 3)
  readonly property int mission: app.get("gestures.missionFingers", 3)
  readonly property bool pinch: app.get("gestures.launchpadPinch", true) === true

  readonly property var fingerOptions: [
    { value: 3, label: app.t("fingers.3short") },
    { value: 4, label: app.t("fingers.4short") }
  ]

  // Linha de gesto: ilustração à esquerda, nome, explicação e controle à direita.
  component GestureRow: Item {
    id: row

    property string gesture: "spaces"
    property int fingers: 3
    property string title: ""
    property string description: ""
    property string note: ""
    property bool live: true
    default property alias control: controlSlot.data

    width: parent ? parent.width : 0
    height: Math.max(scene.height, texts.implicitHeight) + 28
    opacity: row.live ? 1 : 0.5

    Rectangle {
      visible: row.y > 0
      x: Theme.rowPadX
      width: row.width - Theme.rowPadX * 2
      height: 1
      color: Theme.separator
    }

    GestureScene {
      id: scene
      x: 8
      anchors.verticalCenter: parent.verticalCenter
      width: 320
      height: 150
      gesture: row.gesture
      fingers: row.fingers
      active: row.live
    }

    Column {
      id: texts
      anchors.left: scene.right
      anchors.leftMargin: 14
      anchors.right: parent.right
      anchors.rightMargin: Theme.rowPadX + 4
      anchors.verticalCenter: parent.verticalCenter
      spacing: 5

      Label {
        width: parent.width
        text: row.title
        font.pixelSize: Theme.subtitle
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
      }

      Label {
        width: parent.width
        text: row.description
        color: Theme.secondary
        wrapMode: Text.WordWrap
        lineHeight: 1.1
      }

      Label {
        visible: row.note !== ""
        width: parent.width
        text: row.note
        color: Theme.secondary
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
      }

      Item { width: 1; height: controlSlot.children.length > 0 ? 4 : 0 }

      Row {
        id: controlSlot
        spacing: 8
      }
    }
  }

  Group {
    SwitchRow {
      label: app.t("trackpad.enable")
      description: app.t("trackpad.enableHint")
      glyph: "trackpad"
      glyphColor: Theme.orange
      checked: page.gestures
      onToggled: app.set("gestures.enabled", !checked)
    }
  }

  Group {
    title: app.t("trackpad.gestures")
    footer: app.t("trackpad.gesturesHint")
    enabled: page.gestures

    GestureRow {
      gesture: "spaces"
      fingers: page.spaces
      live: page.gestures
      title: app.t("g.spaces.title")
      description: app.t("g.spaces.desc", app.fingersText(page.spaces))

      Segmented {
        options: page.fingerOptions
        value: page.spaces
        onChosen: function(value) { app.set("gestures.spacesFingers", value) }
      }
    }

    GestureRow {
      gesture: "mission"
      fingers: page.mission
      live: page.gestures && app.get("mission.enabled", true) === true
      title: app.t("g.mission.title")
      description: app.t("g.mission.desc", app.fingersText(page.mission))

      Segmented {
        options: page.fingerOptions
        value: page.mission
        onChosen: function(value) { app.set("gestures.missionFingers", value) }
      }
    }

    GestureRow {
      gesture: "expose"
      fingers: page.mission
      live: page.gestures && app.get("mission.enabled", true) === true
      title: app.t("g.expose.title")
      description: app.t("g.expose.desc", app.fingersText(page.mission))
      note: app.t("g.expose.note")
    }

    GestureRow {
      gesture: "launchpad"
      live: page.gestures && page.pinch
      title: app.t("g.launchpad.title")
      description: app.t("g.launchpad.desc")

      Row {
        spacing: 10
        MacSwitch {
          anchors.verticalCenter: parent.verticalCenter
          checked: page.pinch
          onToggled: app.set("gestures.launchpadPinch", !checked)
        }
        Label {
          anchors.verticalCenter: parent.verticalCenter
          text: app.t("trackpad.pinch")
        }
      }
    }

    GestureRow {
      gesture: "launchpadClose"
      live: page.gestures && page.pinch
      title: app.t("g.launchpadClose.title")
      description: app.t("g.launchpadClose.desc")
      note: app.t("g.launchpadClose.note")
    }
  }
}
