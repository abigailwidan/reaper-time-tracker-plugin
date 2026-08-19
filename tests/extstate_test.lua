-- ============================================================================
-- Test File: extstate_test.lua
-- Purpose: Validates basic read, write, and delete behaviour of REAPER's
--          per-project ExtState API (reaper.SetProjExtState /
--          reaper.GetProjExtState), using the exact section/key pair that
--          lib/tt_project_id.lua uses to persist a project's GUID: section
--          "TimeTracker", key "ProjectGUID". Manual REAPER-console script,
--          not automated -- run inside REAPER with the console open.
--
-- What it tests:
--   1. Write: reaper.SetProjExtState() successfully stores a string value.
--   2. Read: reaper.GetProjExtState() retrieves the exact value written.
--   3. Key/Namespace Isolation: values in one section don't bleed into
--      another (guards against a future feature reusing the "TimeTracker"
--      namespace for something else and clobbering the GUID key).
--   4. Delete: Setting an empty string clears the value (standard REAPER
--      pattern; tt_project_id.lua never actually does this, but the
--      dependent logic assumes empty-string means "no GUID yet").
-- ============================================================================

reaper.SetProjExtState(0, "TimeTracker", "ProjectGUID", "TEST-1234")

local retval, val = reaper.GetProjExtState(0, "TimeTracker", "ProjectGUID")
reaper.ShowConsoleMsg("1. Write and read: " .. tostring(val) .. " (expected: TEST-1234)\n")

reaper.SetProjExtState(0, "TimeTracker", "ProjectGUID", "TEST-5678")
local retval2, val2 = reaper.GetProjExtState(0, "TimeTracker", "ProjectGUID")
reaper.ShowConsoleMsg("2. Overwrite: " .. tostring(val2) .. " (expected: TEST-5678)\n")

reaper.SetProjExtState(0, "OtherNamespace", "ProjectGUID", "DIFFERENT")
local retval3, val3 = reaper.GetProjExtState(0, "TimeTracker", "ProjectGUID")
reaper.ShowConsoleMsg("3. Namespace isolation - TimeTracker still has: " .. tostring(val3) .. " (expected: TEST-5678)\n")

reaper.SetProjExtState(0, "TimeTracker", "ProjectGUID", "")
local retval4, val4 = reaper.GetProjExtState(0, "TimeTracker", "ProjectGUID")
reaper.ShowConsoleMsg("4. Deletion (empty string): " .. tostring(val4) .. " (expected: empty or nil)\n")

-- Clean up the other namespace test entry
reaper.SetProjExtState(0, "OtherNamespace", "ProjectGUID", "")
