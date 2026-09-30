-- Uso: HOME=<tmp> lua5.4 tests/lua/run.lua <repo> <cenário>
-- Cenários: "load" (carrega pomar.lua como o Hyprland faria e imprime as chamadas),
-- "defaults" (só imprime M.DEFAULTS), "gesture:<alvo>" (roda start/update/finish
-- do gesto ao vivo e imprime os eventos), "json:<texto>" (decodifica com json.lua).
local repo, scenario = arg[1], arg[2] or "load"
package.path = repo .. "/tests/lua/?.lua;" .. package.path
local harness = dofile(repo .. "/tests/lua/harness.lua")

if scenario == "defaults" then
  _G.POMAR_NO_AUTORUN = true
  local M = dofile(repo .. "/hypr/pomar.lua")
  print(harness.encode(M.DEFAULTS))
  return
end

if scenario:sub(1, 5) == "json:" then
  local json = dofile(repo .. "/hypr/json.lua")
  local value = json.decode(scenario:sub(6))
  print(harness.encode({ ok = value ~= nil, value = value }))
  return
end

if scenario == "usergaps" then -- hypr/looknfeel.lua da pessoa: 6 entre janelas, 12 nas bordas
  FAKE_CONFIG = {
    ["general.gaps_in"] = { top = 6, right = 6, bottom = 6, left = 6 },
    ["general.gaps_out"] = { top = 12, right = 12, bottom = 12, left = 12 },
  }
elseif scenario == "roomy" then -- já cabe: nada a mexer
  FAKE_CONFIG = {
    ["general.gaps_in"] = { top = 30, right = 4, bottom = 4, left = 4 },
    ["general.gaps_out"] = { top = 40, right = 8, bottom = 8, left = 8 },
  }
end

if scenario == "release" or scenario == "minimize" then
  FAKE_WINDOWS = {
    { address = "0xaaa", workspace = { name = "special:pomar-minimized", id = -98 } },
    { address = "0xbbb", workspace = { name = "2", id = 2 } },
  }
  FAKE_ACTIVE = { address = "0xccc", at = { x = 10, y = 40 }, size = { x = 800, y = 600 } }
end

local M = dofile(repo .. "/hypr/pomar.lua")

if scenario == "release" or scenario == "minimize" then
  if scenario == "minimize" then
    harness.calls.dispatches = {}
    M.minimize_active()
  end
  local out = {}
  for _, d in ipairs(harness.calls.dispatches) do
    if d.kind == "move" then out[#out + 1] = { move = d.args.window, to = d.args.workspace }
    elseif d.kind == "event" then out[#out + 1] = { event = d.msg } end
  end
  print(harness.encode(out))
  return
end

if scenario:sub(1, 8) == "gesture:" then
  local target = scenario:sub(9)
  local found
  for _, g in ipairs(harness.calls.gestures) do
    if type(g.action) == "table" and ((target == "mission" and g.direction == "vertical") or (target == "launchpad" and g.direction == "pinch")) then found = g end
  end
  if not found then print('{"error":"gesto não registrado"}') return end
  harness.calls.dispatches = {}
  found.action.start({ type = "swipe", fingers = found.fingers, delta = { x = 0, y = 0 } })
  found.action.update({ type = "swipe", fingers = found.fingers, delta = { x = 0.5, y = -12.345 }, scale = 0.8123 })
  found.action.finish({ type = "swipe", cancelled = false })
  found.action.finish({ type = "swipe", cancelled = true })
  local messages = {}
  for _, d in ipairs(harness.calls.dispatches) do table.insert(messages, d.msg) end
  print(harness.encode(messages))
  return
end

print(harness.encode({ active = M.active, calls = harness.calls }))
