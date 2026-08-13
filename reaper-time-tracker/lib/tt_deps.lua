-- tt_deps.lua
-- Checks for the js_ReaScriptAPI extension, which this project depends on
-- for OS-level window-focus queries (stock ReaScript has no such call).
-- See DOCS.md > Technology Choice Rationale.

local tt_deps = {}

-- True if js_ReaScriptAPI is installed and available in this instance.
-- Tests for JS_Window_GetForeground specifically, since that's the one
-- function this project actually needs (no package-name lookup needed).
function tt_deps.check_js_reascript_api()
  return type(reaper.JS_Window_GetForeground) == "function"
end

-- Shows a message box pointing the user to installing the extension via
-- ReaPack. Caller is responsible for exiting afterwards.
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
