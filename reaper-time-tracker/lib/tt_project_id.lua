-- lib/tt_project_id.lua
--
-- Milestone 2: Project identity module.
-- Handles tracking the active project, generating/reading persistent GUIDs
-- via ExtState, and detecting file operations (First Save, Save As) to ensure
-- the tracked identity remains accurate.

local project_id = {}

local EXT_SEC = "TimeTracker"
local EXT_KEY = "ProjectGUID"

local active_project_ptr = nil
local active_project_path = ""
local active_project_guid = nil

-- Generates a REAPER GUID and strips the enclosing braces
-- (e.g. "{123...}" -> "123...") so it can be used cleanly as a JSON key.
local function generate_clean_guid()
  local guid = reaper.genGuid()
  return guid:gsub("{", ""):gsub("}", "")
end

-- Extracts the filename from a full path for display purposes
local function get_display_name(path)
  if path == "" then return "Unsaved Project" end
  return path:match("([^/\\]+)$") or path
end

-- Called every tracking poll to resolve the current project identity.
-- Returns:
--   has_tab_changed (boolean) - true if the user switched project tabs
--   current_guid (string) - the active GUID for tracking
--   display_name (string) - the filename or "Unsaved Project"
--   migrated_from_guid (string|nil) - the old temp GUID if a First Save occurred
function project_id.update()
  local current_ptr, current_path = reaper.EnumProjects(-1, "")
  local migrated_from_guid = nil
  local has_tab_changed = false

  -- CASE 1: Tab switch (or initial script load)
  if current_ptr ~= active_project_ptr then
    has_tab_changed = true
    active_project_ptr = current_ptr
    active_project_path = current_path
    
    if current_path == "" then
      -- Unsaved project: generate a temporary session GUID in memory only
      active_project_guid = "TEMP-" .. generate_clean_guid()
    else
      -- Saved project: Read existing GUID or initialize a new one immediately
      local has_ext, guid = reaper.GetProjExtState(current_ptr, EXT_SEC, EXT_KEY)
      if has_ext == 1 and guid ~= "" then
        active_project_guid = guid
      else
        active_project_guid = generate_clean_guid()
        reaper.SetProjExtState(current_ptr, EXT_SEC, EXT_KEY, active_project_guid)
      end
    end

  -- CASE 2: Same project tab, but the path changed (Save / Save As)
  elseif current_path ~= active_project_path then
    
    if active_project_path == "" then
      -- First Save: The project went from "" (unsaved) to a real path.
      migrated_from_guid = active_project_guid
      active_project_guid = generate_clean_guid()
      reaper.SetProjExtState(current_ptr, EXT_SEC, EXT_KEY, active_project_guid)
      reaper.ShowConsoleMsg(string.format(
        "[TimeTracker] First Save detected. Migrated %s -> %s\n", 
        migrated_from_guid, active_project_guid
      ))
    else
      -- Save As: The project went from one valid path to another.
      -- Explicitly overwrite the ExtState GUID to ensure the duplicate 
      -- doesn't continue logging time to the original file's GUID.
      reaper.ShowConsoleMsg("[TimeTracker] Save As detected. Forcing new GUID.\n")
      active_project_guid = generate_clean_guid()
      reaper.SetProjExtState(current_ptr, EXT_SEC, EXT_KEY, active_project_guid)
    end
    
    active_project_path = current_path
  end

  local display_name = get_display_name(current_path)

  return has_tab_changed, active_project_guid, display_name, migrated_from_guid
end

return project_id