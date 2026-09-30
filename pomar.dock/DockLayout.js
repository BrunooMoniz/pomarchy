.pragma library
.import "shared/Tokens.js" as Tokens

// Geometria do Dock: onde cada item fica e de que tamanho, com a ampliação do
// Mac. O Dock é uma fila de segmentos (margem, itens, vãos de arrasto,
// margem). Cada item ocupa `tamanho + respiro`, multiplicado pela presença
// (0 a 1), que anima a entrada e a saída de itens sem salto.
//
// A ampliação mede a distância do cursor até o centro de REPOUSO de cada
// ícone, em coordenadas de tela. Como o repouso não depende da ampliação, não
// há retroalimentação e nada treme. A fila ampliada é então ancorada no
// cursor: o ponto sob ele continua na mesma fração do mesmo segmento, então o
// ícone sob o cursor não foge dele e o Dock cresce para os dois lados.

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

// flow: [{ key, kind, presence }], kind = app | launchpad | minimized | trash | separator | gap
// dims: { iconSize, magnifiedSize, gap, edge, sepWidth, centerX, span }
// pointer: { x, zoom }
function compute(flow, dims, pointer) {
  var s = dims.iconSize
  var m = Math.max(s, dims.magnifiedSize)
  var zoom = clamp(pointer.zoom || 0, 0, 1)
  var segs = [{ pad: true, r: dims.edge }]
  for (var i = 0; i < flow.length; i++) {
    var item = flow[i]
    var presence = clamp(item.presence, 0, 1)
    var base = item.kind === "separator" ? dims.sepWidth : s + dims.gap
    segs.push({ item: item, presence: presence, r: base * presence })
  }
  segs.push({ pad: true, r: dims.edge })

  // Repouso: fila centrada na tela.
  var restTotal = 0
  for (var a = 0; a < segs.length; a++) restTotal += segs[a].r
  var restLeft = dims.centerX - restTotal / 2
  var cursor = restLeft
  for (var b = 0; b < segs.length; b++) {
    segs[b].L = cursor
    segs[b].c = cursor + segs[b].r / 2
    cursor += segs[b].r
  }
  var restRight = cursor

  // Tamanho ampliado de cada item pela curva em sino.
  for (var c = 0; c < segs.length; c++) {
    var seg = segs[c]
    if (seg.pad) { seg.size = 0; seg.M = seg.r; continue }
    if (seg.item.kind === "separator") { seg.size = dims.sepWidth; seg.M = seg.r; continue }
    var f = zoom > 0 ? Tokens.magnify(Math.abs(pointer.x - seg.c), dims.span) * zoom : 0
    seg.size = s + (m - s) * f
    seg.M = (seg.size + dims.gap) * seg.presence
  }

  // Âncora: segmento de repouso sob o cursor e a fração dentro dele.
  var X = clamp(pointer.x, restLeft, restRight)
  var k = segs.length - 1
  for (var d = 0; d < segs.length; d++) {
    if (X < segs[d].L + segs[d].r) { k = d; break }
  }
  var t = segs[k].r > 0 ? clamp((X - segs[k].L) / segs[k].r, 0, 1) : 0
  var before = 0
  for (var e = 0; e < k; e++) before += segs[e].M
  var left = zoom > 0 ? X - t * segs[k].M - before : restLeft

  var out = { items: ({}), order: [], left: left, right: left, restLeft: restLeft, restRight: restRight, maxSize: s }
  var x = left
  for (var g = 0; g < segs.length; g++) {
    var sg = segs[g]
    if (!sg.pad) {
      out.items[sg.item.key] = {
        key: sg.item.key,
        kind: sg.item.kind,
        center: x + sg.M / 2,
        size: sg.size,
        slotLeft: x,
        slotWidth: sg.M,
        restCenter: sg.c,
        presence: sg.presence
      }
      out.order.push(sg.item.key)
      if (sg.item.kind !== "separator" && sg.item.kind !== "gap") out.maxSize = Math.max(out.maxSize, sg.size)
    }
    x += sg.M
  }
  out.right = x
  return out
}

// Item cujo segmento contém x (os segmentos são contíguos). Ignora vãos.
function keyAt(layout, x) {
  if (!layout || x < layout.left || x > layout.right) return ""
  var best = ""
  var bestDistance = Infinity
  for (var i = 0; i < layout.order.length; i++) {
    var slot = layout.items[layout.order[i]]
    if (slot.kind === "gap" || slot.presence < 0.5) continue
    if (x >= slot.slotLeft && x < slot.slotLeft + slot.slotWidth) return slot.key
    var distance = Math.abs(x - slot.center)
    if (distance < bestDistance) { bestDistance = distance; best = slot.key }
  }
  return best
}
