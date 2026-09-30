import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "shared"
import "shared/Tokens.js" as Tokens

// Menu de contexto do Dock e o diálogo de confirmação, numa camada acima de
// tudo (pomar-menu, com desfoque atrás do vidro). A janela cobre a tela
// inteira só para fechar com clique fora; fica desmapeada quando fechada, e
// cada abertura mapeia de novo com teclado exclusivo (ESC, setas, Enter).
PanelWindow {
  id: win

  required property var dock

  // Linhas: { type: "header" | "item" | "separator", text, enabled, checked, dim }
  property var rows: []
  property real anchorX: 0
  property real anchorBottom: 0
  property int current: -1
  property bool menuShown: false
  // { icon, title, message, confirm, cancel } ou null
  property var dialog: null

  signal activated(int index)
  signal dismissed()
  signal confirmed()
  signal canceled()

  readonly property bool dark: dock.dark
  readonly property int inset: 5
  readonly property int textInset: 10
  readonly property int rowHeight: 22
  readonly property bool hasChecks: {
    for (var i = 0; i < rows.length; i++) if (rows[i].checked !== undefined) return true
    return false
  }
  readonly property int checkWidth: hasChecks ? 14 : 0

  visible: menuShown || dialog !== null
  screen: dock.dockScreen
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "pomar-menu"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  function selectable(index) {
    var row = rows[index]
    return !!row && row.type === "item" && row.enabled !== false
  }

  function step(delta) {
    if (!rows.length) return
    var index = current
    for (var n = 0; n < rows.length; n++) {
      index = index < 0 ? (delta > 0 ? 0 : rows.length - 1) : (index + delta + rows.length) % rows.length
      if (selectable(index)) { current = index; return }
    }
  }

  onVisibleChanged: {
    if (!visible) return
    current = -1
    appear.restart()
    Qt.callLater(function() { keys.forceActiveFocus() })
  }
  onDialogChanged: if (dialog) Qt.callLater(function() { keys.forceActiveFocus() })

  NumberAnimation {
    id: appear
    targets: [card, dialogCard]
    property: "opacity"
    from: 0
    to: 1
    duration: Tokens.motion.instant
    easing.type: Easing.OutCubic
  }

  // Escurece de leve só no diálogo; fica abaixo do limiar de desfoque da
  // camada, então só o vidro do cartão recebe desfoque.
  Rectangle {
    anchors.fill: parent
    color: Tokens.scrim(win.dark, 0.5)
    visible: win.dialog !== null
  }

  // Clique fora fecha (o diálogo cancela).
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: {
      if (win.dialog) win.canceled()
      else win.dismissed()
    }
  }

  Item {
    id: keys
    focus: true
    Keys.onPressed: function(event) {
      if (win.dialog) {
        if (event.key === Qt.Key_Escape) win.canceled()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) win.confirmed()
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Escape) win.dismissed()
      else if (event.key === Qt.Key_Down) win.step(1)
      else if (event.key === Qt.Key_Up) win.step(-1)
      else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && win.selectable(win.current))
        win.activated(win.current)
      event.accepted = true
    }
  }

  // Mede o texto mais largo para a largura do menu.
  Column {
    id: measure
    visible: false
    Repeater {
      model: win.rows
      Text {
        required property var modelData
        text: modelData.type === "separator" ? "" : String(modelData.text || "")
        font.family: win.dock.fontFamily
        font.pixelSize: 13
        font.weight: modelData.type === "header" ? Font.DemiBold : Font.Normal
      }
    }
  }

  // ------------------------------------------------------------ menu
  Item {
    id: card
    visible: win.menuShown && win.dialog === null
    width: Math.round(Tokens.clamp(measure.width + 2 * (win.inset + win.textInset) + win.checkWidth + 8, 190, 360))
    height: column.height + 2 * win.inset
    x: Math.round(Tokens.clamp(win.anchorX - width / 2, 8, Math.max(8, win.width - width - 8)))
    y: Math.round(Math.max(8, win.anchorBottom - height))

    Glass {
      anchors.fill: parent
      dark: win.dark
      radius: Tokens.radius.menu
      fill: Tokens.glassStrong(win.dark)
      shadowBlur: 28
      shadowOffsetY: 8
    }

    // Segura o clique dentro do menu (não fecha) e limpa a seleção ao sair.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    HoverHandler { onHoveredChanged: if (!hovered) win.current = -1 }

    Column {
      id: column
      x: win.inset
      y: win.inset
      width: card.width - 2 * win.inset

      Repeater {
        model: win.rows

        Item {
          id: row
          required property var modelData
          required property int index
          readonly property bool isSeparator: modelData.type === "separator"
          readonly property bool isHeader: modelData.type === "header"
          readonly property bool enabledRow: win.selectable(index)
          readonly property bool highlighted: win.current === index && enabledRow

          width: column.width
          height: isSeparator ? 11 : win.rowHeight

          Rectangle {
            anchors.fill: parent
            radius: Tokens.radius.menuItem
            color: Color.accent
            visible: row.highlighted
          }

          Rectangle {
            visible: row.isSeparator
            x: win.textInset - 1
            width: parent.width - 2 * (win.textInset - 1)
            height: 1
            anchors.verticalCenter: parent.verticalCenter
            color: Tokens.separator(win.dark)
          }

          // Marca da janela em foco.
          Shape {
            visible: row.modelData.checked === true
            x: win.textInset - 2
            width: 10
            height: 10
            anchors.verticalCenter: parent.verticalCenter
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              strokeColor: row.highlighted ? Color.menu.selectedText : Tokens.label(win.dark)
              strokeWidth: 1.6
              fillColor: "transparent"
              capStyle: ShapePath.RoundCap
              joinStyle: ShapePath.RoundJoin
              startX: 1; startY: 5.5
              PathLine { x: 4; y: 8.5 }
              PathLine { x: 9; y: 1.5 }
            }
          }

          Text {
            visible: !row.isSeparator
            x: win.textInset + win.checkWidth
            width: parent.width - x - win.textInset
            anchors.verticalCenter: parent.verticalCenter
            text: String(row.modelData.text || "")
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: win.dock.fontFamily
            font.pixelSize: 13
            font.weight: row.isHeader ? Font.DemiBold : Font.Normal
            color: row.highlighted ? Color.menu.selectedText
              : (row.isHeader ? Tokens.label(win.dark)
              : (!row.enabledRow || row.modelData.dim === true ? Tokens.secondaryLabel(win.dark) : Tokens.label(win.dark)))
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.enabledRow
            onEntered: win.current = row.index
            onClicked: win.activated(row.index)
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ diálogo
  Item {
    id: dialogCard
    visible: win.dialog !== null
    width: 300
    height: content.height + 40
    anchors.centerIn: parent

    Glass {
      anchors.fill: parent
      dark: win.dark
      radius: Tokens.radius.card
      fill: Tokens.glassStrong(win.dark)
      shadowBlur: 40
      shadowOffsetY: 14
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Column {
      id: content
      x: 20
      y: 22
      width: parent.width - 40
      spacing: 10

      Image {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 64
        height: 64
        source: win.dialog ? String(win.dialog.icon || "") : ""
        sourceSize.width: 128
        sourceSize.height: 128
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: win.dialog ? String(win.dialog.title || "") : ""
        font.family: win.dock.fontFamily
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: Tokens.label(win.dark)
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: win.dialog ? String(win.dialog.message || "") : ""
        font.family: win.dock.fontFamily
        font.pixelSize: 11
        color: Tokens.secondaryLabel(win.dark)
      }

      Item { width: 1; height: 4 }

      Row {
        width: parent.width
        spacing: 8

        Repeater {
          model: 2

          Rectangle {
            id: button
            required property int index
            readonly property bool primary: index === 1
            width: (content.width - 8) / 2
            height: 28
            radius: Tokens.radius.menuItem
            color: primary ? Color.accent : (buttonArea.pressed ? Tokens.pressed(win.dark) : Tokens.hover(win.dark))
            opacity: primary && buttonArea.pressed ? 0.85 : 1

            Text {
              anchors.centerIn: parent
              width: parent.width - 12
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: win.dialog ? String(button.primary ? win.dialog.confirm : win.dialog.cancel) : ""
              font.family: win.dock.fontFamily
              font.pixelSize: 13
              color: button.primary ? Color.menu.selectedText : Tokens.label(win.dark)
            }

            MouseArea {
              id: buttonArea
              anchors.fill: parent
              onClicked: button.primary ? win.confirmed() : win.canceled()
            }
          }
        }
      }
    }
  }
}
