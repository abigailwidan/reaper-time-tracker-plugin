local retval, val = reaper.GetProjExtState(0, "TimeTracker", "GUID")
reaper.ShowConsoleMsg("Save As ExtState value: " .. tostring(val) .. "\n")