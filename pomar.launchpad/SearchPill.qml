pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Commons
import "shared"
import "shared/Tokens.js" as Tokens

// Campo "Buscar" em pílula de vidro, no topo, como no Launchpad do Mac. Vazio,
// mostra lupa e texto centralizados; ao digitar, a lupa vai para a esquerda e
// o texto aparece ao lado. É um TextInput de verdade (acentos, teclas mortas e
// método de entrada funcionam); as teclas de navegação sobem para o Launchpad.
Item {
  id: pill

  property string placeholder: ""
  property string clearLabel: ""
  property alias text: input.text
  readonly property bool empty: input.text.length === 0
  readonly property bool hasFocus: input.activeFocus

  signal keyPressed(var event)

  function focusInput() {
    input.forceActiveFocus()
  }

  function clear() {
    input.text = ""
  }

  readonly property real padding: Math.round(height * 0.34)
  readonly property real glyph: Math.round(height * 0.46)
  readonly property real gap: Math.round(height * 0.2)
  readonly property real restX: Math.round((width - glyph - gap - placeholderText.implicitWidth) / 2)

  // Vidro claro sobre o fundo escurecido, nos dois temas (o Launchpad é
  // sempre "noturno", como no Mac); contorno externo leve para não pesar.
  Glass {
    anchors.fill: parent
    dark: true
    radius: height / 2
    fill: Tokens.pressed(true)
    highlight: Tokens.hairline(true)
    stroke: Tokens.outline(false)
    shadow: false
  }

  // Clicar no campo não fecha o Launchpad e devolve o foco à busca.
  MouseArea {
    anchors.fill: parent
    onPressed: pill.focusInput()
  }

  // Lupa desenhada (sem depender de fonte de ícones).
  Shape {
    id: magnifier
    x: pill.empty ? pill.restX : pill.padding
    anchors.verticalCenter: parent.verticalCenter
    width: pill.glyph
    height: pill.glyph
    preferredRendererType: Shape.CurveRenderer
    Behavior on x { NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic } }

    ShapePath {
      strokeColor: Tokens.secondaryLabel(true)
      strokeWidth: Math.max(1.4, pill.glyph * 0.12)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: pill.glyph * 0.42
        centerY: pill.glyph * 0.42
        radiusX: pill.glyph * 0.33
        radiusY: pill.glyph * 0.33
        startAngle: 0
        sweepAngle: 360
      }
    }

    ShapePath {
      strokeColor: Tokens.secondaryLabel(true)
      strokeWidth: Math.max(1.6, pill.glyph * 0.14)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      startX: pill.glyph * 0.68
      startY: pill.glyph * 0.68
      PathLine { x: pill.glyph * 0.94; y: pill.glyph * 0.94 }
    }
  }

  Text {
    id: placeholderText
    x: magnifier.x + pill.glyph + pill.gap
    anchors.verticalCenter: parent.verticalCenter
    text: pill.placeholder
    textFormat: Text.PlainText
    color: Tokens.secondaryLabel(true)
    font.family: Style.fontFamily
    font.pixelSize: Style.font.body
    opacity: pill.empty ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.instant } }
  }

  TextInput {
    id: input
    x: pill.padding + pill.glyph + pill.gap
    anchors.verticalCenter: parent.verticalCenter
    width: pill.width - x - (clearButton.width + pill.padding * 0.5)
    color: Tokens.label(true)
    selectionColor: Color.accent
    selectedTextColor: Color.menu.selectedText
    font.family: Style.fontFamily
    font.pixelSize: Style.font.body
    clip: true
    focus: true
    selectByMouse: true
    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) { pill.keyPressed(event) }

    // Cursor próprio: some com o campo vazio (a dica fica centralizada) e
    // pisca no ritmo do sistema.
    cursorDelegate: Rectangle {
      id: caret
      width: 1.5
      color: Tokens.label(true)
      visible: input.activeFocus && !pill.empty
      opacity: 1

      Connections {
        target: input
        function onCursorPositionChanged() {
          caret.opacity = 1
          blink.restart()
        }
      }

      Timer {
        id: blink
        interval: Math.max(250, Qt.styleHints.cursorFlashTime / 2)
        repeat: true
        running: caret.visible
        onTriggered: caret.opacity = caret.opacity > 0 ? 0 : 1
        onRunningChanged: caret.opacity = 1
      }
    }
  }

  // Botão de limpar (círculo com um x), só com texto digitado.
  Item {
    id: clearButton
    width: pill.height
    height: pill.height
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    opacity: pill.empty ? 0 : 1
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.instant } }
    Accessible.role: Accessible.Button
    Accessible.name: pill.clearLabel

    Shape {
      anchors.centerIn: parent
      width: pill.glyph
      height: pill.glyph
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeColor: "transparent"
        fillColor: Tokens.secondaryLabel(true)
        PathAngleArc {
          centerX: pill.glyph / 2
          centerY: pill.glyph / 2
          radiusX: pill.glyph / 2
          radiusY: pill.glyph / 2
          startAngle: 0
          sweepAngle: 360
        }
      }

      ShapePath {
        strokeColor: Tokens.shadow(true)
        strokeWidth: Math.max(1.3, pill.glyph * 0.11)
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        startX: pill.glyph * 0.34
        startY: pill.glyph * 0.34
        PathLine { x: pill.glyph * 0.66; y: pill.glyph * 0.66 }
        PathMove { x: pill.glyph * 0.66; y: pill.glyph * 0.34 }
        PathLine { x: pill.glyph * 0.34; y: pill.glyph * 0.66 }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        pill.clear()
        pill.focusInput()
      }
    }
  }
}
