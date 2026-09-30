pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Commons
import "shared"
import "shared/Tokens.js" as Tokens

// Menu de clique direito de um app, no estilo de menu do Mac: vidro denso,
// texto de 13 px, item em foco em azul (Color.accent) com texto branco e um
// filete separando os grupos. Abre onde o clique aconteceu e nunca sai da tela.
Item {
  id: menu

  property bool dark: false
  // [{ key, text, separator }]; `separator` põe um filete antes do item.
  property var entries: []
  property int current: -1
  property bool shown: false
  property real anchorX: 0
  property real anchorY: 0
  // O que fica atrás do menu (sem o próprio menu): vira o vidro desfocado.
  // O desfoque do Hyprland só pega o que está atrás da janela inteira, não o
  // conteúdo do próprio Launchpad.
  property Item blurSource: null

  signal chosen(string key)

  readonly property int inset: 5
  readonly property int rowHeight: 24
  readonly property int textPadding: 12
  readonly property int separatorHeight: 11

  function move(delta) {
    if (menu.entries.length === 0) return
    if (menu.current < 0) menu.current = delta > 0 ? 0 : menu.entries.length - 1
    else menu.current = (menu.current + delta + menu.entries.length) % menu.entries.length
  }

  function trigger() {
    if (menu.current >= 0 && menu.current < menu.entries.length) menu.chosen(menu.entries[menu.current].key)
  }

  function contentWidth() {
    var widest = 0
    for (var i = 0; i < menu.entries.length; i++) widest = Math.max(widest, metrics.advanceWidth(String(menu.entries[i].text || "")))
    return Math.ceil(widest)
  }

  function contentHeight() {
    var total = 0
    for (var i = 0; i < menu.entries.length; i++) total += menu.rowHeight + (menu.entries[i].separator ? menu.separatorHeight : 0)
    return total
  }

  width: Math.max(180, contentWidth() + textPadding * 2 + inset * 2 + 24)
  height: contentHeight() + inset * 2
  // Abre para baixo e para a direita do ponteiro; perto da borda, vira.
  x: Math.max(8, anchorX + width + 8 > (parent ? parent.width : 0) ? anchorX - width : anchorX)
  y: Math.max(8, anchorY + height + 8 > (parent ? parent.height : 0) ? anchorY - height : anchorY)
  opacity: shown ? 1 : 0
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: menu.shown ? Tokens.motion.instant : Tokens.motion.fast; easing.type: Easing.OutCubic } }

  FontMetrics {
    id: metrics
    font.family: Style.fontFamily
    font.pixelSize: Style.font.body
  }

  ShaderEffectSource {
    id: behind
    anchors.fill: parent
    sourceItem: menu.blurSource
    sourceRect: Qt.rect(menu.x, menu.y, menu.width, menu.height)
    live: menu.visible
    visible: false
  }

  Item {
    id: roundMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Rectangle {
      anchors.fill: parent
      radius: Tokens.radius.menu
      color: Tokens.label(false)
    }
  }

  MultiEffect {
    anchors.fill: parent
    source: behind
    visible: menu.blurSource !== null && menu.visible
    autoPaddingEnabled: false
    blurEnabled: true
    blur: 1.0
    blurMax: 48
    maskEnabled: true
    maskSource: roundMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1.0
  }

  Glass {
    anchors.fill: parent
    dark: menu.dark
    radius: Tokens.radius.menu
    fill: Tokens.glassStrong(menu.dark)
    shadowBlur: 28
    shadowOffsetY: 8
  }

  // Engole os cliques dentro do menu (fora dele, quem fecha é o Launchpad).
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
  }

  Column {
    x: menu.inset
    y: menu.inset
    width: menu.width - menu.inset * 2

    Repeater {
      model: menu.entries

      delegate: Column {
        id: row

        required property var modelData
        required property int index

        readonly property bool active: menu.current === row.index

        width: parent.width

        Item {
          visible: row.modelData.separator === true
          width: parent.width
          height: visible ? menu.separatorHeight : 0

          Rectangle {
            anchors.centerIn: parent
            width: parent.width - menu.textPadding * 2 + 4
            height: 1
            color: Tokens.separator(menu.dark)
          }
        }

        Item {
          width: parent.width
          height: menu.rowHeight

          Rectangle {
            anchors.fill: parent
            radius: Tokens.radius.menuItem
            color: Color.accent
            visible: row.active
          }

          Text {
            x: menu.textPadding
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - menu.textPadding * 2
            text: String(row.modelData.text || "")
            textFormat: Text.PlainText
            color: row.active ? Color.menu.selectedText : Tokens.label(menu.dark)
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: menu.current = row.index
            onExited: if (menu.current === row.index) menu.current = -1
            onClicked: menu.chosen(String(row.modelData.key))
          }
        }
      }
    }
  }
}
