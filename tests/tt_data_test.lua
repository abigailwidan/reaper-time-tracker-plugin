-- tests/tt_data_test.lua
--
-- Automated tests for the REAPER-free parts of lib/tt_data.lua: has_content,
-- project_count, and scope_to_project. The remaining functions (load,
-- active_project_guid, prompt_for_scope) call into the reaper.* API and need
-- a live REAPER instance -- see reascript_sandbox_test.lua for those.
--
-- Run directly with: lua tests/tt_data_test.lua

local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "../lib/?.lua;" .. package.path

local tt_data = require("tt_data")

local failures = 0

local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
  else
    print("PASS " .. name)
  end
end

local empty_data = { version = 1, projects = {} }
check("has_content: empty data set", tt_data.has_content(empty_data), false)
check("project_count: empty data set", tt_data.project_count(empty_data), 0)

local multi_project_data = {
  version = 1,
  last_saved = 1700000000,
  projects = {
    ["guid-a"] = { display_name = "ClientA_Mix.RPP", total_seconds = 3600, sessions = {} },
    ["guid-b"] = { display_name = "ClientB_Master.RPP", total_seconds = 1800, sessions = {} },
  },
}

check("has_content: populated data set", tt_data.has_content(multi_project_data), true)
check("project_count: two projects", tt_data.project_count(multi_project_data), 2)

-- scope_to_project is the confidentiality boundary a client-facing report
-- relies on: it must isolate exactly the requested project and nothing else,
-- while still carrying the file-level metadata along with it.
local scoped = tt_data.scope_to_project(multi_project_data, "guid-a")
check("scope_to_project: keeps requested project", scoped.projects["guid-a"] ~= nil, true)
check("scope_to_project: drops other project", scoped.projects["guid-b"], nil)
check("scope_to_project: preserves version", scoped.version, multi_project_data.version)
check("scope_to_project: preserves last_saved", scoped.last_saved, multi_project_data.last_saved)
check("scope_to_project: unknown guid returns nil",
  tt_data.scope_to_project(multi_project_data, "no-such-guid"), nil)

if failures > 0 then
  print(string.format("\n%d failure(s)", failures))
  os.exit(1)
end
print("\nAll tt_data tests passed.")
