-- lib/tt_deps.lua
--
-- Purpose: Validate required external dependencies before running TimeTracker.
--
-- TimeTracker depends on js_ReaScriptAPI, a community-maintained REAPER extension
-- that provides OS-level window management functions unavailable in stock ReaScript.
-- Specifically, we need JS_Window_GetForeground() to query the OS window focus,
-- which enables focus-based time tracking (vs. idle detection).
--
-- This module checks for the presence of the extension and guides the user to
-- install it via ReaPack if missing. It does NOT handle installation—it only
-- detects and warns.
--
-- Dependencies: REAPER API (reaper.JS_Window_GetForeground)

local tt_deps = {}

-- Returns true if js_ReaScriptAPI is installed and JS_Window_GetForeground is available.
-- This function is tested on startup to bail gracefully if the extension is missing.
function tt_deps.check_js_reascript_api()
  return type(reaper.JS_Window_GetForeground) == "function"
end

-- Displays a user-facing message box with instructions for installing js_ReaScriptAPI.
-- Guides the user through: Extensions > ReaPack > Browse Packages > search > install > restart.
-- Call this before exiting if the dependency check fails.
function tt_deps.warn_missing_js_reascript_api()
  reaper.ShowMessageBox(
    "TimeTracker requires the js_ReaScriptAPI extension, which isn't installed.\n\n" ..
    "To install it:\n" ..
    "1. Open Extensions > ReaPack > Browse packages\n" ..
    "2. Search for \"js_ReaScriptAPI\"\n" ..
    "3. Install \"js_ReaScriptAPI: API functions for ReaScripts\"\n" ..
    "4. Restart REAPER and run this script again",
    "TimeTracker - Missing Dependency",
    0
  )
end

return tt_deps