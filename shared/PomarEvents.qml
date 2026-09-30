import QtQuick
import Quickshell
import Quickshell.Hyprland

// Barramento de comandos do Pomarchy. O hypr/pomar.lua (gestos e atalhos) e o
// comando `pomar` publicam eventos no socket2 do Hyprland com
// hl.dsp.event("pomar>>alvo:verbo:argumento"); cada plugin escuta aqui e
// reage só ao próprio alvo. Nada de processo por quadro: um gesto ao vivo
// manda dezenas de eventos por segundo sem custo.
Item {
  id: root

  signal command(string target, string verb, string arg)

  function parse(data) {
    var text = String(data || "")
    if (text.indexOf("pomar>>") !== 0) return null
    var body = text.slice(7)
    var first = body.indexOf(":")
    var target = first < 0 ? body : body.slice(0, first)
    var rest = first < 0 ? "" : body.slice(first + 1)
    var second = rest.indexOf(":")
    return {
      target: target,
      verb: second < 0 ? rest : rest.slice(0, second),
      arg: second < 0 ? "" : decodeURIComponent(rest.slice(second + 1))
    }
  }

  // Publica um comando para os outros plugins (e para si mesmo).
  function send(target, verb, arg) {
    var body = String(target) + ":" + String(verb || "")
    if (arg !== undefined && arg !== null && String(arg).length > 0)
      body += ":" + encodeURIComponent(String(arg))
    root.dispatch('hl.dsp.event("pomar>>' + body + '")')
  }

  // Executa um dispatcher Lua do Hyprland, por exemplo
  // 'hl.dsp.focus({ workspace = "2" })'. Vai direto pelo socket do Hyprland,
  // sem abrir processo (o Quickshell sabe que a config é Lua).
  function dispatch(luaExpression) {
    Hyprland.dispatch(String(luaExpression))
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var parsed = root.parse(event.data)
      if (parsed) root.command(parsed.target, parsed.verb, parsed.arg)
    }
  }
}
