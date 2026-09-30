import QtQuick

// Teclado: tabela de atalhos com as teclas desenhadas. Os do Pomarchy podem ser
// desligados um a um; os do sistema só aparecem para consulta.
Page {
  id: page

  title: app.t("page.teclado")
  intro: app.t("intro.teclado")
  glyph: "keyboard"
  tint: Theme.gray

  // Linha da tabela: teclas numa coluna fixa (para os nomes alinharem),
  // o que o atalho faz e, se for do Pomarchy, a chave.
  component ShortcutRow: Item {
    id: row

    property var combos: []
    property string label: ""
    property string note: ""
    property string settingKey: ""

    width: parent ? parent.width : 0
    height: Math.max(48, texts.implicitHeight + 20)

    Rectangle {
      visible: row.y > 0
      x: Theme.rowPadX
      width: row.width - Theme.rowPadX * 2
      height: 1
      color: Theme.separator
    }

    Row {
      id: keysColumn
      x: Theme.rowPadX
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      Repeater {
        model: row.combos
        Row {
          required property var modelData
          required property int index
          spacing: 8

          Label {
            visible: index > 0
            anchors.verticalCenter: parent.verticalCenter
            text: app.t("keys.or")
            color: Theme.secondary
            font.pixelSize: Theme.small
          }

          KeyCombo {
            keys: modelData
            size: 26
          }
        }
      }
    }

    Column {
      id: texts
      x: Theme.rowPadX + 196
      width: row.width - x - Theme.rowPadX - (toggle.visible ? toggle.width + 16 : 0)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2

      Label {
        width: parent.width
        text: row.label
        wrapMode: Text.WordWrap
      }

      Label {
        visible: row.note !== ""
        width: parent.width
        text: row.note
        color: Theme.secondary
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
      }
    }

    MacSwitch {
      id: toggle
      visible: row.settingKey !== ""
      anchors.right: parent.right
      anchors.rightMargin: Theme.rowPadX
      anchors.verticalCenter: parent.verticalCenter
      checked: row.settingKey !== "" && app.get(row.settingKey, true) === true
      onToggled: app.set(row.settingKey, !checked)
    }
  }

  Group {
    title: app.t("keys.pomar")
    footer: app.t("keys.pomarHint")

    ShortcutRow {
      combos: [["⌥", app.t("keys.tab")]]
      label: app.t("keys.cmdTab")
      settingKey: "keys.cmdTab"
    }
    ShortcutRow {
      combos: [["⌘", "⌥", app.t("keys.space")]]
      label: app.t("keys.launchpad")
      settingKey: "keys.launchpad"
    }
    ShortcutRow {
      combos: [["⌘", "⌃", "↑"]]
      label: app.t("keys.mission")
      settingKey: "keys.missionControl"
    }
    ShortcutRow {
      combos: [["⌘", "⌃", "↓"]]
      label: app.t("keys.expose")
      note: app.t("keys.exposeNote")
    }
    ShortcutRow {
      combos: [["⌘", "M"]]
      label: app.t("keys.minimize")
      settingKey: "keys.minimize"
    }
    ShortcutRow {
      combos: [["⌘", "⌥", "D"]]
      label: app.t("keys.dock")
      settingKey: "keys.dockToggle"
    }
  }

  Group {
    title: app.t("keys.system")
    footer: app.t("keys.systemHint")

    ShortcutRow {
      combos: [["⌘", app.t("keys.space")]]
      label: app.t("keys.search")
    }
    ShortcutRow {
      combos: [["⌘", "W"]]
      label: app.t("keys.closeWindow")
    }
    ShortcutRow {
      combos: [["⌘", "C"], ["⌘", "V"]]
      label: app.t("keys.copyPaste")
    }
    ShortcutRow {
      combos: [["⌘", "1…9"]]
      label: app.t("keys.desktops")
    }
  }

  Group {
    title: app.t("keys.legend")
    footer: app.t("keys.legendHint")

    ShortcutRow {
      combos: [["⌘"]]
      label: app.t("keys.cmdName")
    }
    ShortcutRow {
      combos: [["⌥"]]
      label: app.t("keys.optName")
    }
    ShortcutRow {
      combos: [["⌃"]]
      label: app.t("keys.ctrlName")
    }
    ShortcutRow {
      combos: [["⇧"]]
      label: app.t("keys.shiftName")
    }
  }
}
