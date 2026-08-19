-- lib/tt_json.lua
--
-- Purpose: Pure-Lua JSON encoder and decoder (no external dependencies).
--
-- This is a vendored, minimal JSON implementation tailored for TimeTracker's
-- data serialization needs. It avoids external JSON libraries to keep the
-- plugin lightweight and self-contained.
--
-- Features:
--   - Encodes: Lua tables (objects/arrays), strings, numbers, booleans, nil
--   - Decodes: Parses JSON strings back into Lua tables
--   - Automatic array detection: numeric keys → JSON arrays, string keys → JSON objects
--   - Escape handling: Properly encodes special characters (\n, \t, \r, etc.)
--   - Error handling: Silently returns nil if JSON parse fails
--
-- Usage:
--   local data = { name = "Project", duration = 3600, active = true }
--   local json_str = json.encode(data)  -- {"name":"Project","duration":3600,"active":true}
--   local restored = json.decode(json_str)  -- Back to Lua table
--
-- Limitations:
--   - Does NOT handle cyclic tables (will infinite loop)
--   - Numbers are stored as Lua floats (potential precision loss for very large integers)

local json = {}

-- Helper: Escapes a string for JSON representation.
-- Handles special chars: newlines, tabs, quotes, backslashes, control characters.
-- Unmapped control chars are encoded as \uXXXX hex escapes.
local function escape_str(s)
  local escape_char_map = { ["\\"] = "\\", ["\""] = "\"", ["\b"] = "b", ["\f"] = "f", ["\n"] = "n", ["\r"] = "r", ["\t"] = "t" }
  return '"' .. s:gsub('[%c\\"]', function(c) return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte())) end) .. '"'
end

-- Encodes a Lua value into a JSON string.
-- Recursively handles tables, strings, numbers, booleans, nil.
-- Automatically detects whether a table should be encoded as a JSON array or object.
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

-- Compact recursive descent JSON parser.
-- Implements a minimal state machine to tokenize and parse JSON.
-- Returns: (parsed_value, next_position_in_string)
-- Does NOT support JSON5 extensions (trailing commas, unquoted keys, etc.).
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

-- Public API: Decode a JSON string into a Lua value.
-- Returns the parsed Lua value on success, or nil if parsing fails (catches exceptions safely).
-- Use with TimeTracker data files to restore session records on startup.
function json.decode(str)
  local ok, val = pcall(parse, str, 1)
  if ok then return val else return nil end
end

return json