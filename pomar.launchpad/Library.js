.pragma library

// Catálogo e busca do Launchpad. Funções puras: recebem as entradas .desktop
// já filtradas e devolvem objetos simples, que a grade usa como modelo.

// Minúsculas e sem acento: "Ação" e "acao" são a mesma coisa para quem busca
// e para a ordem alfabética (num locale C o localeCompare põe acento no fim).
function fold(text) {
  var value = String(text || "").toLowerCase()
  if (typeof value.normalize === "function") value = value.normalize("NFD")
  return value.replace(/[̀-ͯ]/g, "")
}

function words(folded) {
  var parts = String(folded || "").split(/[^a-z0-9]+/)
  var out = []
  for (var i = 0; i < parts.length; i++) if (parts[i]) out.push(parts[i])
  return out
}

function listText(value) {
  if (!value) return ""
  try {
    if (typeof value.join === "function") return value.join(" ")
  } catch (error) {}
  var out = []
  for (var i = 0; i < (value.length || 0); i++) out.push(String(value[i]))
  return out.join(" ")
}

// Categorias do padrão freedesktop com as palavras que uma pessoa usaria em
// português. As categorias em inglês já entram como estão.
var CATEGORY_WORDS = {
  AudioVideo: "audio video som musica filme multimidia",
  Audio: "audio som musica",
  Video: "video filme",
  Player: "player reprodutor tocador",
  Recorder: "gravador gravacao",
  Development: "desenvolvimento programacao codigo",
  IDE: "programacao codigo",
  Education: "educacao ensino escola",
  Game: "jogo jogos games",
  Graphics: "graficos imagem imagens desenho",
  Photography: "foto fotos fotografia",
  Viewer: "visualizador",
  Network: "internet rede",
  WebBrowser: "navegador internet web",
  Email: "email correio",
  Chat: "conversa mensagens bate-papo",
  InstantMessaging: "mensagens conversa",
  Office: "escritorio documentos",
  WordProcessor: "texto documento",
  Spreadsheet: "planilha",
  Presentation: "apresentacao slides",
  Calendar: "calendario agenda",
  Science: "ciencia",
  Settings: "ajustes configuracoes preferencias",
  System: "sistema",
  Monitor: "monitor desempenho",
  Utility: "utilitarios acessorios ferramentas",
  TextEditor: "editor texto",
  FileManager: "arquivos pastas",
  TerminalEmulator: "terminal",
  Calculator: "calculadora",
  Archiving: "compactar arquivos",
  Security: "seguranca senhas"
}

function categoryText(categories) {
  var list = []
  var raw = categories || []
  for (var i = 0; i < (raw.length || 0); i++) {
    var name = String(raw[i] || "")
    if (!name) continue
    list.push(name)
    if (CATEGORY_WORDS[name]) list.push(CATEGORY_WORDS[name])
  }
  return list.join(" ")
}

// Iniciais das palavras do nome ("Visual Studio Code" -> "vsc").
function acronym(nameWords) {
  var out = ""
  for (var i = 0; i < nameWords.length; i++) out += nameWords[i].charAt(0)
  return out
}

// Converte uma DesktopEntry num item da grade, com os campos de busca prontos.
function makeItem(entry, iconUrl) {
  var name = String(entry.name || entry.id || "")
  var nameFolded = fold(name)
  var nameWords = words(nameFolded)
  var generic = fold(entry.genericName)
  var keywords = fold(listText(entry.keywords))
  var categories = fold(categoryText(entry.categories))
  return {
    id: String(entry.id || ""),
    name: name,
    icon: iconUrl,
    key: nameFolded,
    nameWords: nameWords,
    acronym: acronym(nameWords),
    genericWords: words(generic),
    keywordWords: words(keywords),
    categoryWords: words(categories),
    idWords: words(fold(entry.id))
  }
}

function compare(a, b) {
  var byKey = a.key.localeCompare(b.key, "pt-BR")
  if (byKey !== 0) return byKey
  return a.name.localeCompare(b.name, "pt-BR")
}

function sortItems(items) {
  return items.slice().sort(compare)
}

function startsAny(list, term) {
  for (var i = 0; i < list.length; i++) if (list[i].indexOf(term) === 0) return true
  return false
}

// Pontua um termo: começo do nome vence começo de palavra do nome, que vence
// sigla, que vence trecho do nome, e só depois vêm nome genérico, palavras-chave
// e categorias. Fora do nome só vale começo de palavra: com duas letras, um
// trecho qualquer ("ca" em "educacao") traria metade dos apps. Zero = não casa.
function termScore(item, term) {
  if (item.key.indexOf(term) === 0) return 1000
  if (startsAny(item.nameWords, term)) return 800
  if (term.length >= 2 && item.acronym.indexOf(term) === 0) return 700
  if (term.length >= 2 && item.key.indexOf(term) > 0) return 600
  if (startsAny(item.genericWords, term)) return 500
  if (startsAny(item.keywordWords, term)) return 350
  if (startsAny(item.categoryWords, term)) return 250
  if (startsAny(item.idWords, term)) return 150
  return 0
}

function score(item, terms) {
  var total = 0
  for (var i = 0; i < terms.length; i++) {
    var value = termScore(item, terms[i])
    if (value <= 0) return 0
    total += value
  }
  return total
}

// Resultado da busca: todos os termos precisam casar; melhor pontuação primeiro
// e, no empate, ordem alfabética (ENTER abre o primeiro, então a ordem importa).
function search(items, query) {
  var terms = words(fold(query))
  if (terms.length === 0) return []
  var rows = []
  for (var i = 0; i < items.length; i++) {
    var value = score(items[i], terms)
    if (value > 0) rows.push({ item: items[i], score: value })
  }
  rows.sort(function(a, b) { return b.score - a.score || compare(a.item, b.item) })
  var out = []
  for (var j = 0; j < rows.length; j++) out.push(rows[j].item)
  return out
}

// Assinatura do catálogo: evita recriar a grade inteira quando nada mudou de
// verdade (um ajuste do Dock regrava o settings.json e dispara a reconstrução).
function signature(items) {
  var parts = []
  for (var i = 0; i < items.length; i++) parts.push(items[i].id + "\u0001" + items[i].name + "\u0001" + items[i].icon)
  return parts.join("\u0002")
}

function idSet(list) {
  var out = ({})
  var raw = list || []
  for (var i = 0; i < (raw.length || 0); i++) {
    var id = String(raw[i] || "").trim()
    if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
    if (id) out[id] = true
  }
  return out
}

function linesToSet(text) {
  return idSet(String(text || "").split(/\n/))
}
