.pragma library

// Glifos próprios do Pomarchy, numa grade de 24 unidades. Cada um tem a parte
// traçada ("stroke") e a parte preenchida ("fill", regra par-ímpar: um
// subcaminho dentro de outro vira furo). Nada copiado de ícones da Apple.

function f(n) {
  return Math.round(n * 100) / 100
}

function roundRect(x, y, w, h, r) {
  return "M" + f(x + r) + " " + f(y) + " H" + f(x + w - r)
    + " A" + f(r) + " " + f(r) + " 0 0 1 " + f(x + w) + " " + f(y + r)
    + " V" + f(y + h - r)
    + " A" + f(r) + " " + f(r) + " 0 0 1 " + f(x + w - r) + " " + f(y + h)
    + " H" + f(x + r)
    + " A" + f(r) + " " + f(r) + " 0 0 1 " + f(x) + " " + f(y + h - r)
    + " V" + f(y + r)
    + " A" + f(r) + " " + f(r) + " 0 0 1 " + f(x + r) + " " + f(y) + " Z "
}

function circle(cx, cy, r) {
  return "M" + f(cx + r) + " " + f(cy)
    + " A" + f(r) + " " + f(r) + " 0 1 0 " + f(cx - r) + " " + f(cy)
    + " A" + f(r) + " " + f(r) + " 0 1 0 " + f(cx + r) + " " + f(cy) + " Z "
}

// Engrenagem gerada: dentes trapezoidais sobre um aro, furo no meio.
function gear() {
  var teeth = 8
  var outer = 10.4
  var root = 8.0
  var step = Math.PI * 2 / teeth
  var tip = 0.15
  var base = 0.25
  var d = ""
  for (var i = 0; i < teeth; i++) {
    var a = i * step - Math.PI / 2
    var p = [
      [a - base, root], [a - tip, outer], [a + tip, outer], [a + base, root]
    ]
    for (var k = 0; k < p.length; k++) {
      var x = 12 + Math.cos(p[k][0]) * p[k][1]
      var y = 12 + Math.sin(p[k][0]) * p[k][1]
      d += (i === 0 && k === 0 ? "M" : "L") + f(x) + " " + f(y) + " "
    }
    var next = (i + 1) * step - Math.PI / 2 - base
    d += "A" + f(root) + " " + f(root) + " 0 0 1 " + f(12 + Math.cos(next) * root) + " " + f(12 + Math.sin(next) * root) + " "
  }
  d += "Z "
  return d + circle(12, 12, 3.4)
}

var GLYPHS = {
  gear: { fill: gear() },
  dock: {
    stroke: roundRect(3, 4.5, 18, 14.5, 3),
    fill: roundRect(6.5, 14, 11, 2.6, 1.3)
  },
  menubar: {
    stroke: roundRect(3, 4.5, 18, 14.5, 3),
    fill: "M3 7.5 A3 3 0 0 1 6 4.5 H18 A3 3 0 0 1 21 7.5 V9.2 H3 Z"
  },
  mission: {
    fill: roundRect(2.5, 3.5, 5.6, 3.6, 1) + roundRect(9.2, 3.5, 5.6, 3.6, 1) + roundRect(15.9, 3.5, 5.6, 3.6, 1)
      + roundRect(2.5, 9.5, 8.8, 10.5, 1.8) + roundRect(12.7, 9.5, 8.8, 10.5, 1.8)
  },
  trackpad: {
    stroke: roundRect(3, 5, 18, 14, 3),
    fill: circle(9.6, 10.6, 1.7) + circle(14.4, 10.6, 1.7)
  },
  keyboard: {
    stroke: roundRect(2, 6, 20, 12.5, 2.6),
    fill: roundRect(5, 8.7, 2.1, 1.9, 0.5) + roundRect(8.4, 8.7, 2.1, 1.9, 0.5) + roundRect(11.8, 8.7, 2.1, 1.9, 0.5)
      + roundRect(15.2, 8.7, 2.1, 1.9, 0.5) + roundRect(5, 11.6, 2.1, 1.9, 0.5) + roundRect(8.4, 11.6, 2.1, 1.9, 0.5)
      + roundRect(11.8, 11.6, 2.1, 1.9, 0.5) + roundRect(15.2, 11.6, 2.1, 1.9, 0.5) + roundRect(7.4, 14.5, 9.2, 1.9, 0.9)
  },
  leaf: {
    stroke: "M4.2 20.6 L8.6 16.2",
    fill: "M6.4 18.2 C4.6 11.4 9.4 4.9 20 4 C20.6 14.4 14.6 20 6.4 18.2 Z "
      + "M7.6 16.6 L15.8 8.4 L16.5 9.1 L8.3 17.3 Z"
  },
  launchpad: {
    fill: roundRect(3.5, 3.5, 4.6, 4.6, 1.3) + roundRect(9.7, 3.5, 4.6, 4.6, 1.3) + roundRect(15.9, 3.5, 4.6, 4.6, 1.3)
      + roundRect(3.5, 9.7, 4.6, 4.6, 1.3) + roundRect(9.7, 9.7, 4.6, 4.6, 1.3) + roundRect(15.9, 9.7, 4.6, 4.6, 1.3)
      + roundRect(3.5, 15.9, 4.6, 4.6, 1.3) + roundRect(9.7, 15.9, 4.6, 4.6, 1.3) + roundRect(15.9, 15.9, 4.6, 4.6, 1.3)
  },
  trash: {
    stroke: "M4.5 7 H19.5 M9.5 7 V5.2 A1 1 0 0 1 10.5 4.2 H13.5 A1 1 0 0 1 14.5 5.2 V7 M6.5 7 L7.4 18.6 A1.6 1.6 0 0 0 9 20 H15 A1.6 1.6 0 0 0 16.6 18.6 L17.5 7 M10.2 10.5 V16.5 M13.8 10.5 V16.5"
  },
  close: { stroke: "M7 7 L17 17 M17 7 L7 17" },
  minus: { stroke: "M6.5 12 H17.5" },
  check: { stroke: "M5.5 12.6 L10 17 L18.6 7.6" },
  chevronLeft: { stroke: "M14.5 6 L8.5 12 L14.5 18" },
  chevronRight: { stroke: "M9.5 6 L15.5 12 L9.5 18" },
  arrowUp: { stroke: "M12 19.5 V5 M6.5 10.5 L12 5 L17.5 10.5" },
  arrowDown: { stroke: "M12 4.5 V19 M6.5 13.5 L12 19 L17.5 13.5" },
  arrowLeft: { stroke: "M19.5 12 H5 M10.5 6.5 L5 12 L10.5 17.5" },
  arrowRight: { stroke: "M4.5 12 H19 M13.5 6.5 L19 12 L13.5 17.5" },
  external: { stroke: "M13.5 4.5 H19.5 V10.5 M19.5 4.5 L11.5 12.5 M17.5 14 V17.5 A2 2 0 0 1 15.5 19.5 H6.5 A2 2 0 0 1 4.5 17.5 V8.5 A2 2 0 0 1 6.5 6.5 H10" },
  pointer: {
    stroke: "M6 2.8 L6 19.6 L10.3 15.7 L13.1 21.7 L15.9 20.4 L13.1 14.5 L18.9 14.3 Z",
    fill: "M6 2.8 L6 19.6 L10.3 15.7 L13.1 21.7 L15.9 20.4 L13.1 14.5 L18.9 14.3 Z"
  },
  sun: {
    stroke: "M12 2.8 V4.6 M12 19.4 V21.2 M2.8 12 H4.6 M19.4 12 H21.2 M5.5 5.5 L6.8 6.8 M17.2 17.2 L18.5 18.5 M5.5 18.5 L6.8 17.2 M17.2 6.8 L18.5 5.5",
    fill: circle(12, 12, 4.6)
  },
  moon: { fill: "M15.6 3.4 A8.8 8.8 0 1 0 20.6 16.2 A7.2 7.2 0 0 1 15.6 3.4 Z" },
  sparkle: { fill: "M12 3 C12.8 8.4 15.6 11.2 21 12 C15.6 12.8 12.8 15.6 12 21 C11.2 15.6 8.4 12.8 3 12 C8.4 11.2 11.2 8.4 12 3 Z" }
}

function get(name) {
  return GLYPHS[name] || {}
}
