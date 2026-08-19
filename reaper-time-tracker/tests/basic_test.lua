-- ============================================================================
-- Test File: basic_test.lua
-- Purpose: General sandbox for evaluating isolated REAPER API functions or
--          small logic snippets before integrating them into the main tracking
--          and reporting architecture.
--
-- Scope: Tests core REAPER APIs that underpin TimeTracker's identification
--        and state-management strategy.
--
-- What it tests:
--   1. GUID Format: Confirms reaper.genGuid() output (with braces) for
--      stripping before use as JSON keys.
--   2. Pointer Stability: Validates that EnumProjects(-1) returns consistent
--      pointers across calls (safe to use as references).
--   3. Dirty Flag Behavior: Verifies that SetProjExtState() correctly marks
--      the project as modified, ensuring saves are prompted when state changes.
--
-- Key insight: This test ensures the three cornerstones of project tracking
--              (GUIDs, pointer identity, and project dirtying) work as
--              expected before relying on them in the background loop.
-- ============================================================================

reaper.ClearConsole()

-- 1. genGuid() Return Format
-- Expected: A GUID string with braces, e.g. "{12345678-1234-5678-1234-567812345678}"
-- Used for: Confirming brace-stripping logic works correctly.
local guid = reaper.genGuid()
reaper.ShowConsoleMsg("1. genGuid format: " .. tostring(guid) .. "\n")

-- 2. EnumProjects Pointer Stability
-- Expected: proj1 and proj2 are identical pointers for the current project.
-- Used for: Confirming that EnumProjects(-1) reliably refers to the active tab
--           across multiple calls in the defer() loop.
local proj1 = reaper.EnumProjects(-1, "")
local proj2 = reaper.EnumProjects(-1, "")
reaper.ShowConsoleMsg("2. Pointer stability (consecutive calls): " .. tostring(proj1 == proj2) .. "\n")

-- 3. SetProjExtState Dirty Flag Trigger
-- Expected: is_dirty_after should be true (or have a higher value than before).
-- Used for: Confirming that writing state via SetProjExtState() correctly marks
--           the project as modified. This is critical for detecting "Save As"
--           and ensuring the autosave workflow doesn't inadvertently block
--           saves when the user intends to persist the project.
local is_dirty_before = reaper.IsProjectDirty(proj1) ~= 0
reaper.SetProjExtState(proj1, "TimeTracker_Test", "TestKey", "TestValue")
local is_dirty_after = reaper.IsProjectDirty(proj1) ~= 0
reaper.ShowConsoleMsg("3. Dirty flag - Before: " .. tostring(is_dirty_before) .. " | After: " .. tostring(is_dirty_after) .. "\n")

-- Clean up the test state
reaper.SetProjExtState(proj1, "TimeTracker_Test", "TestKey", "")