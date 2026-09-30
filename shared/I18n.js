.pragma library

// Idioma do Pomarchy. Cada plugin guarda os próprios textos num Strings.js ao
// lado do código; aqui ficam só a escolha de idioma e os textos em comum.

function resolve(setting, envLang) {
  var value = String(setting || "auto").toLowerCase()
  if (value === "pt" || value === "en") return value
  var env = String(envLang || "").toLowerCase()
  return env.indexOf("pt") === 0 ? "pt" : "en"
}

// `table` = { chave: { pt: "...", en: "..." } }. Aceita {0}, {1} para valores.
function tr(table, key, lang) {
  var entry = table[key] || COMMON[key]
  var text = entry ? (entry[lang] || entry.en || key) : key
  for (var i = 3; i < arguments.length; i++) {
    text = text.split("{" + (i - 3) + "}").join(String(arguments[i]))
  }
  return text
}

var COMMON = {
  "app.name": { pt: "Pomarchy OS", en: "Pomarchy OS" },
  "launchpad": { pt: "Launchpad", en: "Launchpad" },
  "mission": { pt: "Mission Control", en: "Mission Control" },
  "expose": { pt: "Todas as janelas do app", en: "App Exposé" },
  "settings": { pt: "Ajustes do Pomarchy", en: "Pomarchy Settings" },
  "dock": { pt: "Dock", en: "Dock" },
  "trash": { pt: "Lixeira", en: "Trash" },
  "desktop": { pt: "Mesa {0}", en: "Desktop {0}" },
  "open": { pt: "Abrir", en: "Open" },
  "newWindow": { pt: "Nova janela", en: "New Window" },
  "quit": { pt: "Encerrar", en: "Quit" },
  "close": { pt: "Fechar", en: "Close" },
  "cancel": { pt: "Cancelar", en: "Cancel" },
  "keepInDock": { pt: "Manter no Dock", en: "Keep in Dock" },
  "removeFromDock": { pt: "Remover do Dock", en: "Remove from Dock" },
  "search": { pt: "Buscar", en: "Search" }
}
