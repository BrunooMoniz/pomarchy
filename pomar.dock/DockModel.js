.pragma library
.import "shared/Apps.js" as Apps

// Regras de conteúdo do Dock, sem QML: que app é cada janela, lista inicial
// de favoritos e a ordem estável dos itens.

var LAUNCHPAD = "pomar:launchpad"

// Webapps: a regra mora em shared/Apps.js para Dock, alternador, Mission
// Control e barra de menus reconhecerem o mesmo app.
function webappHost(windowClass) { return Apps.webappHost(windowClass) }
function execHost(execString) { return Apps.execHost(execString) }
function webappIndex(entries) { return Apps.webappIndex(entries) }

// Chave estável de app para uma janela: o id do .desktop quando existe.
function appKey(desktopEntries, index, windowClass) {
  var host = webappHost(windowClass)
  if (host && index && index[host]) return index[host]
  return Apps.appKey(desktopEntries, windowClass)
}

// Favoritos como ids limpos (sem ".desktop"), sem repetição nem lixo.
function normalizeFavorites(list) {
  var out = []
  var seen = ({})
  var source = Array.isArray(list) ? list : []
  for (var i = 0; i < source.length; i++) {
    if (typeof source[i] !== "string") continue
    var id = Apps.stripDesktop(source[i])
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

// Mantém a ordem já conhecida e acrescenta os novos no fim, na ordem de
// chegada: apps abertos não pulam de lugar a cada troca de foco.
function stableOrder(previous, current) {
  var present = ({})
  for (var i = 0; i < current.length; i++) present[current[i]] = true
  var out = []
  var seen = ({})
  for (var j = 0; j < previous.length; j++) {
    var key = previous[j]
    if (present[key] && !seen[key]) { out.push(key); seen[key] = true }
  }
  for (var k = 0; k < current.length; k++) {
    if (!seen[current[k]]) { out.push(current[k]); seen[current[k]] = true }
  }
  return out
}

// Lista exibida = lista nova + itens que estão saindo, cada um no lugar onde
// estava, para a animação de saída acontecer no ponto certo.
function mergeDisplay(previousKeys, targetKeys) {
  var inTarget = ({})
  for (var i = 0; i < targetKeys.length; i++) inTarget[targetKeys[i]] = true
  var out = []
  var emitted = ({})
  var ti = 0
  for (var p = 0; p < previousKeys.length; p++) {
    var key = previousKeys[p]
    if (inTarget[key]) {
      while (ti < targetKeys.length) {
        var next = targetKeys[ti++]
        if (!emitted[next]) { out.push(next); emitted[next] = true }
        if (next === key) break
      }
    } else if (!emitted[key]) {
      out.push(key)
      emitted[key] = true
    }
  }
  while (ti < targetKeys.length) {
    var rest = targetKeys[ti++]
    if (!emitted[rest]) { out.push(rest); emitted[rest] = true }
  }
  return out
}

// Lista inicial na ordem do Dock do Mac (Finder, Launchpad, navegador,
// mensagens, e-mail, mapas, fotos, agenda, contatos, notas, música) e o
// terminal do Omarchy no fim. Em cada grupo entra o primeiro que existir.
var STARTER_GROUPS = [
  ["org.gnome.Nautilus"],
  [LAUNCHPAD],
  ["@browser"],
  ["WhatsApp", "Google Messages", "signal", "org.telegram.desktop", "Telegram"],
  ["HEY", "org.gnome.Geary", "thunderbird", "org.mozilla.Thunderbird"],
  ["Google Maps"],
  ["Google Photos"],
  ["Calendar", "org.gnome.Calendar"],
  ["Google Contacts"],
  ["obsidian", "md.obsidian.Obsidian"],
  ["spotify", "com.spotify.Client"],
  ["@terminal"]
]

function starterFavorites(exists, browserId, terminalId) {
  var out = []
  var seen = ({})
  for (var g = 0; g < STARTER_GROUPS.length; g++) {
    var group = STARTER_GROUPS[g]
    for (var i = 0; i < group.length; i++) {
      var id = group[i]
      if (id === "@browser") id = Apps.stripDesktop(browserId)
      else if (id === "@terminal") id = Apps.stripDesktop(terminalId)
      if (!id || seen[id]) continue
      if (id !== LAUNCHPAD && !exists(id)) continue
      out.push(id)
      seen[id] = true
      break
    }
  }
  return out
}

// "browser=chromium.desktop\nterminal=foot.desktop:new-window" -> ids limpos.
function parseDefaults(text) {
  var out = { browser: "", terminal: "" }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    var eq = line.indexOf("=")
    if (eq < 0) continue
    var name = line.slice(0, eq)
    var value = line.slice(eq + 1).split(":")[0].trim()
    if (name === "browser" || name === "terminal") out[name] = Apps.stripDesktop(value)
  }
  return out
}
