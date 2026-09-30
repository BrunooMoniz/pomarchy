-- Pomarchy para Hyprland: gestos, atalhos, animações e regras que deixam o
-- Omarchy com jeito de Mac.
--
-- Carregado pelo bloco "pomar" do ~/.config/hypr/hyprland.lua logo depois dos
-- padrões do Omarchy, então o que a pessoa escreve em ~/.config/hypr/*.lua
-- continua valendo por cima. Só age com um tema Pomarchy ativo (ou com
-- "alwaysOn" nos ajustes): ao trocar de tema o Omarchy recarrega o Hyprland e
-- tudo isto some sozinho.
--
-- Os plugins do shell recebem os gestos e atalhos como eventos no socket2
-- ("pomar>>alvo:verbo:arg"), sem abrir processo nenhum, o que deixa o gesto ao
-- vivo do Mission Control acompanhar o dedo.

local M = {}

local home = os.getenv("HOME") or ""
local here = (debug.getinfo(1, "S").source or ""):match("^@(.+)/[^/]+$") or "."
local json = dofile(here .. "/json.lua")

M.MINIMIZED = "special:pomar-minimized"

-- Espelho de shared/Defaults.js; tests/test_contract.py confere os dois.
M.DEFAULTS = {
  version = 1,
  alwaysOn = false,
  language = "auto",
  dock = {
    enabled = true, position = "bottom", iconSize = 54, magnification = true,
    magnifiedSize = 82, autohide = false, showRunning = true, showMinimized = true,
    showTrash = true, seeded = false, favorites = {},
  },
  launchpad = { enabled = true, hidden = {} },
  mission = { enabled = true },
  switcher = { enabled = true },
  menubar = { enabled = true },
  windowControls = { enabled = true },
  gestures = { enabled = true, spacesFingers = 3, missionFingers = 3, launchpadPinch = true },
  keys = { cmdTab = true, missionControl = true, launchpad = true, minimize = true, dockToggle = true },
  welcome = { seen = false },
}

local function read(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local function is_list(value)
  return type(value) == "table" and (next(value) == nil or value[1] ~= nil)
end

-- Mesma regra do Defaults.js: valor de tipo errado é ignorado, não derruba nada.
local function merge(target, source)
  if type(source) ~= "table" then return target end
  for key, incoming in pairs(source) do
    local current = target[key]
    if current == nil then
      target[key] = copy(incoming)
    elseif type(current) == "table" and not is_list(current) then
      if type(incoming) == "table" and not is_list(incoming) then merge(current, incoming) end
    elseif is_list(current) then
      if is_list(incoming) then target[key] = copy(incoming) end
    elseif type(incoming) == type(current) then
      target[key] = incoming
    end
  end
  return target
end

function M.load_settings(path)
  local decoded = json.decode(read(path) or "")
  return merge(copy(M.DEFAULTS), type(decoded) == "table" and decoded or nil)
end

function M.current_theme()
  return ((read(home .. "/.local/state/omarchy/current/theme.name") or ""):gsub("%s+$", ""))
end

function M.is_active(theme, settings)
  return (theme or ""):sub(1, 5) == "pomar" or (settings and settings.alwaysOn == true)
end

local function fingers(value, fallback)
  local n = math.floor(tonumber(value) or fallback)
  if n < 3 or n > 5 then return fallback end
  return n
end

function M.emit(message)
  hl.dispatch(hl.dsp.event("pomar>>" .. message))
end

local emit = M.emit

local function live(target)
  return {
    start = function() emit(target .. ":begin") end,
    update = function(e)
      if target == "launchpad" then
        if e and e.scale then emit(string.format("launchpad:scale:%.4f", e.scale)) end
      elseif e and e.delta then
        emit(string.format("%s:delta:%.2f", target, e.delta.y or 0))
      end
    end,
    finish = function(e) emit(target .. ":end:" .. ((e and e.cancelled) and "1" or "0")) end,
  }
end

-- Minimizar: o Dock recebe a posição da janela e começa o efeito "gênio" com a
-- imagem ao vivo dela; 70 ms depois a janela de verdade sai de cena por baixo
-- do efeito. Sem o Dock no ar, a janela só some (o evento não tem quem ouça).
function M.minimize_active()
  local w = hl.get_active_window()
  if not w or not w.address then return end
  local address = tostring(w.address)
  local at, size = w.at or {}, w.size or {}
  emit(string.format("dock:minimizing:%s,%d,%d,%d,%d", address, at.x or 0, at.y or 0, size.x or 0, size.y or 0))
  local function hide()
    hl.dispatch(hl.dsp.window.move({ window = "address:" .. address, workspace = M.MINIMIZED, follow = false }))
    emit("dock:minimized:" .. address)
  end
  if hl.timer then hl.timer(hide, { timeout = 70, type = "oneshot" }) else hide() end
end

-- Com o Pomarchy desligado não há Dock para devolver as minimizadas: elas
-- voltam sozinhas para a mesa ativa, senão ficariam escondidas para sempre.
function M.release_minimized()
  if not hl.get_windows then return end
  local ok, windows = pcall(hl.get_windows)
  if not ok or type(windows) ~= "table" then return end
  local active = hl.get_active_workspace and hl.get_active_workspace()
  local target = active and active.id and tostring(active.id) or "1"
  for _, w in ipairs(windows) do
    local ws = w.workspace
    if ws and tostring(ws.name) == M.MINIMIZED then
      hl.dispatch(hl.dsp.window.move({ window = "address:" .. tostring(w.address), workspace = target, follow = false }))
    end
  end
end

function M.apply_look()
  hl.curve("pomarOut", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
  hl.curve("pomarInOut", { type = "bezier", points = { { 0.45, 0 }, { 0.2, 1 } } })
  -- Fechar acelera para fora, como no Mac: começa devagar e some rápido.
  hl.curve("pomarIn", { type = "bezier", points = { { 0.5, 0 }, { 0.75, 0.25 } } })
  -- Crescer para tela cheia ou maximizar: sai rápido e pousa macio, sem quique.
  hl.curve("pomarZoom", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
  -- O Hyprland 0.56 chama o amortecimento de "dampening" (a wiki diz "damping").
  hl.curve("pomarSpring", { type = "spring", mass = 1, stiffness = 120, dampening = 20 })

  -- Abrir: zoom curto de 90% para 100% com a janela aparecendo (~300 ms).
  hl.animation({ leaf = "windowsIn", enabled = true, speed = 3.0, bezier = "pomarOut", style = "popin 90%" })
  hl.animation({ leaf = "fadeIn", enabled = true, speed = 2.2, bezier = "pomarOut" })
  -- Fechar: encolhe um pouco e some depressa (~180 ms).
  hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.8, bezier = "pomarIn", style = "popin 86%" })
  hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.6, bezier = "pomarIn" })
  -- Mover, redimensionar, tela cheia e maximizar (~380 ms, sem quique).
  hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.8, bezier = "pomarZoom" })
  hl.animation({ leaf = "workspaces", enabled = true, speed = 4.6, bezier = "pomarOut", style = "slide" })
  hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "pomarOut", style = "slidevert" })
  hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2.4, bezier = "pomarOut" })
  hl.animation({ leaf = "fadeShadow", enabled = true, speed = 2.4, bezier = "pomarOut" })

  hl.config({
    decoration = {
      rounding = 12,
      rounding_power = 3.0,
      blur = { enabled = true, size = 12, passes = 3, vibrancy = 0.22, noise = 0.012, popups = true },
      shadow = {
        enabled = true, range = 32, render_power = 3, offset = { 0, 8 },
        color = "rgba(0000004d)", color_inactive = "rgba(00000026)",
      },
    },
    general = { gaps_in = 5, gaps_out = 10, border_size = 1 },
  })

  -- Desfoque atrás das superfícies do Pomarchy. ignore_alpha deixa de fora as
  -- áreas transparentes e as sombras, só o vidro recebe o desfoque.
  hl.layer_rule({ match = { namespace = "^pomar-(dock|menu|switcher|tooltip)$" }, blur = true, ignore_alpha = 0.3, no_anim = true })
  hl.layer_rule({ match = { namespace = "^pomar-settings$" }, blur = true, ignore_alpha = 0.02, no_anim = true })
  -- Launchpad e Mission Control desenham o próprio fundo opaco (papel de parede),
  -- então desfocar o que está atrás seria trabalho de GPU jogado fora.
  hl.layer_rule({ match = { namespace = "^pomar-(launchpad|mission)$" }, no_anim = true })
end

function M.apply_input(settings)
  hl.config({
    input = {
      -- Rolagem "natural" e um pouco mais rápida que a do Omarchy (0.4), perto
      -- da sensação do trackpad do Mac. O que a pessoa puser em hypr/input.lua vence.
      touchpad = { natural_scroll = true, clickfinger_behavior = true, disable_while_typing = true, scroll_factor = 0.6 },
    },
    gestures = {
      workspace_swipe_distance = 360,
      workspace_swipe_cancel_ratio = 0.3,
      workspace_swipe_min_speed_to_force = 20,
      workspace_swipe_create_new = false,
      workspace_swipe_forever = false,
    },
  })

  local g = settings.gestures
  if not g.enabled then return end

  hl.gesture({ fingers = fingers(g.spacesFingers, 3), direction = "horizontal", action = "workspace" })
  if settings.mission.enabled then
    hl.gesture({ fingers = fingers(g.missionFingers, 3), direction = "vertical", action = live("mission") })
  end
  if g.launchpadPinch and settings.launchpad.enabled then
    hl.gesture({ fingers = 4, direction = "pinch", action = live("launchpad") })
  end
end

-- Alternador de apps (o Cmd+Tab do Mac) no ALT+TAB: no teclado de PC o Alt
-- fica onde o Cmd fica no Mac, então a mão de quem vem do Mac já vai para lá,
-- e o SUPER+TAB continua sendo o "próxima mesa" do Omarchy. ALT+TAB abre e
-- avança, soltar o ALT escolhe. Um submapa segura as teclas enquanto o alternador está aberto. Sem
-- "catchall" de propósito: ele pegaria o SHIFT de ALT+SHIFT+TAB. As saídas
-- são soltar o ALT, ESC, ENTER, o clique no alternador e um tempo-limite no
-- próprio plugin, que também devolve o submapa ao normal.
function M.apply_switcher()
  local function enter(verb)
    return function()
      emit("switcher:" .. verb)
      hl.dispatch(hl.dsp.submap("pomar-switcher"))
    end
  end

  hl.define_submap("pomar-switcher", function()
    local function stay(verb)
      return function() emit("switcher:" .. verb) end
    end
    local function leave(verb)
      return function()
        emit("switcher:" .. verb)
        hl.dispatch(hl.dsp.submap("reset"))
      end
    end
    hl.bind("ALT + TAB", stay("next"), { repeating = true })
    hl.bind("ALT + SHIFT + TAB", stay("prev"), { repeating = true })
    hl.bind("ALT + grave", stay("prev"), { repeating = true })
    hl.bind("ALT + RIGHT", stay("next"), { repeating = true })
    hl.bind("ALT + LEFT", stay("prev"), { repeating = true })
    hl.bind("ALT + Q", stay("quit"))
    -- Soltar o ALT confirma. release + transparent é o par que o Hyprland usa
    -- para Alt+Tab: dispara no soltar e nenhum outro atalho encobre.
    hl.bind("ALT + Alt_L", leave("commit"), { release = true, transparent = true })
    hl.bind("ALT + Alt_R", leave("commit"), { release = true, transparent = true })
    hl.bind("Alt_L", leave("commit"), { release = true, transparent = true })
    hl.bind("Alt_R", leave("commit"), { release = true, transparent = true })
    hl.bind("ALT + RETURN", leave("commit"))
    hl.bind("RETURN", leave("commit"))
    hl.bind("ALT + ESCAPE", leave("cancel"))
    hl.bind("ESCAPE", leave("cancel"))
  end)

  -- Substitui o "focar próxima janela" do Omarchy, que o alternador já faz
  -- mostrando os apps. Vem depois do submapa: se ele falhar, nada entra nele.
  o.rebind("ALT + TAB", "Alternar entre apps", enter("next"))
  o.rebind("ALT + SHIFT + TAB", "Alternar entre apps (voltar)", enter("prev"))
end

function M.apply_keys(settings)
  local k = settings.keys
  if k.missionControl and settings.mission.enabled then
    o.bind("SUPER + CTRL + UP", "Mission Control", function() emit("mission:toggle") end)
    o.bind("SUPER + CTRL + DOWN", "Todas as janelas do app", function() emit("mission:expose") end)
  end
  if k.launchpad and settings.launchpad.enabled then
    o.rebind("SUPER + ALT + SPACE", "Launchpad", function() emit("launchpad:toggle") end)
  end
  if k.minimize then
    o.bind("SUPER + M", "Minimizar para o Dock", M.minimize_active)
  end
  if k.dockToggle and settings.dock.enabled then
    o.bind("SUPER + ALT + D", "Ocultar ou mostrar o Dock", function() emit("dock:autohide-toggle") end)
  end
  if k.cmdTab and settings.switcher.enabled then
    M.apply_switcher()
  end
end

-- Altura do espaço em cima de cada janela, onde o Dock desenha os botões de
-- fechar, minimizar e zoom (WindowControls.qml usa o mesmo valor).
M.TITLE_GAP = 28

-- A config da pessoa (hypr/looknfeel.lua) carrega depois do Pomarchy e pode
-- definir os espaços entre janelas. Terminada a carga, só o lado de cima cresce
-- até caber os botões; os outros lados ficam como a pessoa quis.
function M.ensure_title_gap()
  if not hl.get_config then return end
  local inner, outer = hl.get_config("general.gaps_in"), hl.get_config("general.gaps_out")
  if type(inner) ~= "table" or type(outer) ~= "table" then return end
  local top_in = math.max(inner.top or 0, M.TITLE_GAP - (inner.bottom or 0))
  local top_out = math.max(outer.top or 0, M.TITLE_GAP)
  if top_in == inner.top and top_out == outer.top then return end
  hl.config({ general = {
    gaps_in = { top = top_in, right = inner.right, bottom = inner.bottom, left = inner.left },
    gaps_out = { top = top_out, right = outer.right, bottom = outer.bottom, left = outer.left },
  } })
end

function M.apply(settings)
  M.apply_look()
  M.apply_input(settings)
  M.apply_keys(settings)
  if settings.windowControls.enabled and hl.timer then
    hl.timer(M.ensure_title_gap, { timeout = 1, type = "oneshot" })
  end
end

function M.run()
  local settings = M.load_settings(home .. "/.config/pomar/settings.json")
  local theme = M.current_theme()
  M.active = M.is_active(theme, settings)
  if M.active then
    M.apply(settings)
  elseif hl.timer then
    -- Depois de a config terminar de carregar, não no meio dela.
    hl.timer(M.release_minimized, { timeout = 250, type = "oneshot" })
  end
  return M.active
end

if type(hl) == "table" and not _G.POMAR_NO_AUTORUN then
  M.run()
end

return M
