-- ============================================================================
-- Test File: basic_test.lua
-- Purpose: Manual REAPER-console sandbox for the raw REAPER API calls that
--          lib/tt_project_id.lua's identity logic is built on. Run inside
--          REAPER (Actions > Load ReaScript) with the console open -- it is
--          not automated and has no assertions, just annotated console
--          output for a human to eyeball.
--
-- What it tests:
--   1. GUID Format: Confirms reaper.genGuid() output (with braces) before
--      lib/tt_project_id.lua strips them for use as a JSON key.
--   2. Pointer Stability: Validates that EnumProjects(-1) returns consistent
--      pointers across calls, which tab-switch detection relies on.
--   3. Dirty Flag Behavior: Verifies that SetProjExtState() marks the project
--      as modified, so GUID persistence doesn't get silently skipped by a
--      "nothing to save" project state.
-- ============================================================================

reaper.ClearConsole()

-- 1. genGuid() Return Format
-- Expected: A GUID string with braces, e.g. "{12345678-1234-5678-1234-567812345678}"
local guid = reaper.genGuid()
reaper.ShowConsoleMsg("1. genGuid format: " .. tostring(guid) .. "\n")

-- 2. EnumProjects Pointer Stability
-- Expected: proj1 and proj2 are identical pointers for the current project.
local proj1 = reaper.EnumProjects(-1, "")
local proj2 = reaper.EnumProjects(-1, "")
reaper.ShowConsoleMsg("2. Pointer stability (consecutive calls): " .. tostring(proj1 == proj2) .. "\n")

-- 3. SetProjExtState Dirty Flag Trigger
-- Expected: is_dirty_after should be true (or have a higher value than before).
local is_dirty_before = reaper.IsProjectDirty(proj1) ~= 0
reaper.SetProjExtState(proj1, "TimeTracker_Test", "TestKey", "TestValue")
local is_dirty_after = reaper.IsProjectDirty(proj1) ~= 0
reaper.ShowConsoleMsg("3. Dirty flag - Before: " .. tostring(is_dirty_before) .. " | After: " .. tostring(is_dirty_after) .. "\n")

-- Clean up the test state
reaper.SetProjExtState(proj1, "TimeTracker_Test", "TestKey", "")
