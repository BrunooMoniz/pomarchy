.pragma library

// Arranjo "Exposé": espalha as janelas numa grade de linhas sem sobreposição,
// com a mesma escala para todas (proporções preservadas) e a maior escala que
// cabe na área. As janelas continuam perto de onde estavam: quem estava em
// cima fica nas linhas de cima, quem estava à esquerda fica à esquerda.
//
// windows: [{ x, y, w, h }] em px locais; area: { x, y, w, h }.
// Devolve [{ x, y, w, h }] na mesma ordem da entrada.

function split(count, rows) {
  var sizes = []
  var base = Math.floor(count / rows)
  var extra = count % rows
  for (var r = 0; r < rows; r++) sizes.push(base + (r < extra ? 1 : 0))
  return sizes
}

function arrange(windows, rows, area, gap, maxScale) {
  var order = []
  for (var i = 0; i < windows.length; i++) order.push(i)
  order.sort(function(a, b) {
    var ay = windows[a].y + windows[a].h / 2, by = windows[b].y + windows[b].h / 2
    if (Math.abs(ay - by) > 1) return ay - by
    return (windows[a].x + windows[a].w / 2) - (windows[b].x + windows[b].w / 2)
  })
  var sizes = split(order.length, rows)
  var groups = []
  var cursor = 0
  for (var r = 0; r < rows; r++) {
    var group = order.slice(cursor, cursor + sizes[r])
    cursor += sizes[r]
    group.sort(function(a, b) {
      return (windows[a].x + windows[a].w / 2) - (windows[b].x + windows[b].w / 2)
    })
    groups.push(group)
  }

  var scale = maxScale
  var sumHeights = 0
  for (var g = 0; g < groups.length; g++) {
    var widths = 0
    var tallest = 0
    for (var k = 0; k < groups[g].length; k++) {
      widths += windows[groups[g][k]].w
      tallest = Math.max(tallest, windows[groups[g][k]].h)
    }
    var room = area.w - gap * (groups[g].length - 1)
    if (widths > 0) scale = Math.min(scale, room / widths)
    sumHeights += tallest
  }
  var roomY = area.h - gap * (groups.length - 1)
  if (sumHeights > 0) scale = Math.min(scale, roomY / sumHeights)
  return { groups: groups, scale: Math.max(0.02, scale) }
}

function layout(windows, area, options) {
  var opts = options || {}
  var gap = opts.gap === undefined ? 28 : opts.gap
  var maxScale = opts.maxScale === undefined ? 0.9 : opts.maxScale
  var count = windows.length
  if (count === 0) return []

  var best = null
  for (var rows = 1; rows <= count; rows++) {
    var candidate = arrange(windows, rows, area, gap, maxScale)
    // Empate técnico: prefira menos linhas (a leitura fica mais natural).
    if (!best || candidate.scale > best.scale * 1.01) best = candidate
  }

  var s = best.scale
  var result = new Array(count)
  var heights = []
  var total = 0
  for (var g = 0; g < best.groups.length; g++) {
    var tallest = 0
    for (var k = 0; k < best.groups[g].length; k++) tallest = Math.max(tallest, windows[best.groups[g][k]].h * s)
    heights.push(tallest)
    total += tallest
  }
  total += gap * (best.groups.length - 1)
  var y = area.y + (area.h - total) / 2
  for (var r = 0; r < best.groups.length; r++) {
    var group = best.groups[r]
    var rowWidth = gap * (group.length - 1)
    for (var j = 0; j < group.length; j++) rowWidth += windows[group[j]].w * s
    var x = area.x + (area.w - rowWidth) / 2
    for (var m = 0; m < group.length; m++) {
      var win = windows[group[m]]
      var w = win.w * s
      var h = win.h * s
      result[group[m]] = { x: x, y: y + (heights[r] - h) / 2, w: w, h: h }
      x += w + gap
    }
    y += heights[r] + gap
  }
  return result
}

// Vizinho mais próximo numa direção ("left", "right", "up", "down") para a
// navegação por setas.
function neighbor(rects, index, direction) {
  if (index < 0 || index >= rects.length) return rects.length ? 0 : -1
  var from = rects[index]
  var fx = from.x + from.w / 2, fy = from.y + from.h / 2
  var bestIndex = index
  var bestScore = Infinity
  for (var i = 0; i < rects.length; i++) {
    if (i === index) continue
    var r = rects[i]
    var dx = r.x + r.w / 2 - fx
    var dy = r.y + r.h / 2 - fy
    var along = direction === "left" ? -dx : direction === "right" ? dx : direction === "up" ? -dy : dy
    var across = direction === "left" || direction === "right" ? Math.abs(dy) : Math.abs(dx)
    if (along <= 1) continue
    var score = along + across * 2
    if (score < bestScore) { bestScore = score; bestIndex = i }
  }
  return bestIndex
}
