.pragma library

// Identidade de apps: liga janelas (classe do Hyprland / appId do Wayland) às
// entradas .desktop, que dão nome, ícone e o jeito certo de abrir.
// Os singletons do Quickshell chegam por parâmetro porque uma biblioteca JS
// não enxerga o contexto QML.

function stripDesktop(id) {
  var value = String(id || "").trim()
  return value.slice(-8) === ".desktop" ? value.slice(0, -8) : value
}

// Webapps do Omarchy abrem no Chromium com --app=URL e a janela ganha a
// classe "chrome-HOST__CAMINHO-PERFIL" em vez da do .desktop. Sem ligar o
// host ao .desktop, o WhatsApp aberto apareceria sem nome e sem ícone.
function webappHost(windowClass) {
  var match = /^(?:chrome|chromium|brave|msedge|vivaldi|opera|helium)-([^_]+)__/i.exec(String(windowClass || ""))
  return match ? match[1].toLowerCase() : ""
}

function execHost(execString) {
  var match = /https?:\/\/([^\/\s"'?#]+)/i.exec(String(execString || ""))
  return match ? match[1].toLowerCase() : ""
}

// Mapa host -> id do .desktop, montado a partir de todos os apps instalados.
function webappIndex(entries) {
  var index = ({})
  var list = entries || []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry || !entry.id) continue
    var host = execHost(entry.execString)
    if (host && !(host in index)) index[host] = entry.id
  }
  return index
}

function entryFor(desktopEntries, appId, index) {
  var id = stripDesktop(appId)
  if (!id || !desktopEntries) return null
  var host = webappHost(id)
  if (host && index && index[host]) {
    var web = desktopEntries.byId(index[host])
    if (web) return web
  }
  return desktopEntries.byId(id)
    || desktopEntries.byId(id.toLowerCase())
    || desktopEntries.heuristicLookup(id)
    || null
}

function displayName(entry, fallbackId) {
  if (entry && entry.name) return entry.name
  var id = stripDesktop(fallbackId)
  var tail = id.split(".").pop() || id
  return tail.length ? tail.charAt(0).toUpperCase() + tail.slice(1) : id
}

function iconSource(quickshell, entry, fallbackId) {
  var icon = entry && entry.icon ? String(entry.icon) : ""
  if (icon.indexOf("/") === 0) return "file://" + icon
  if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon
  var themed = icon ? quickshell.iconPath(icon, true) : ""
  if (themed) return themed
  var byId = fallbackId ? quickshell.iconPath(stripDesktop(fallbackId).toLowerCase(), true) : ""
  if (byId) return byId
  return quickshell.iconPath("application-x-executable", "")
}

// Abre pelo mesmo caminho do lançador do Omarchy: gtk-launch dentro de um
// escopo do uwsm, para o app não herdar o serviço do compositor.
function launch(quickshell, desktopId) {
  var id = stripDesktop(desktopId)
  if (!id) return
  quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
}

// Classe de janela -> chave estável de app, para agrupar janelas no Dock e no
// alternador. Usa o id do .desktop quando existe.
function appKey(desktopEntries, windowClass, index) {
  var entry = entryFor(desktopEntries, windowClass, index)
  return entry ? entry.id : String(windowClass || "").toLowerCase()
}

function sameApp(desktopEntries, windowClass, desktopId, index) {
  if (!windowClass || !desktopId) return false
  return appKey(desktopEntries, windowClass, index) === stripDesktop(desktopId)
}

// Em teste (POMAR_TEST=1) nada é aberto de verdade: só fica anotado no log.
// Defesa extra: o harness também troca uwsm-app e gtk-launch por dublês.
function launchGuarded(quickshell, desktopId) {
  if (quickshell.env("POMAR_TEST") === "1") {
    console.log("POMAR_LAUNCH " + stripDesktop(desktopId))
    return
  }
  launch(quickshell, desktopId)
}
