import QtQuick
import Quickshell
import qs.Commons
import "shared"
import "shared/Tokens.js" as Tokens

// Submenu de um MacMenu (um nível só: o QML não deixa um componente conter a
// si mesmo, e o macOS raramente passa disso na barra de menus).
PopupWindow {
  id: sub

  property var items: []
  property Item anchorItem: null
  property int parentIndex: -1
  property bool dark: true
  signal done()

  function openMenu() { sub.visible = true }

  anchor.item: anchorItem
  anchor.edges: Edges.Right | Edges.Top
  anchor.gravity: Edges.Bottom | Edges.Right
  anchor.margins.top: -6
  anchor.margins.left: 4
  implicitWidth: Math.max(180, column.implicitWidth + 12)
  implicitHeight: column.implicitHeight + 12
  color: "transparent"
  visible: false

  Glass {
    anchors.fill: parent
    dark: sub.dark
    radius: Tokens.radius.menu
    fill: Tokens.glassStrong(sub.dark)
    shadowBlur: 24
    shadowOffsetY: 8
  }

  Column {
    id: column
    x: 6
    y: 6
    width: sub.width - 12

    Repeater {
      model: sub.items
      delegate: Item {
        id: row
        required property var modelData
        readonly property bool enabled: modelData.enabled !== false
        readonly property bool isSeparator: modelData.separator === true
        width: column.width
        implicitWidth: label.implicitWidth + 60
        height: isSeparator ? 11 : 22

        Rectangle {
          visible: row.isSeparator
          anchors.verticalCenter: parent.verticalCenter
          x: 8
          width: parent.width - 16
          height: 1
          color: Tokens.separator(sub.dark)
        }
        Rectangle {
          anchors.fill: parent
          radius: Tokens.radius.menuItem
          color: Color.accent
          visible: area.containsMouse && row.enabled && !row.isSeparator
        }
        Text {
          id: label
          visible: !row.isSeparator
          anchors.verticalCenter: parent.verticalCenter
          x: 12
          text: (row.modelData.checked ? "✓  " : "") + (row.modelData.label || "")
          color: area.containsMouse && row.enabled ? "white" : (row.enabled ? Tokens.label(sub.dark) : Tokens.secondaryLabel(sub.dark))
          font.pixelSize: 13
          font.family: Style.fontFamily
        }
        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          enabled: !row.isSeparator
          onClicked: {
            if (!row.enabled) return
            sub.visible = false
            sub.done()
            if (typeof row.modelData.action === "function") row.modelData.action()
          }
        }
      }
    }
  }
}
