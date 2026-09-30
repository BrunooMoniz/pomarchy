import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import "shared"
import "shared/Tokens.js" as Tokens

// Menu suspenso no estilo do macOS: vidro, itens de 13 px, destaque azul com
// texto branco, atalho alinhado à direita, submenus que abrem no hover e uma
// confirmação embutida para o que não tem volta (reiniciar, desligar).
//
// items: [{ label, shortcut?, action?, enabled?, separator?, submenu?: [...],
//           confirm?: { title, button } }]
PopupWindow {
  id: menu

  property var items: []
  property Item anchorItem: null
  property bool dark: true
  property bool isSubmenu: false
  property var confirming: null
  property int hoveredIndex: -1
  signal done()

  function openMenu() {
    menu.confirming = null
    menu.hoveredIndex = -1
    menu.visible = true
  }

  function closeMenu() {
    if (submenu.visible) submenu.visible = false
    menu.visible = false
    menu.confirming = null
  }

  function run(item) {
    if (!item || item.enabled === false || item.separator) return
    if (item.submenu) return
    if (item.confirm && !menu.confirming) { menu.confirming = item; return }
    menu.closeMenu()
    menu.done()
    if (typeof item.action === "function") item.action()
  }

  anchor.item: anchorItem
  anchor.edges: isSubmenu ? Edges.Right | Edges.Top : Edges.Bottom | Edges.Left
  anchor.gravity: Edges.Bottom | Edges.Right
  anchor.margins.top: isSubmenu ? -6 : 4
  implicitWidth: Math.max(230, column.implicitWidth + 12)
  implicitHeight: menu.confirming ? confirmBox.implicitHeight + 28 : column.implicitHeight + 12
  color: "transparent"
  visible: false

  HyprlandFocusGrab {
    windows: menu.isSubmenu ? [] : [menu, submenu]
    active: menu.visible && !menu.isSubmenu
    onCleared: { menu.closeMenu(); menu.done() }
  }

  Glass {
    anchors.fill: parent
    dark: menu.dark
    radius: Tokens.radius.menu
    fill: Tokens.glassStrong(menu.dark)
    shadowBlur: 24
    shadowOffsetY: 8
  }

  Column {
    id: column
    visible: !menu.confirming
    x: 6
    y: 6
    width: menu.width - 12

    Repeater {
      model: menu.items
      delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property bool isSeparator: modelData.separator === true
        readonly property bool enabled: modelData.enabled !== false
        readonly property bool highlighted: enabled && !isSeparator && (area.containsMouse || (submenu.visible && submenu.parentIndex === index))
        width: column.width
        implicitWidth: label.implicitWidth + shortcut.implicitWidth + 64
        height: isSeparator ? 11 : 22

        Rectangle {
          visible: row.isSeparator
          anchors.verticalCenter: parent.verticalCenter
          x: 8
          width: parent.width - 16
          height: 1
          color: Tokens.separator(menu.dark)
        }

        Rectangle {
          anchors.fill: parent
          radius: Tokens.radius.menuItem
          color: Color.accent
          visible: row.highlighted
        }

        Text {
          id: label
          visible: !row.isSeparator
          anchors.verticalCenter: parent.verticalCenter
          x: 12
          text: row.modelData.label || ""
          color: row.highlighted ? "white" : (row.enabled ? Tokens.label(menu.dark) : Tokens.secondaryLabel(menu.dark))
          font.pixelSize: 13
          font.family: Style.fontFamily
        }

        Text {
          id: shortcut
          visible: !row.isSeparator
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: 12
          text: row.modelData.submenu ? "›" : (row.modelData.shortcut || "")
          color: row.highlighted ? Qt.rgba(1, 1, 1, 0.85) : Tokens.secondaryLabel(menu.dark)
          font.pixelSize: row.modelData.submenu ? 16 : 13
          font.family: Style.fontFamily
        }

        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          enabled: !row.isSeparator
          onEntered: {
            menu.hoveredIndex = row.index
            if (row.modelData.submenu && row.enabled) {
              submenu.items = row.modelData.submenu
              submenu.parentIndex = row.index
              submenu.anchorItem = row
              submenu.openMenu()
            } else if (submenu.visible) {
              submenu.visible = false
            }
          }
          onClicked: menu.run(row.modelData)
        }
      }
    }
  }

  // Confirmação embutida: o menu vira uma pergunta com dois botões.
  Column {
    id: confirmBox
    visible: !!menu.confirming
    x: 14
    y: 14
    width: menu.width - 28
    spacing: 12

    Text {
      id: confirmTitle
      width: parent.width
      wrapMode: Text.WordWrap
      text: menu.confirming && menu.confirming.confirm ? menu.confirming.confirm.title : ""
      color: Tokens.label(menu.dark)
      font.pixelSize: 13
      font.weight: Font.DemiBold
      font.family: Style.fontFamily
    }

    Row {
      id: buttons
      anchors.right: parent.right
      spacing: 8
      height: 26

      Rectangle {
        width: cancelText.implicitWidth + 24
        height: 26
        radius: 7
        color: cancelArea.containsMouse ? Tokens.pressed(menu.dark) : Tokens.hover(menu.dark)
        Text {
          id: cancelText
          anchors.centerIn: parent
          text: menu.confirming && menu.confirming.confirm ? menu.confirming.confirm.cancel : ""
          color: Tokens.label(menu.dark)
          font.pixelSize: 13
          font.family: Style.fontFamily
        }
        MouseArea { id: cancelArea; anchors.fill: parent; hoverEnabled: true; onClicked: menu.confirming = null }
      }

      Rectangle {
        width: okText.implicitWidth + 24
        height: 26
        radius: 7
        color: okArea.containsMouse ? Qt.darker(Color.accent, 1.1) : Color.accent
        Text {
          id: okText
          anchors.centerIn: parent
          text: menu.confirming && menu.confirming.confirm ? menu.confirming.confirm.button : ""
          color: "white"
          font.pixelSize: 13
          font.weight: Font.DemiBold
          font.family: Style.fontFamily
        }
        MouseArea { id: okArea; anchors.fill: parent; hoverEnabled: true; onClicked: menu.run(menu.confirming) }
      }
    }
  }

  MacMenuSub {
    id: submenu
    dark: menu.dark
    onDone: { menu.closeMenu(); menu.done() }
  }
}
