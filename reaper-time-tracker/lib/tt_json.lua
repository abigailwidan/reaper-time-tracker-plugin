-- lib/tt_json.lua
-- Lightweight JSON encode/decode.

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
    -- Check if it's an array
    local is_array = true
    local max = 0
    for k, v in pairs(val) do
      if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then is_array = false break end
      if k > max then max = k end
    end
    if is_array and max > 0 then
      local parts = {}
      for i = 1, max do parts[i] = json.encode(val[i] or json.null) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(val) do table.insert(parts, escape_str(tostring(k)) .. ":" .. json.encode(v)) end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  else
    return "null"
  end
end

-- We will add json.decode in Milestone 5 for Startup Recovery.
return json