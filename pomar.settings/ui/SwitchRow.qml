import QtQuick

// Linha com chave liga/desliga. A linha inteira responde ao clique: para quem
// não está acostumado, acertar a chavinha pequena é difícil.
FormRow {
  id: row

  property bool checked: false

  signal toggled()

  clickable: true
  onClicked: row.toggled()

  MacSwitch {
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    checked: row.checked
    interactive: false
  }
}
