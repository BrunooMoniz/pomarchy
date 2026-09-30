import QtQuick

// Mission Control: a ilustração do gesto, ligar/desligar e as formas de
// abrir (atalho, gesto, janelas só do app em uso).
Page {
  id: page

  title: app.t("page.mission")
  intro: app.t("intro.mission")
  glyph: "mission"
  tint: Theme.purple

  readonly property int fingers: app.get("gestures.missionFingers", 3)
  readonly property bool gestures: app.get("gestures.enabled", true) === true
  readonly property bool enabledMission: app.get("mission.enabled", true) === true

  Group {
    Item {
      width: parent.width
      height: 206

      GestureScene {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 440)
        height: width * 150 / 320
        gesture: "mission"
        fingers: page.fingers
        active: page.enabledMission
        opacity: page.enabledMission ? 1 : 0.45
      }
    }
  }

  Group {
    SwitchRow {
      label: app.t("mission.enable")
      description: app.t("mission.enableHint")
      glyph: "mission"
      glyphColor: Theme.purple
      checked: page.enabledMission
      onToggled: app.set("mission.enabled", !checked)
    }
  }

  Group {
    title: app.t("mission.howTo")
    enabled: page.enabledMission

    FormRow {
      label: app.t("mission.shortcut")

      KeyCombo {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        keys: ["⌘", "⌃", "↑"]
        size: 24
      }

      Item { width: 6; height: 1 }

      MacSwitch {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        checked: app.get("keys.missionControl", true) === true
        onToggled: app.set("keys.missionControl", !checked)
      }
    }

    FormRow {
      label: app.t("mission.gesture")
      description: page.gestures ? app.t("mission.gestureValue", app.fingersText(page.fingers)) : app.t("mission.gestureOff")

      PushButton {
        text: app.t("mission.adjust")
        onClicked: app.goTo("trackpad")
      }
    }

    FormRow {
      label: app.t("mission.appWindows")
      description: app.t("mission.appWindowsHint", app.fingersText(page.fingers))

      KeyCombo {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        keys: ["⌘", "⌃", "↓"]
        size: 24
      }
    }
  }
}
