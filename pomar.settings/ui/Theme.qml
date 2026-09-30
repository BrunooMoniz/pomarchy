pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../shared/Tokens.js" as Tokens

// Cores, medidas e tipografia dos Ajustes, num lugar só.
// Texto, vidro e filetes vêm do Tokens; destaque e fundo, do Color do Omarchy.
// O Color não expõe o resto da paleta do tema (vermelho, verde, roxo...), que
// os quadradinhos da barra lateral e as ilustrações precisam: por isso este
// objeto lê o colors.toml do tema atual, o mesmo arquivo que o Color lê.
QtObject {
  id: theme

  readonly property bool dark: Tokens.isDark(Color.background)
  readonly property string family: Style.fontFamily

  // ---------------------------------------------------------------- texto
  readonly property color label: Tokens.label(dark)
  readonly property color secondary: Tokens.secondaryLabel(dark)
  readonly property color tertiary: Tokens.withAlpha(Tokens.secondaryLabel(dark), 0.36)
  readonly property color separator: Tokens.separator(dark)
  readonly property color hover: Tokens.hover(dark)
  readonly property color pressed: Tokens.pressed(dark)
  readonly property color accent: Color.accent
  // Texto sobre o destaque: claro ou escuro conforme o destaque do tema.
  readonly property color accentText: Tokens.luminance(Color.accent) > 0.62 ? Tokens.label(false) : Tokens.label(true)
  // Quase branco do Tokens: botão das chaves, glifos sobre os quadradinhos.
  readonly property color white: Tokens.label(true)

  // ---------------------------------------------------------------- superfícies
  readonly property color windowFill: Tokens.withAlpha(Color.background, 0.97)
  // Vidro denso, como a barra lateral do Mac: o desfoque aparece, a leitura não sofre.
  // Barra lateral translúcida: o desfoque do Hyprland atrás dá a "vibrância"
  // dos Ajustes do Sistema.
  readonly property color sidebarFill: Tokens.glass(dark)
  readonly property color outline: Tokens.outline(dark)
  readonly property color highlight: Tokens.hairline(dark)
  readonly property color shadow: Tokens.shadow(dark)
  // Cartões "inset grouped": o tom mais claro que o tema define.
  readonly property color card: pick("lighter_background", dark ? Tokens.mix(Color.background, Color.foreground, 0.07) : Tokens.mix(Color.background, white, 0.8))
  readonly property color cardStroke: dark ? Tokens.withAlpha(white, 0.06) : Tokens.withAlpha(Color.foreground, 0.07)
  // Trilho de chave, controle e régua desligados.
  readonly property color track: dark ? Tokens.withAlpha(white, 0.16) : Tokens.withAlpha(Color.foreground, 0.10)
  // Botão comum (sem destaque).
  readonly property color control: dark ? Tokens.withAlpha(white, 0.14) : card
  readonly property color controlStroke: dark ? Tokens.withAlpha(white, 0.05) : Tokens.withAlpha(Color.foreground, 0.12)

  // ---------------------------------------------------------------- paleta do tema
  property var values: ({})

  function pick(key, fallback) {
    var value = theme.values[key]
    return value ? value : fallback
  }

  // Nos temas claros do Pomarchy as "bright_*" são as cores de sistema do Mac e as
  // normais são tons escuros para o terminal; nos escuros as normais já são as
  // de sistema.
  function system(name, fallback) {
    if (!theme.dark && theme.values["bright_" + name]) return theme.values["bright_" + name]
    return pick(name, fallback)
  }

  readonly property color red: system("red", Color.urgent)
  readonly property color orange: system("orange", Color.urgent)
  readonly property color yellow: system("yellow", Color.accent)
  readonly property color green: system("green", Color.accent)
  readonly property color cyan: system("cyan", Color.accent)
  readonly property color purple: system("magenta", Color.accent)
  readonly property color blue: Color.accent
  readonly property color gray: Color.muted
  // Azul-petróleo legível com glifo branco: o ciano do tema escuro é claro demais.
  readonly property color teal: dark ? Qt.darker(cyan, 1.45) : cyan

  function parse(text) {
    var out = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (match) out[match[1]] = match[2]
    }
    return out
  }

  function reload() { colorsFile.reload() }

  property FileView colorsFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: theme.values = theme.parse(text())
    onFileChanged: reload()
  }

  // Papel de parede atual (caminho real; a raiz dos Ajustes resolve o link
  // ~/.local/state/omarchy/current/background). As ilustrações usam a foto
  // da própria pessoa.
  property string wallpaperPath: ""
  readonly property string wallpaperUrl: wallpaperPath ? Util.fileUrl(wallpaperPath) : ""

  // ---------------------------------------------------------------- medidas
  readonly property int windowRadius: Tokens.radius.window
  readonly property int groupRadius: Tokens.radius.menu
  readonly property int itemRadius: Tokens.radius.menuItem
  readonly property int sidebarWidth: 240
  readonly property int rowHeight: 44
  readonly property int rowPadX: 14
  readonly property int pagePadX: 30

  // ---------------------------------------------------------------- tipografia (escala do Omarchy)
  readonly property int caption: Style.font.caption
  readonly property int small: Style.font.bodySmall
  readonly property int body: Style.font.body
  readonly property int subtitle: Style.font.subtitle
  readonly property int title: Style.font.title
  readonly property int heading: Style.font.heading
  readonly property int display: Style.font.display
  readonly property int displayLarge: Style.font.displayLarge
}
