import QtQuick

// Combinação de teclas lado a lado, como aparece nos menus do Mac: ⌘ ⌥ Espaço.
Row {
  id: root

  property var keys: []
  property real size: 26
  // Índices das teclas que estão "apertadas" agora (animação das boas-vindas).
  property var pressed: []

  spacing: Math.round(size * 0.18)

  Repeater {
    model: root.keys
    KeyCap {
      required property var modelData
      required property int index
      text: modelData
      size: root.size
      down: root.pressed.indexOf(index) !== -1
    }
  }
}
