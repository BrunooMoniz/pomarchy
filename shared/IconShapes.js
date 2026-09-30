.pragma library

// Formato de cada ícone de app, medido uma vez pelo canal alfa (32x32):
// - "full": já é um quadrado (ou quadrado arredondado) grande e cheio, como
//   Obsidian ou Notion; só ganha os cantos no padrão do Pomarchy;
// - "free": redondo ou de formato livre, como Chromium ou Arquivos; vai para
//   dentro de uma placa arredondada.
// O resultado fica guardado por caminho de ícone enquanto o shell viver.

var shapes = ({})
var FULL_BOX = { x0: 0, y0: 0, x1: 1, y1: 1 }

function known(src) {
  return Object.prototype.hasOwnProperty.call(shapes, String(src || ""))
}

function lookup(src, version) {
  var entry = shapes[String(src || "")]
  return entry ? entry.shape : "unknown"
}

function box(src, version) {
  var entry = shapes[String(src || "")]
  return entry && entry.box ? entry.box : FULL_BOX
}

// data: RGBA de n x n pixels (Canvas.getImageData().data).
function classify(data, n) {
  var minX = n, minY = n, maxX = -1, maxY = -1, count = 0
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (data[(y * n + x) * 4 + 3] > 128) {
        count++
        if (x < minX) minX = x
        if (x > maxX) maxX = x
        if (y < minY) minY = y
        if (y > maxY) maxY = y
      }
    }
  }
  if (count === 0) return { shape: "free", box: FULL_BOX }
  var w = maxX - minX + 1
  var h = maxY - minY + 1
  var fill = count / (w * h)
  var cover = Math.min(w, h) / n
  // Quadrado arredondado cheio: cantos arredondados tiram pouco (> 0,9 cheio);
  // um círculo fica em ~0,79 e vai para a placa.
  var full = Math.abs(w - h) <= 2 && cover >= 0.78 && fill >= 0.9
  return { shape: full ? "full" : "free",
           box: { x0: minX / n, y0: minY / n, x1: (maxX + 1) / n, y1: (maxY + 1) / n } }
}

function remember(src, data, n) {
  shapes[String(src || "")] = classify(data, n)
  return shapes[String(src || "")]
}
