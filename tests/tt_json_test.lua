-- tests/tt_json_test.lua
--
-- Automated round-trip tests for lib/tt_json.lua. Pure Lua, no REAPER
-- dependency, so it runs outside REAPER: `lua tests/tt_json_test.lua`

local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "../lib/?.lua;" .. package.path

local json = require("tt_json")

local failures = 0

local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
  else
    print("PASS " .. name)
  end
end

-- Scalars
check("encode number", json.encode(42), "42")
check("encode true", json.encode(true), "true")
check("encode string", json.encode("hi"), '"hi"')
check("encode escapes control chars", json.encode("a\nb\"c"), '"a\\nb\\"c"')

-- Array vs. object detection (numeric 1..n keys vs. string keys)
check("encode array", json.encode({ 1, 2, 3 }), "[1,2,3]")

-- Round trip an object shaped like the real tracking_data structure
local original = {
  version = 1,
  last_saved = 1700000000,
  projects = {
    ["abc-123"] = {
      display_name = "Song.RPP",
      total_seconds = 120,
      sessions = {
        {
          start_time = "2024-01-01T10:00:00+00:00",
          end_time = "2024-01-01T10:02:00+00:00",
          duration_seconds = 120,
          _raw_start = 1700000000,
          _raw_end = 1700000120,
        },
      },
    },
  },
}

local decoded = json.decode(json.encode(original))

check("round trip version", decoded.version, original.version)
check("round trip display_name", decoded.projects["abc-123"].display_name,
  original.projects["abc-123"].display_name)
check("round trip session count", #decoded.projects["abc-123"].sessions, 1)
check("round trip duration_seconds", decoded.projects["abc-123"].sessions[1].duration_seconds,
  original.projects["abc-123"].sessions[1].duration_seconds)

-- Failure handling: decode() must return nil rather than raising, since
-- callers (tt_data.load) use a nil return to detect a corrupt data file.
check("decode malformed json returns nil", json.decode("{not valid json"), nil)
check("decode empty object", type(json.decode("{}")), "table")

if failures > 0 then
  print(string.format("\n%d failure(s)", failures))
  os.exit(1)
end
print("\nAll tt_json tests passed.")
