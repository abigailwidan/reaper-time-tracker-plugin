-- TimeTracker_Background.lua
--
-- Milestone 4: JSON Persistence
-- Adds atomic periodic writes every 45s and formats the schema correctly.

local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "../lib/?.lua;" .. package.path

local tt_deps = require("tt_deps")
local tt_project_id = require("tt_project_id")
local tt_paths = require("tt_paths")
local tt_json = require("tt_json")

-- ── Dependency check ────────────────────────────────────────────────────
if not tt_deps.check_js_reascript_api() then
  tt_deps.warn_missing_js_reascript_api()
  return
end

-- ── Constants ───────────────────────────────────────────────────────────
local FOCUS_POLL_INTERVAL = 1.0
local MIN_SESSION_SEC = 5
local MERGE_GAP_SEC = 15
local AUTOSAVE_INTERVAL = 45.0 -- Fixed 45s autosave

-- ── State ───────────────────────────────────────────────────────────────
local last_poll_time = 0
local last_save_time = reaper.time_precise()
local this_instance_hwnd = reaper.GetMainHwnd()
local tracking_data = { version = 1, projects = {} }
local is_tracking = false
local session_start_time = 0
local session_tracked_guid = nil
local session_tracked_name = ""
local session_tracked_path = ""

-- ── Utilities ───────────────────────────────────────────────────────────
local function get_top_level_ancestor(hwnd)
  if not hwnd then return nil end
  local root = reaper.JS_Window_GetRelated(hwnd, "ROOT")
  if root then return root end
  local current = hwnd
  while true do
    local parent = reaper.JS_Window_GetParent(current)
    if not parent then break end
    current = parent
  end
  return current
end

local function is_this_instance_focused()
  local foreground_hwnd = reaper.JS_Window_GetForeground()
  if not foreground_hwnd then return false end
  return get_top_level_ancestor(foreground_hwnd) == this_instance_hwnd
end

local function format_iso8601(timestamp)
  local t = os.date("%Y-%m-%dT%H:%M:%S", timestamp)
  local tz = os.date("%z", timestamp)
  if tz == "Z" or tz == "z" then
    tz = "+00:00"
  else
    tz = tz:sub(1,3) .. ":" .. tz:sub(4,5)
  end
  return t .. tz
end

-- ── Disk I/O (Atomic Write) ─────────────────────────────────────────────
local function save_data_to_disk()
  tt_paths.ensure_dir()
  local temp_file = tt_paths.get_temp_file()
  local data_file = tt_paths.get_data_file()
  
  local json_str = tt_json.encode(tracking_data)
  
  local f = io.open(temp_file, "w")
  if not f then return end
  f:write(json_str)
  f:close()
  
  -- Atomic rename (delete existing first for Windows compatibility)
  os.remove(data_file)
  os.rename(temp_file, data_file)
  
  reaper.ShowConsoleMsg(string.format("[TimeTracker] Autosaved to disk at %s\n", os.date("%H:%M:%S")))
end

-- Hook save on script exit (clean exit)
reaper.atexit(save_data_to_disk)

-- ── Session Accumulation ────────────────────────────────────────────────
local function get_or_create_project(guid, display_name, path)
  if not tracking_data.projects[guid] then
    tracking_data.projects[guid] = {
      display_name = display_name,
      last_known_path = path,
      total_seconds = 0,
      sessions = {}
    }
  else
    tracking_data.projects[guid].display_name = display_name
    tracking_data.projects[guid].last_known_path = path
  end
  return tracking_data.projects[guid]
end

local function commit_session(guid, display_name, path, start_time, end_time)
  local duration = end_time - start_time
  if duration < MIN_SESSION_SEC then return end
  
  local proj = get_or_create_project(guid, display_name, path)
  local sessions = proj.sessions
  local last_session = sessions[#sessions]
  
  -- Merge condition
  if last_session and (start_time - last_session._raw_end) <= MERGE_GAP_SEC then
    last_session._raw_end = end_time
    last_session.end_time = format_iso8601(end_time)
    last_session.duration_seconds = end_time - last_session._raw_start
    proj.total_seconds = proj.total_seconds + (end_time - start_time)
  else
    -- New session
    table.insert(sessions, {
      _raw_start = start_time,
      _raw_end = end_time,
      start_time = format_iso8601(start_time),
      end_time = format_iso8601(end_time),
      duration_seconds = duration
    })
    proj.total_seconds = proj.total_seconds + duration
  end
end

-- ── Main loop ───────────────────────────────────────────────────────────
local function main()
  local now = reaper.time_precise()

  if now - last_poll_time >= FOCUS_POLL_INTERVAL then
    last_poll_time = now
    
    local focused = is_this_instance_focused()
    local has_tab_changed, current_guid, display_name, migrated_guid = tt_project_id.update()
    local _, current_path = reaper.EnumProjects(-1, "")
    
    if migrated_guid and tracking_data.projects[migrated_guid] then
      tracking_data.projects[current_guid] = tracking_data.projects[migrated_guid]
      tracking_data.projects[current_guid].display_name = display_name
      tracking_data.projects[current_guid].last_known_path = current_path
      tracking_data.projects[migrated_guid] = nil
      if is_tracking and session_tracked_guid == migrated_guid then
        session_tracked_guid = current_guid
        session_tracked_name = display_name
        session_tracked_path = current_path
      end
    end
    
    local should_track = focused and current_guid ~= nil
    local current_time = os.time()
    
    if is_tracking then
      if not should_track or has_tab_changed then
        commit_session(session_tracked_guid, session_tracked_name, session_tracked_path, session_start_time, current_time)
        is_tracking = false
        reaper.ShowConsoleMsg("[TimeTracker] Tracking paused. Session committed to memory.\n")
      end
    end
    
    if not is_tracking and should_track then
      session_start_time = current_time
      session_tracked_guid = current_guid
      session_tracked_name = display_name
      session_tracked_path = current_path
      is_tracking = true
      reaper.ShowConsoleMsg(string.format("[TimeTracker] Tracking started for: %s\n", display_name))
    end
  end

  -- Autosave Trigger
  if now - last_save_time >= AUTOSAVE_INTERVAL then
    last_save_time = now
    save_data_to_disk()
  end

  reaper.defer(main)
end

reaper.ClearConsole()
reaper.ShowConsoleMsg("[TimeTracker] Started. Persistence active (45s autosave).\n")
main()