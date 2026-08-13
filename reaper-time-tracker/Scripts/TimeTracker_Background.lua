-- TimeTracker_Background.lua
--
-- Milestone 2: Background polling + Project Identity
-- Integrates the lib/tt_project_id module to read/generate GUIDs and track
-- tab switching, Save As, and initial saves.

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

-- ── State ───────────────────────────────────────────────────────────────
local last_poll_time = 0
local this_instance_hwnd = reaper.GetMainHwnd()

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

-- ── Main loop ───────────────────────────────────────────────────────────
local function main()
  local now = reaper.time_precise()

  if now - last_poll_time >= FOCUS_POLL_INTERVAL then
    last_poll_time = now
    
    local focused = is_this_instance_focused()
    
    -- Update project identity and check for state changes
    local has_tab_changed, current_guid, display_name, migrated_guid = tt_project_id.update()
    
    if has_tab_changed then
      reaper.ShowConsoleMsg(string.format(
        "\n[TimeTracker] Tab Switched To: %s (GUID: %s)\n", 
        display_name, current_guid
      ))
    end
    
    -- Print current state to verify polling is working alongside identity tracking
    reaper.ShowConsoleMsg(string.format(
      "[TimeTracker] t=%.1f | focus=%s | proj=%s\n", 
      now, tostring(focused), current_guid
    ))
  end

  reaper.defer(main)
end

reaper.ClearConsole()
reaper.ShowConsoleMsg("[TimeTracker] Started. Polling foreground and project state.\n")
main()