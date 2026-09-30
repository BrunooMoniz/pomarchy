import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import "shared/Tokens.js" as Tokens

// Fundo do Launchpad: o papel de parede atual bem desfocado, com o véu do
// Pomarchy por cima, cobrindo as janelas como no Mac. Tudo vira uma camada só:
// o desfoque é calculado uma vez e a animação de abrir apenas mistura uma
// textura pronta. A imagem é decodificada em meia resolução (o desfoque
// apaga o detalhe) enquanto o Launchpad ainda está fechado.
Item {
  id: backdrop

  property bool dark: false
  property int decodeWidth: 960
  property int decodeHeight: 600
  property string path: ""
  property url source: ""

  readonly property string link: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
  readonly property bool video: Util.isVideoPath(path)
  readonly property bool ready: wallpaper.status === Image.Ready

  // Relê o link do papel de parede. Barato; o Launchpad chama ao abrir.
  function refresh() {
    if (resolver.running) resolver.pending = true
    else resolver.running = true
  }

  layer.enabled: true

  // Base enquanto a imagem carrega ou quando o papel de parede é um vídeo.
  Rectangle {
    anchors.fill: parent
    color: Color.background
  }

  Image {
    id: wallpaper
    anchors.fill: parent
    visible: false
    source: backdrop.source
    sourceSize.width: backdrop.decodeWidth
    sourceSize.height: backdrop.decodeHeight
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    smooth: true
  }

  MultiEffect {
    anchors.fill: parent
    source: wallpaper
    visible: backdrop.ready
    autoPaddingEnabled: false
    blurEnabled: true
    blur: 1.0
    blurMax: 128
    blurMultiplier: 1.0
    saturation: 0.18
  }

  Rectangle {
    anchors.fill: parent
    // Papel de parede claro pede véu um pouco mais forte para o texto branco.
    color: Tokens.scrim(backdrop.dark, backdrop.dark ? 1.0 : 1.85)
  }

  // Caminho real + data de modificação: a troca de tema pode regravar o
  // arquivo sem mudar o caminho, e a data serve de "versão" da imagem.
  Process {
    id: resolver

    property bool pending: false

    command: ["bash", "-c", "p=$(readlink -f -- \"$1\") || exit 0; printf '%s\\n%s\\n' \"$p\" \"$(stat -c %Y -- \"$p\" 2>/dev/null)\"",
      "pomar-launchpad", backdrop.link]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var next = String(lines[0] || "").trim()
        var stamp = String(lines[1] || "").trim()
        if (next !== backdrop.path) backdrop.path = next
        var url = next && !Util.isVideoPath(next) ? Util.fileUrl(next) + (stamp ? "?v=" + stamp : "") : ""
        if (String(url) !== String(backdrop.source)) backdrop.source = url
      }
    }
    onExited: {
      if (!resolver.pending) return
      resolver.pending = false
      resolver.running = true
    }
  }

  Component.onCompleted: refresh()
}
