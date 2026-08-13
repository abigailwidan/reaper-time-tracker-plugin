-- TimeTracker_Background.lua
--
-- Milestone 1: dependency check + skeleton polling loop.
-- Confirms js_ReaScriptAPI is installed, then polls (throttled to once per
-- second) whether REAPER is the OS-foreground window AND whether that
-- foreground window belongs to *this* REAPER instance. For now this only
-- prints to the console — no project tracking or data writing yet.
--
-- See DOCS.md > Architecture (1. Background tracking loop) and
-- PLAN.md > Timing Constants / Edge Cases (Multiple REAPER instances).

-- Make lib/ requirable relative to this script's own location.
local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "../lib/?.lua;" .. package.path

local tt_deps = require("tt_deps")

-- ── Dependency check ────────────────────────────────────────────────────
-- Must happen before the defer loop is ever registered. If js_ReaScriptAPI
-- is missing, warn and return immediately — no loop, no data, no crash.
if not tt_deps.check_js_reascript_api() then
  tt_deps.warn_missing_js_reascript_api()
  return
end

-- ── Constants ───────────────────────────────────────────────────────────
local FOCUS_POLL_INTERVAL = 1.0 -- seconds; see PLAN.md > Timing Constants

-- ── State ───────────────────────────────────────────────────────────────
local last_poll_time = 0
local this_instance_hwnd = reaper.GetMainHwnd()
local root_method_logged = false -- so we only log which method worked once

-- Walks up from a window handle to its top-level ancestor. Prefers
-- JS_Window_GetRelated(hwnd, "ROOT"); falls back to manually walking
-- JS_Window_GetParent if "ROOT" isn't supported by the installed
-- js_ReaScriptAPI version.
--
-- STATUS: unverified — see "Items to Confirm During Build" in PLAN.md.
-- Logs which path it took so this can be confirmed against real behaviour.
local function get_top_level_ancestor(hwnd)
  if not hwnd then return nil end

  local root = reaper.JS_Window_GetRelated(hwnd, "ROOT")

  if not root_method_logged then
    if root then
      reaper.ShowConsoleMsg("[TimeTracker] Multi-instance check: using JS_Window_GetRelated ROOT.\n")
    else
      reaper.ShowConsoleMsg("[TimeTracker] Multi-instance check: ROOT unsupported, falling back to JS_Window_GetParent walk.\n")
    end
    root_method_logged = true
  end

  if root then return root end

  -- Fallback: walk parents manually until there isn't one.
  local current = hwnd
  while true do
    local parent = reaper.JS_Window_GetParent(current)
    if not parent then break end
    current = parent
  end
  return current
end

-- True if REAPER is the OS-foreground window AND that foreground window
-- belongs to this REAPER instance (guards against a second open instance
-- being mistaken for this one).
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
    reaper.ShowConsoleMsg(string.format(
      "[TimeTracker] t=%.1f focused=%s\n", now, tostring(focused)
    ))
  end

  reaper.defer(main)
end

reaper.ClearConsole()
reaper.ShowConsoleMsg("[TimeTracker] Started. js_ReaScriptAPI found — polling foreground state.\n")
main()
