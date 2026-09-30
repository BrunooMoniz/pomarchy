import QtQuick
import Quickshell
import "../shared/Tokens.js" as Tokens
import "../shared/Apps.js" as Apps
import "../shared"

// Dock: prévia viva no topo (acompanha tamanho e ampliação enquanto a pessoa
// arrasta), comportamento e a lista de apps fixos.
Page {
  id: page

  title: app.t("page.dock")
  intro: app.t("intro.dock")
  glyph: "dock"
  tint: Theme.blue

  readonly property real iconSize: app.live("dock.iconSize", 54)
  readonly property real magnifiedSize: app.live("dock.magnifiedSize", 82)
  readonly property bool magnification: app.get("dock.magnification", true) === true

  // Régua com "Pequeno" e "Grande" embaixo das pontas, como no Mac.
  component SizeSlider: Column {
    id: sizer

    property alias from: slider.from
    property alias to: slider.to
    property alias value: slider.value

    signal moved(real value)
    signal released(real value)

    width: 280
    spacing: 2

    MacSlider {
      id: slider
      width: parent.width
      stepSize: 1
      onMoved: function(value) { sizer.moved(value) }
      onReleased: function(value) { sizer.released(value) }
    }

    Item {
      width: parent.width
      height: small.implicitHeight

      Label {
        id: small
        x: 2
        text: app.t("dock.small")
        color: Theme.secondary
        font.pixelSize: Theme.caption
      }

      Label {
        anchors.right: parent.right
        anchors.rightMargin: 2
        text: app.t("dock.large")
        color: Theme.secondary
        font.pixelSize: Theme.caption
      }
    }
  }

  Group {
    Item {
      width: parent.width
      height: 188

      DockScene {
        anchors.fill: parent
        anchors.margins: 12
        demo: false
        zoom: 0.6
        iconSize: page.iconSize
        magnifiedSize: page.magnifiedSize
        magnification: page.magnification
        showTrash: app.get("dock.showTrash", true) === true
      }
    }
  }

  Group {
    FormRow {
      label: app.t("dock.size")
      minHeight: 58

      SizeSlider {
        from: 36
        to: 80
        value: page.iconSize
        onMoved: function(value) { app.setLive("dock.iconSize", Math.round(value)) }
        onReleased: function(value) { app.commitLive("dock.iconSize", Math.round(value)) }
      }
    }

    SwitchRow {
      label: app.t("dock.magnification")
      description: app.t("dock.magnificationHint")
      checked: page.magnification
      onToggled: app.set("dock.magnification", !checked)
    }

    FormRow {
      label: app.t("dock.magnifiedSize")
      minHeight: 58
      enabled: page.magnification

      SizeSlider {
        from: 48
        to: 128
        value: page.magnifiedSize
        onMoved: function(value) { app.setLive("dock.magnifiedSize", Math.round(value)) }
        onReleased: function(value) { app.commitLive("dock.magnifiedSize", Math.round(value)) }
      }
    }
  }

  Group {
    title: app.t("dock.behavior")

    SwitchRow {
      label: app.t("dock.autohide")
      description: app.t("dock.autohideHint")
      checked: app.get("dock.autohide", false) === true
      onToggled: app.set("dock.autohide", !checked)
    }

    SwitchRow {
      label: app.t("dock.showRunning")
      description: app.t("dock.showRunningHint")
      checked: app.get("dock.showRunning", true) === true
      onToggled: app.set("dock.showRunning", !checked)
    }

    SwitchRow {
      label: app.t("dock.showMinimized")
      description: app.t("dock.showMinimizedHint")
      checked: app.get("dock.showMinimized", true) === true
      onToggled: app.set("dock.showMinimized", !checked)
    }

    SwitchRow {
      label: app.t("dock.showTrash")
      checked: app.get("dock.showTrash", true) === true
      onToggled: app.set("dock.showTrash", !checked)
    }
  }

  Group {
    title: app.t("dock.favorites")
    footer: app.t("dock.favoritesHint")

    FormRow {
      visible: app.favorites.length === 0
      label: app.t("dock.favoritesEmpty")
      labelItem.color: Theme.secondary
      minHeight: 58
    }

    Repeater {
      model: app.favorites

      FormRow {
        id: favorite
        required property var modelData
        required property int index
        readonly property var entry: app.appEntry(modelData)
        label: app.appName(modelData, entry)
        minHeight: 48

        // Ícone do app no lugar do quadradinho.
        AppIconTile {
          parent: favorite
          x: Theme.rowPadX
          anchors.verticalCenter: parent.verticalCenter
          width: 30
          height: 30
          visible: favorite.modelData !== "pomar:launchpad"
          source: favorite.modelData === "pomar:launchpad" ? "" : Apps.iconSource(Quickshell, favorite.entry, favorite.modelData)
          textureSize: 60
          dark: Theme.dark
        }

        IconTile {
          parent: favorite
          x: Theme.rowPadX
          anchors.verticalCenter: parent.verticalCenter
          visible: favorite.modelData === "pomar:launchpad"
          size: 30
          color: Theme.gray
          glyph: "launchpad"
          glyphScale: 0.6
        }

        labelItem.leftPadding: 42

        PushButton {
          kind: "plain"
          glyph: "chevronLeft"
          text: ""
          enabled: favorite.index > 0
          implicitWidth: 30
          onClicked: app.moveFavorite(favorite.index, -1)
        }

        PushButton {
          kind: "plain"
          glyph: "chevronRight"
          text: ""
          enabled: favorite.index < app.favorites.length - 1
          implicitWidth: 30
          onClicked: app.moveFavorite(favorite.index, 1)
        }

        PushButton {
          text: app.t("dock.remove")
          onClicked: app.removeFavorite(favorite.index)
        }
      }
    }
  }
}
