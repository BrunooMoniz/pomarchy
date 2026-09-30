-- Dublê da API Lua do Hyprland para testar hypr/pomar.lua fora do compositor.
-- Registra cada chamada; o teste em Python lê o resultado em JSON.
local calls = { gestures = {}, binds = {}, unbinds = {}, submaps = {}, layer_rules = {}, curves = {},
                animations = {}, configs = {}, dispatches = {}, events = {}, timers = {} }
local current_submap = nil

local function record_dispatch(value) table.insert(calls.dispatches, value) end

hl = {
  dsp = {
    event = function(msg) return { kind = "event", msg = msg } end,
    submap = function(name) return { kind = "submap", name = name } end,
    exec_cmd = function(cmd) return { kind = "exec", cmd = cmd } end,
    window = { move = function(t) return { kind = "move", args = t } end },
  },
  dispatch = function(d) record_dispatch(d) end,
  gesture = function(t) table.insert(calls.gestures, t) end,
  bind = function(keys, action, opts)
    table.insert(calls.binds, { keys = keys, submap = current_submap, opts = opts or {}, action = action })
  end,
  unbind = function(keys) table.insert(calls.unbinds, keys) end,
  define_submap = function(name, fn)
    local previous = current_submap
    current_submap = name
    fn()
    current_submap = previous
    table.insert(calls.submaps, name)
  end,
  layer_rule = function(t) table.insert(calls.layer_rules, t) end,
  curve = function(name, t) calls.curves[name] = t end,
  animation = function(t) table.insert(calls.animations, t) end,
  config = function(t) table.insert(calls.configs, t) end,
  on = function(name) table.insert(calls.events, name) end,
  -- Temporizador do dublê roda na hora: o teste vê o efeito sem esperar.
  timer = function(fn, opts) table.insert(calls.timers, opts or {}); fn() end,
  get_windows = function() return FAKE_WINDOWS or {} end,
  -- Espaços entre janelas como a config da pessoa deixou (cenários de run.lua).
  get_config = function(key)
    local fake = FAKE_CONFIG or {
      ["general.gaps_in"] = { top = 5, right = 5, bottom = 5, left = 5 },
      ["general.gaps_out"] = { top = 10, right = 10, bottom = 10, left = 10 },
    }
    return fake[key]
  end,
  get_active_workspace = function() return { id = 3, name = "3" } end,
  get_active_window = function() return FAKE_ACTIVE end,
}

-- o.* do Omarchy (default/hypr/helpers.lua), só o que o pomar.lua usa.
o = {
  bind = function(keys, description, dispatcher, options)
    local opts = options or {}
    opts.description = description
    hl.bind(keys, dispatcher, opts)
  end,
}
o.rebind = function(keys, description, dispatcher, options)
  hl.unbind(keys)
  o.bind(keys, description, dispatcher, options)
end

local function encode(value, seen)
  local t = type(value)
  if t == "nil" then return "null" end
  if t == "boolean" or t == "number" then return tostring(value) end
  if t == "string" then return (string.format("%q", value):gsub("\\\n", "\\n")) end
  if t == "function" then return '"<function>"' end
  if t == "table" then
    seen = seen or {}
    if seen[value] then return '"<cycle>"' end
    seen[value] = true
    local is_list = #value > 0 or next(value) == nil
    local parts = {}
    if is_list then
      for _, v in ipairs(value) do table.insert(parts, encode(v, seen)) end
      seen[value] = nil
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(value) do table.insert(keys, tostring(k)) end
    table.sort(keys)
    for _, k in ipairs(keys) do table.insert(parts, string.format("%q", k) .. ":" .. encode(value[k], seen)) end
    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return '"<' .. t .. '>"'
end

return { calls = calls, encode = encode }
