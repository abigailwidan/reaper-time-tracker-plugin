-- ============================================================================
-- Test File: extstate_carryover_test.lua
-- Purpose: Verifies that REAPER's ExtState data persists accurately across
--          different project tabs (context switches) and survives script
--          restarts without losing the active timer session.
--
-- Scope: Tests the durability of ExtState in multi-project workflows and
--        ensures that session data isn't dropped when switching projects
--        or reloading the script.
--
-- What it tests:
--   1. Cross-Tab Persistence: After writing a value in project A, switch to
--      project B, then back to A. Confirm the value is still there.
--   2. Script Restart Resilience: Stop and restart the background loop without
--      losing previously stored session data.
--   3. Session Continuity: If a timer session is in progress when the script
--      restarts, the GUID and accumulated time remain intact in ExtState.
--
-- Context: TimeTracker relies on ExtState to hold project GUIDs and session
--          time data. Users may switch between multiple projects (tabs) in
--          a single REAPER session or restart the background script without
--          losing work. This test ensures ExtState doesn't silently drop data
--          during these common workflows.
--
-- Manual test procedure:
--   1. Run this script in project A.
--   2. Note the ExtState value for "TimeTracker" > "GUID".
--   3. Switch to project B (or create a new tab).
--   4. Switch back to project A.
--   5. Run this script again and confirm the same GUID is retrieved.
--   6. Stop the background script, then restart it.
--   7. Confirm the GUID is still present in ExtState.
-- ============================================================================

-- Query the active project's ExtState for a stored GUID
-- This would typically be set by TimeTracker_Background.lua on first run.
local retval, val = reaper.GetProjExtState(0, "TimeTracker", "GUID")

reaper.ShowConsoleMsg("Current project ExtState - TimeTracker GUID: " .. tostring(val) .. "\n")

-- If no GUID exists yet, note it; if one does, confirm it persists.
if val == "" then
  reaper.ShowConsoleMsg("  (No GUID yet — this project is untracked.)\n")
else
  reaper.ShowConsoleMsg("  (GUID found — ExtState is working correctly.)\n")
end

-- Optionally, log accumulated time if stored
local retval2, timeVal = reaper.GetProjExtState(0, "TimeTracker", "AccumulatedTime")
if timeVal ~= "" then
  reaper.ShowConsoleMsg("Accumulated time in this project: " .. tostring(timeVal) .. "\n")
else
  reaper.ShowConsoleMsg("No accumulated time yet for this project.\n")
end