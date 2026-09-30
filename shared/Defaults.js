.pragma library

// Ajustes padrão do Pomarchy. Espelho de hypr/pomar.lua (DEFAULTS): quem mudar um
// lado muda o outro; tests/test_contract.py compara os dois.
var DEFAULTS = {
  version: 1,
  // Mantém Dock, Launchpad e companhia ligados mesmo com outro tema do Omarchy.
  alwaysOn: false,
  // "auto" segue o LANG do sistema; "pt" ou "en" forçam o idioma.
  language: "auto",
  dock: {
    enabled: true,
    position: "bottom",
    iconSize: 54,
    magnification: true,
    magnifiedSize: 82,
    autohide: false,
    showRunning: true,
    showMinimized: true,
    showTrash: true,
    // Marca que a lista inicial de favoritos já foi montada uma vez: um Dock
    // esvaziado de propósito continua vazio.
    seeded: false,
    // Ids de .desktop (sem a extensão). "pomar:launchpad" é o ícone do Launchpad.
    // Vazio = o Dock monta uma lista inicial com os apps que existem na máquina.
    favorites: []
  },
  launchpad: {
    enabled: true,
    hidden: []
  },
  mission: {
    enabled: true
  },
  switcher: {
    enabled: true
  },
  menubar: {
    enabled: true
  },
  // Botões de fechar, minimizar e zoom no alto de cada janela.
  windowControls: {
    enabled: true
  },
  gestures: {
    enabled: true,
    // Dedos para trocar de mesa (deslizar para os lados).
    spacesFingers: 3,
    // Dedos para Mission Control (para cima) e App Exposé (para baixo).
    missionFingers: 3,
    // Pinça com quatro dedos abre o Launchpad; abrir os dedos fecha.
    launchpadPinch: true
  },
  keys: {
    cmdTab: true,
    missionControl: true,
    launchpad: true,
    minimize: true,
    dockToggle: true
  },
  welcome: {
    seen: false
  }
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

// Copia `source` por cima de `target`, chave a chave, sem trocar o tipo de uma
// chave conhecida: um arquivo editado à mão com `"iconSize": "grande"` não
// derruba o Dock, só é ignorado.
function mergeInto(target, source) {
  if (!isObject(source)) return target
  for (var key in source) {
    var incoming = source[key]
    if (!(key in target)) {
      target[key] = clone(incoming)
    } else if (isObject(target[key])) {
      mergeInto(target[key], incoming)
    } else if (Array.isArray(target[key])) {
      if (Array.isArray(incoming)) target[key] = clone(incoming)
    } else if (typeof incoming === typeof target[key]) {
      target[key] = incoming
    }
  }
  return target
}

function merged(userData) {
  return mergeInto(clone(DEFAULTS), userData)
}

function parse(text) {
  try {
    var value = JSON.parse(String(text || ""))
    return isObject(value) ? value : null
  } catch (error) {
    return null
  }
}

function lookup(data, keyPath, fallback) {
  var parts = String(keyPath || "").split(".")
  var node = data
  for (var i = 0; i < parts.length; i++) {
    if (!isObject(node) || !(parts[i] in node)) return fallback
    node = node[parts[i]]
  }
  return node === undefined || node === null ? fallback : node
}

function assign(data, keyPath, value) {
  var parts = String(keyPath || "").split(".")
  var node = data
  for (var i = 0; i < parts.length - 1; i++) {
    if (!isObject(node[parts[i]])) node[parts[i]] = {}
    node = node[parts[i]]
  }
  node[parts[parts.length - 1]] = clone(value === undefined ? null : value)
  return data
}
