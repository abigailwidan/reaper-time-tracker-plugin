-- ============================================================================
-- Test File: extstate_carryover_test.lua
-- Purpose: Verifies that a project's GUID (stored via ExtState under section
--          "TimeTracker", key "ProjectGUID" -- see lib/tt_project_id.lua)
--          persists across project tab switches and background-script
--          restarts. Manual procedure, not automated -- run inside REAPER.
--
-- Note: only the GUID lives in ExtState. Accumulated session time lives in
-- the JSON data file on disk (lib/tt_paths.lua), not in ExtState, so there
-- is nothing to check for time carryover here -- that's what
-- tests/tt_data_test.lua and TimeTracker_Background.lua's crash-recovery
-- path (load_and_recover_data) cover instead.
--
-- Manual test procedure:
--   1. Run this script in project A. Note the printed GUID.
--   2. Switch to project B (or create a new tab).
--   3. Switch back to project A.
--   4. Run this script again and confirm the same GUID is retrieved.
--   5. Stop the background script (TimeTracker_Background.lua), then
--      restart it.
--   6. Confirm the GUID is still present in ExtState afterwards.
-- ============================================================================

local retval, val = reaper.GetProjExtState(0, "TimeTracker", "ProjectGUID")

reaper.ShowConsoleMsg("Current project ExtState - TimeTracker ProjectGUID: " .. tostring(val) .. "\n")

if val == "" then
  reaper.ShowConsoleMsg("  (No GUID yet -- this project is untracked, or unsaved.)\n")
else
  reaper.ShowConsoleMsg("  (GUID found -- ExtState is working correctly.)\n")
end
