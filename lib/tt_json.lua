-- lib/tt_json.lua
-- Lightweight JSON encode/decode for TimeTracker.

local json = {}

local function escape_str(s)
  local escape_char_map = { ["\\"] = "\\", ["\""] = "\"", ["\b"] = "b", ["\f"] = "f", ["\n"] = "n", ["\r"] = "r", ["\t"] = "t" }
  return '"' .. s:gsub('[%c\\"]', function(c) return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte())) end) .. '"'
end

function json.encode(val)
  local t = type(val)
  if t == "number" or t == "boolean" then
    return tostring(val)
  elseif t == "string" then
    return escape_str(val)
  elseif t == "table" then
    local is_array, max = true, 0
    for k, v in pairs(val) do
      if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then is_array = false break end
      if k > max then max = k end
    end
    if is_array and max > 0 then
      local parts = {}
      for i = 1, max do parts[i] = json.encode(val[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(val) do
        if v ~= nil then table.insert(parts, escape_str(tostring(k)) .. ":" .. json.encode(v)) end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

-- Compact Recursive Descent JSON Decoder
local function parse(str, pos)
  while true do
    local c = str:sub(pos, pos)
    if c == " " or c == "\n" or c == "\r" or c == "\t" then pos = pos + 1 else break end
  end
  
  local c = str:sub(pos, pos)
  if c == "{" then
    local obj = {}
    pos = pos + 1
    while true do
      while str:sub(pos, pos):match("[%s\r\n]") do pos = pos + 1 end
      if str:sub(pos, pos) == "}" then return obj, pos + 1 end
      
      local key, next_pos = parse(str, pos)
      pos = next_pos
      while str:sub(pos, pos):match("[%s\r\n:]") do pos = pos + 1 end
      
      local val, next_pos2 = parse(str, pos)
      obj[key] = val
      pos = next_pos2
      
      while str:sub(pos, pos):match("[%s\r\n]") do pos = pos + 1 end
      if str:sub(pos, pos) == "," then pos = pos + 1 end
    end
  elseif c == "[" then
    local arr = {}
    pos = pos + 1
    local i = 1
    while true do
      while str:sub(pos, pos):match("[%s\r\n]") do pos = pos + 1 end
      if str:sub(pos, pos) == "]" then return arr, pos + 1 end
      
      local val, next_pos = parse(str, pos)
      arr[i] = val
      i = i + 1
      pos = next_pos
      
      while str:sub(pos, pos):match("[%s\r\n]") do pos = pos + 1 end
      if str:sub(pos, pos) == "," then pos = pos + 1 end
    end
  elseif c == '"' then
    local val = ""
    pos = pos + 1
    while true do
      local ch = str:sub(pos, pos)
      if ch == '"' then return val, pos + 1
      elseif ch == "\\" then
        pos = pos + 1
        local esc = str:sub(pos, pos)
        if esc == "n" then val = val .. "\n" elseif esc == "t" then val = val .. "\t"
        elseif esc == "r" then val = val .. "\r" else val = val .. esc end
        pos = pos + 1
      else
        val = val .. ch
        pos = pos + 1
      end
    end
  elseif c:match("[%-%d]") then
    local s = pos
    while str:sub(pos, pos):match("[%-%d%.eE%+]") do pos = pos + 1 end
    return tonumber(str:sub(s, pos - 1)), pos
  elseif str:sub(pos, pos+3) == "true" then return true, pos + 4
  elseif str:sub(pos, pos+4) == "false" then return false, pos + 5
  elseif str:sub(pos, pos+3) == "null" then return nil, pos + 4
  else error("JSON parse error") end
end

function json.decode(str)
  local ok, val = pcall(parse, str, 1)
  if ok then return val else return nil end
end

return json