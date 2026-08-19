-- TimeTracker_EmailReport.lua
--
-- Milestone 8: Email handoff.
-- Standalone action: emails the existing report without regenerating it.
-- Use when re-sending to a second client, or resending after a bounce.
--
-- Read-only, and has zero dependency on js_ReaScriptAPI. All corrupt-file
-- quarantining is left to TimeTracker_GenerateReport.lua.

local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "../lib/?.lua;" .. package.path

local tt_data = require("tt_data")
local tt_email = require("tt_email")

local function main()
  local data, message, kind = tt_data.load()

  if not data then
    if kind == "corrupt" then
      message = message .. "\n\nRun Generate Report first -- it will set the "
        .. "corrupted file aside for inspection."
    end
    reaper.ShowMessageBox(message, "TimeTracker - Email Report", 0)
    return
  end

  -- Confidentiality gate: an email to one client must not disclose other
  -- clients' project names and hours.
  data = tt_data.prompt_for_scope(data, "TimeTracker - Report Scope")
  if not data then return end

  tt_email.compose(data)
end

main()
