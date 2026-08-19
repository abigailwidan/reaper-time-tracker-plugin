-- lib/tt_data.lua
--
-- Single implementation of PLAN.md's "Tracker <-> Report Interface" read side,
-- shared by the report generator and the email action so the two can't drift.
--
-- Read-only: this module never writes, renames, or deletes anything. Callers
-- decide what to do about a corrupt file. Only the report generator quarantines
-- it, so two scripts can never race to rename the same file.

local tt_paths = require("tt_paths")
local tt_json = require("tt_json")

local data_mod = {}

data_mod.EXPECTED_VERSION = 1

-- Returns: data (table|nil), message (string|nil), kind (string|nil)
--   kind is one of "missing", "empty", "corrupt", "version"
function data_mod.load()
  local f = io.open(tt_paths.get_data_file(), "r")
  if not f then
    return nil,
      "No time tracking data found yet. Track some active project time first!",
      "missing"
  end

  local content = f:read("*a")
  f:close()

  if content == "" then
    return nil, "Time data file is empty.", "empty"
  end

  local data = tt_json.decode(content)
  if not data or type(data) ~= "table" then
    return nil, "The data file could not be parsed.", "corrupt"
  end

  if data.version ~= data_mod.EXPECTED_VERSION then
    return nil, string.format(
      "This report expects data version %d but found version %s. Update "
        .. "TimeTracker_GenerateReport.lua to match, or restore an older backup "
        .. "of time_data.json.",
      data_mod.EXPECTED_VERSION, tostring(data.version)), "version"
  end

  return data
end

-- True if at least one project exists in the data set.
function data_mod.has_content(data)
  for _ in pairs(data.projects or {}) do return true end
  return false
end

-- Number of projects in the data set.
function data_mod.project_count(data)
  local n = 0
  for _ in pairs(data.projects or {}) do n = n + 1 end
  return n
end

-- Returns the GUID of the currently active REAPER project, or nil if it has
-- none recorded yet (unsaved, or never tracked). Uses GetProjExtState against
-- project 0 (the active project), so this stays free of js_ReaScriptAPI.
function data_mod.active_project_guid()
  if not reaper.GetProjExtState then return nil end
  local ok, guid = reaper.GetProjExtState(0, "TimeTracker", "ProjectGUID")
  if ok == 1 and guid ~= "" then return guid end
  return nil
end

-- Returns a copy of `data` containing only the named project.
--
-- This is a confidentiality control, not a convenience. A report sent to one
-- client must not disclose the existence, names, or hours of other clients'
-- projects, which a whole-file report would do.
function data_mod.scope_to_project(data, guid)
  local proj = (data.projects or {})[guid]
  if not proj then return nil end
  return {
    version = data.version,
    last_saved = data.last_saved,
    projects = { [guid] = proj },
  }
end

-- Asks the user whether to include every project or only the active one.
-- Skipped entirely when there is nothing to disambiguate.
--
-- Returns: scoped data (table|nil). nil means the user cancelled.
function data_mod.prompt_for_scope(data, dialog_title)
  if data_mod.project_count(data) < 2 then return data end

  local active_guid = data_mod.active_project_guid()
  if not active_guid or not (data.projects or {})[active_guid] then
    -- Nothing sensible to narrow to; fall through to the full data set.
    return data
  end

  local name = data.projects[active_guid].display_name or "the active project"

  -- 3 = Yes/No/Cancel. 6 = Yes, 7 = No, 2 = Cancel.
  local answer = reaper.ShowMessageBox(
    "This data file contains " .. data_mod.project_count(data) .. " projects.\n\n"
      .. "Include ALL projects?\n\n"
      .. "Yes  -  include every project\n"
      .. "No   -  include only " .. name .. "\n\n"
      .. "Sending a report covering all projects will disclose your other "
      .. "clients' project names and hours to the recipient.",
    dialog_title, 3)

  if answer == 2 then return nil end
  if answer == 7 then return data_mod.scope_to_project(data, active_guid) end
  return data
end

return data_mod
