-- Leitor de JSON mínimo para os ajustes do Pomarchy, sem dependências.
-- Aceita o que JSON.stringify produz; qualquer erro vira nil e o Pomarchy segue
-- com os padrões, porque um arquivo editado à mão nunca pode travar o Hyprland.

local json = {}

local escapes = {
  ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
  b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}

local function skip(text, i)
  local _, last = text:find("^[ \n\r\t]*", i)
  return last + 1
end

local function utf8char(code)
  if code < 0x80 then return string.char(code) end
  if code < 0x800 then
    return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
  end
  return string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end

local parse_value

local function parse_string(text, i)
  local out, j = {}, i + 1
  while true do
    local c = text:sub(j, j)
    if c == "" then error("texto sem aspas de fechamento") end
    if c == '"' then return table.concat(out), j + 1 end
    if c == "\\" then
      local n = text:sub(j + 1, j + 1)
      if n == "u" then
        local code = tonumber(text:sub(j + 2, j + 5), 16)
        if not code then error("escape \\u inválido") end
        out[#out + 1] = (code >= 0xD800 and code <= 0xDFFF) and "?" or utf8char(code)
        j = j + 6
      elseif escapes[n] then
        out[#out + 1] = escapes[n]
        j = j + 2
      else
        error("escape inválido")
      end
    else
      out[#out + 1] = c
      j = j + 1
    end
  end
end

local function parse_number(text, i)
  local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
  if not number or number == "" or number == "-" then error("número inválido") end
  local value = tonumber(number)
  if value == nil then error("número inválido") end
  return value, i + #number
end

local function parse_array(text, i)
  local out = {}
  i = skip(text, i + 1)
  if text:sub(i, i) == "]" then return out, i + 1 end
  while true do
    local value
    value, i = parse_value(text, i)
    out[#out + 1] = value
    i = skip(text, i)
    local c = text:sub(i, i)
    if c == "]" then return out, i + 1 end
    if c ~= "," then error("esperava , ou ]") end
    i = skip(text, i + 1)
  end
end

local function parse_object(text, i)
  local out = {}
  i = skip(text, i + 1)
  if text:sub(i, i) == "}" then return out, i + 1 end
  while true do
    if text:sub(i, i) ~= '"' then error("esperava nome de chave") end
    local key
    key, i = parse_string(text, i)
    i = skip(text, i)
    if text:sub(i, i) ~= ":" then error("esperava :") end
    local value
    value, i = parse_value(text, skip(text, i + 1))
    out[key] = value
    i = skip(text, i)
    local c = text:sub(i, i)
    if c == "}" then return out, i + 1 end
    if c ~= "," then error("esperava , ou }") end
    i = skip(text, i + 1)
  end
end

parse_value = function(text, i)
  i = skip(text, i)
  local c = text:sub(i, i)
  if c == "{" then return parse_object(text, i) end
  if c == "[" then return parse_array(text, i) end
  if c == '"' then return parse_string(text, i) end
  if text:sub(i, i + 3) == "true" then return true, i + 4 end
  if text:sub(i, i + 4) == "false" then return false, i + 5 end
  if text:sub(i, i + 3) == "null" then return nil, i + 4 end
  return parse_number(text, i)
end

function json.decode(text)
  if type(text) ~= "string" or text == "" then return nil end
  local ok, value, finish = pcall(parse_value, text, 1)
  if not ok then return nil end
  if skip(text, finish) <= #text then return nil end
  return value
end

return json
