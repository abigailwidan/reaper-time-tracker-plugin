reaper.ClearConsole()

-- 1. genGuid() Return Format
local guid = reaper.genGuid()
reaper.ShowConsoleMsg("1. genGuid format: " .. tostring(guid) .. "\n")

-- 2. EnumProjects Pointer Stability
local proj1 = reaper.EnumProjects(-1, "")
local proj2 = reaper.EnumProjects(-1, "")
reaper.ShowConsoleMsg("2. Pointer stability (consecutive calls): " .. tostring(proj1 == proj2) .. "\n")

-- 3. SetProjExtState Dirty Flag Trigger
local is_dirty_before = reaper.IsProjectDirty(proj1) ~= 0
reaper.SetProjExtState(proj1, "TimeTracker_Test", "TestKey", "TestValue")
local is_dirty_after = reaper.IsProjectDirty(proj1) ~= 0
reaper.ShowConsoleMsg("3. Dirty flag - Before: " .. tostring(is_dirty_before) .. " | After: " .. tostring(is_dirty_after) .. "\n")

-- Clean up the test state
reaper.SetProjExtState(proj1, "TimeTracker_Test", "TestKey", "")