-- TimeTracker_Background.lua
--
-- Milestone 3: In-memory session accumulation
-- Starts/stops timers based on focus and tab changes. Applies the 5s minimum
-- session rule and the 15s merge-gap rule. Handles in-memory data migration
-- during a First Save.

local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "../lib/?.lua;" .. package.path

local tt_deps = require("tt_deps")
local tt_project_id = require("tt_project_id")

-- ── Dependency check ────────────────────────────────────────────────────
if not tt_deps.check_js_reascript_api() then
  tt_deps.warn_missing_js_reascript_api()
  return
end

-- ── Constants ───────────────────────────────────────────────────────────
local FOCUS_POLL_INTERVAL = 1.0
local MIN_SESSION_SEC = 5
local MERGE_GAP_SEC = 15

-- ── State ───────────────────────────────────────────────────────────────
local last_poll_time = 0
local this_instance_hwnd = reaper.GetMainHwnd()

-- Tracking memory
local tracking_data = { projects = {} }
local is_tracking = false
local session_start_time = 0
local session_tracked_guid = nil
local session_tracked_name = ""

-- ── Multi-Instance Helper ───────────────────────────────────────────────
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

  local ancestor = get_top_level_ancestor(foreground_hwnd)
  return ancestor == this_instance_hwnd
end

-- ── Session Accumulation Helpers ────────────────────────────────────────
local function get_or_create_project(guid, display_name)
  if not tracking_data.projects[guid] then
    tracking_data.projects[guid] = {
      display_name = display_name,
      total_seconds = 0,
      sessions = {}
    }
  else
    tracking_data.projects[guid].display_name = display_name
  end
  return tracking_data.projects[guid]
end

local function commit_session(guid, display_name, start_time, end_time)
  local duration = end_time - start_time
  
  if duration < MIN_SESSION_SEC then
    reaper.ShowConsoleMsg(string.format("[TimeTracker] Session discarded (<%ds): %ds\n", MIN_SESSION_SEC, duration))
    return
  end
  
  local proj = get_or_create_project(guid, display_name)
  local sessions = proj.sessions
  local last_session = sessions[#sessions]
  
  -- Merge condition: gap is <= 15 seconds
  if last_session and (start_time - last_session.end_time) <= MERGE_GAP_SEC then
    local added_duration = end_time - last_session.end_time
    last_session.end_time = end_time
    last_session.duration = last_session.end_time - last_session.start_time
    proj.total_seconds = proj.total_seconds + added_duration
    reaper.ShowConsoleMsg(string.format("[TimeTracker] Session merged (gap <=%ds). Added %ds. Total: %ds\n", 
      MERGE_GAP_SEC, added_duration, proj.total_seconds))
  else
    -- New session
    table.insert(sessions, {
      start_time = start_time,
      end_time = end_time,
      duration = duration
    })
    proj.total_seconds = proj.total_seconds + duration
    reaper.ShowConsoleMsg(string.format("[TimeTracker] Session logged: %ds on %s. Total: %ds\n", 
      duration, display_name, proj.total_seconds))
  end
end

-- ── Main loop ───────────────────────────────────────────────────────────
local function main()
  local now = reaper.time_precise()

  if now - last_poll_time >= FOCUS_POLL_INTERVAL then
    last_poll_time = now
    
    local focused = is_this_instance_focused()
    local has_tab_changed, current_guid, display_name, migrated_guid = tt_project_id.update()
    
    -- Handle first-save migration in memory
    if migrated_guid and tracking_data.projects[migrated_guid] then
      tracking_data.projects[current_guid] = tracking_data.projects[migrated_guid]
      tracking_data.projects[current_guid].display_name = display_name
      tracking_data.projects[migrated_guid] = nil
      
      -- If the active timer was running on the temp GUID, migrate the live timer too
      if is_tracking and session_tracked_guid == migrated_guid then
        session_tracked_guid = current_guid
        session_tracked_name = display_name
      end
      reaper.ShowConsoleMsg("[TimeTracker] Migrated past sessions from temporary GUID to real GUID.\n")
    end
    
    local should_track = focused and current_guid ~= nil
    local current_time = os.time()
    
    -- Evaluate stop condition
    if is_tracking then
      -- Stop tracking if we lost focus, or if the focus remained but the tab changed
      if not should_track or has_tab_changed then
        commit_session(session_tracked_guid, session_tracked_name, session_start_time, current_time)
        is_tracking = false
        reaper.ShowConsoleMsg("[TimeTracker] Tracking paused.\n")
      end
    end
    
    -- Evaluate start condition
    if not is_tracking and should_track then
      session_start_time = current_time
      session_tracked_guid = current_guid
      session_tracked_name = display_name
      is_tracking = true
      reaper.ShowConsoleMsg(string.format("[TimeTracker] Tracking started for: %s\n", display_name))
    end
  end

  reaper.defer(main)
end

reaper.ClearConsole()
reaper.ShowConsoleMsg("[TimeTracker] Started. Polling foreground and session state.\n")
main()