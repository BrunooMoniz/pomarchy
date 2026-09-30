.pragma library

// Tokens visuais do Pomarchy: materiais, cantos, tipografia e movimento no estilo
// do macOS. As cores de base (fundo, texto, destaque) vêm do tema do Omarchy
// pelo singleton Color; aqui ficam só as derivações.

var radius = {
  dock: 22,
  dockItem: 14,
  menu: 12,
  menuItem: 6,
  card: 16,
  thumb: 12,
  window: 14,
  pill: 999
}

// Durações em ms. As curvas equivalem às do macOS: saída rápida, pouso macio.
var motion = {
  instant: 90,
  fast: 160,
  base: 240,
  slow: 380,
  bounce: 520
}

var fontCandidates = ["SF Pro Text", "SF Pro Display", "Adwaita Sans", "Inter", "Inter Variable", "Cantarell", "Noto Sans"]

function uiFont(available) {
  var families = available || []
  for (var i = 0; i < fontCandidates.length; i++) {
    if (families.indexOf(fontCandidates[i]) !== -1) return fontCandidates[i]
  }
  return "Sans Serif"
}

function luminance(color) {
  if (!color) return 0
  return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
}

function isDark(background) {
  return luminance(background) < 0.5
}

function withAlpha(color, alpha) {
  return Qt.rgba(color.r, color.g, color.b, alpha)
}

function mix(a, b, amount) {
  var t = Math.max(0, Math.min(1, amount))
  return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
}

// Vidro do Dock, da barra e dos cartões. O desfoque atrás vem do Hyprland.
function glass(dark) {
  return dark ? Qt.rgba(0.16, 0.16, 0.18, 0.68) : Qt.rgba(0.98, 0.98, 0.99, 0.66)
}

// Vidro mais denso para menus e o alternador de apps, onde texto precisa ler bem.
function glassStrong(dark) {
  return dark ? Qt.rgba(0.14, 0.14, 0.16, 0.88) : Qt.rgba(0.97, 0.97, 0.98, 0.90)
}

// Filete claro interno que dá o brilho de borda do vidro.
function hairline(dark) {
  return dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.70)
}

// Contorno externo de 1px que separa o vidro do fundo.
function outline(dark) {
  return dark ? Qt.rgba(0, 0, 0, 0.42) : Qt.rgba(0, 0, 0, 0.10)
}

function label(dark) {
  return dark ? Qt.rgba(0.96, 0.96, 0.97, 1) : Qt.rgba(0.11, 0.11, 0.12, 1)
}

function secondaryLabel(dark) {
  return dark ? Qt.rgba(0.92, 0.92, 0.96, 0.62) : Qt.rgba(0.20, 0.20, 0.23, 0.62)
}

function separator(dark) {
  return dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
}

// Fundo de item em foco em listas e grades (hover e teclado).
function hover(dark) {
  return dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)
}

function pressed(dark) {
  return dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.13)
}

// Véu sobre o papel de parede no Launchpad e no Mission Control.
function scrim(dark, strength) {
  var s = strength === undefined ? 1 : strength
  return dark ? Qt.rgba(0, 0, 0, 0.38 * s) : Qt.rgba(0.05, 0.05, 0.08, 0.26 * s)
}

function shadow(dark) {
  return dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.20)
}

// Fator de ampliação do Dock para um ícone a `distance` px do cursor.
// Curva em sino como a do macOS; `span` é o alcance em px.
function magnify(distance, span) {
  if (span <= 0) return 0
  var x = distance / span
  if (Math.abs(x) >= 1) return 0
  return Math.cos(x * Math.PI / 2) * Math.cos(x * Math.PI / 2)
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

// Interpolação usada pelos gestos ao vivo (progresso 0 a 1).
function lerp(a, b, t) {
  return a + (b - a) * t
}
