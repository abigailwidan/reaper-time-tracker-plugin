-- ============================================================================
-- Test File: extstate_test.lua
-- Purpose: Validates basic read, write, and delete capabilities of REAPER's
--          ExtState API (reaper.SetProjExtState / reaper.GetProjExtState).
--
-- Scope: Tests the ExtState persistence mechanism that stores project GUIDs
--        and temporary session data during rapid polling.
--
-- What it tests:
--   1. Write: reaper.SetProjExtState() successfully stores a string value.
--   2. Read: reaper.GetProjExtState() retrieves the exact value written.
--   3. Delete: Setting an empty string clears the value (standard REAPER pattern).
--   4. Key/Namespace Isolation: Values in one namespace don't bleed into another.
--
-- Context: TimeTracker uses ExtState to persist project GUIDs across sessions,
--          so a project's identity survives REAPER restarts. This test ensures
--          that the underlying storage layer is reliable for this critical use case.
--
-- Expected flow:
--   → SetProjExtState(0, "TimeTracker", "GUID", "TEST-1234")
--   → GetProjExtState(0, "TimeTracker", "GUID") returns "TEST-1234"
--   → SetProjExtState(0, "TimeTracker", "GUID", "") clears the value
-- ============================================================================

-- Write a test GUID
reaper.SetProjExtState(0, "TimeTracker", "GUID", "TEST-1234")

-- Immediately read it back to confirm write succeeded
local retval, val = reaper.GetProjExtState(0, "TimeTracker", "GUID")
reaper.ShowConsoleMsg("1. Write and read: " .. tostring(val) .. " (expected: TEST-1234)\n")

-- Test that we can overwrite
reaper.SetProjExtState(0, "TimeTracker", "GUID", "TEST-5678")
local retval2, val2 = reaper.GetProjExtState(0, "TimeTracker", "GUID")
reaper.ShowConsoleMsg("2. Overwrite: " .. tostring(val2) .. " (expected: TEST-5678)\n")

-- Test namespace isolation (different section should not affect this value)
reaper.SetProjExtState(0, "OtherNamespace", "GUID", "DIFFERENT")
local retval3, val3 = reaper.GetProjExtState(0, "TimeTracker", "GUID")
reaper.ShowConsoleMsg("3. Namespace isolation - TimeTracker still has: " .. tostring(val3) .. " (expected: TEST-5678)\n")

-- Test deletion by setting to empty string
reaper.SetProjExtState(0, "TimeTracker", "GUID", "")
local retval4, val4 = reaper.GetProjExtState(0, "TimeTracker", "GUID")
reaper.ShowConsoleMsg("4. Deletion (empty string): " .. tostring(val4) .. " (expected: empty or nil)\n")

-- Clean up the other namespace test entry
reaper.SetProjExtState(0, "OtherNamespace", "GUID", "")