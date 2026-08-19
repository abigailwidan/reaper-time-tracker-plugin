-- lib/tt_project_id.lua
--
-- Purpose: Manage project identity and lifecycle tracking.
--
-- This module is responsible for:
--   - Assigning and persisting unique GUIDs to each project via REAPER's ExtState
--   - Detecting project tab switches (has_tab_changed)
--   - Detecting file operations: First Save (unsaved → saved) and Save As (path change)
--   - Handling temporary session GUIDs for unsaved projects
--   - Migrating accumulated time data when a project is first saved
--
-- Key Design:
--   - Unsaved projects receive temporary in-memory GUIDs (prefixed "TEMP-")
--   - Saved projects receive persistent GUIDs stored in ExtState
--   - ExtState key: project's "TimeTracker" section, "ProjectGUID" attribute
--   - On file operations, returns a "migrated_from_guid" to facilitate data migration
--
-- Dependencies: REAPER API (reaper.EnumProjects, reaper.genGuid, ExtState functions)

local project_id = {}

local EXT_SEC = "TimeTracker"
local EXT_KEY = "ProjectGUID"

local active_project_ptr = nil
local active_project_path = ""
local active_project_guid = nil

-- Generates a fresh GUID and strips braces for clean JSON key compatibility.
-- REAPER's reaper.genGuid() returns "{...}", but JSON keys work better without braces.
local function generate_clean_guid()
  local guid = reaper.genGuid()
  return guid:gsub("{", ""):gsub("}", "")
end

-- Extracts human-readable project name from file path.
-- Returns the filename for saved projects, or "Unsaved Project" if the path is empty.
local function get_display_name(path)
  if path == "" then return "Unsaved Project" end
  return path:match("([^/\\]+)$") or path
end

-- Core polling function: updates and returns the current project identity state.
--
-- Called on every tracking poll (nominally ~1 second) to detect:
--   1. Tab switches (different project pointer)
--   2. First Save (empty path → real path, generates new GUID)
--   3. Save As (path change, forces new GUID to avoid duplicates)
--
-- Returns (in order):
--   has_tab_changed (boolean) - true if project pointer changed
--   current_guid (string) - active GUID for this tracking cycle
--   display_name (string) - human-readable project name
--   migrated_from_guid (string|nil) - old GUID if migration occurred (for data relocation)
--
-- Side effects:
--   - Updates ExtState with GUID for saved projects
--   - Logs file operations to console
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