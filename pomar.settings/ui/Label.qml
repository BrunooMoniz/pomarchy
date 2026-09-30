import QtQuick

// Texto dos Ajustes: fonte de interface do Pomarchy, cor de rótulo e sem
// interpretação de marcação (nome de app ou de arquivo aparece como é).
Text {
  color: Theme.label
  font.family: Theme.family
  font.pixelSize: Theme.body
  textFormat: Text.PlainText
  verticalAlignment: Text.AlignVCenter
}
