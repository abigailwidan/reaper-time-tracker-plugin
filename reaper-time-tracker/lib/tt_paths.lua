-- lib/tt_paths.lua
--
-- Purpose: Centralized path resolution for TimeTracker data files.
--
-- This module abstracts filesystem path construction, ensuring consistent
-- data storage across platforms (Windows, macOS, Linux) by leveraging
-- REAPER's built-in GetResourcePath() and respecting OS-specific path
-- separators.
--
-- Key Responsibilities:
--   - Compute the platform-specific TimeTracker data directory
--   - Return paths for persistent JSON data, temporary staging files
--   - Ensure the data directory exists before first write
--
-- Dependencies: REAPER API (reaper.GetResourcePath, reaper.RecursiveCreateDirectory)

local paths = {}
local sep = package.config:sub(1,1)  -- Platform separator: "/" (Unix) or "\\" (Windows)

-- Returns the base directory for TimeTracker data.
-- Format: <REAPER Resource Path>/Data/TimeTracker
-- Example: /Users/me/Library/Application Support/REAPER/Data/TimeTracker (macOS)
--          C:\Users\me\AppData\Roaming\REAPER\Data\TimeTracker (Windows)
function paths.get_data_dir()
  return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "TimeTracker"
end

-- Returns the path to the primary JSON data file where all session records are stored.
-- This file is created atomically via a temp file to prevent corruption on crash.
function paths.get_data_file()
  return paths.get_data_dir() .. sep .. "time_data.json"
end

-- Returns the path to the temporary staging file used during atomic writes.
-- Data is first written here, then atomically renamed to time_data.json.
function paths.get_temp_file()
  return paths.get_data_dir() .. sep .. "time_data.tmp"
end

-- Ensures the TimeTracker data directory exists. Called before any disk write.
-- Parameter: 0 (unused; required by REAPER API signature)
function paths.ensure_dir()
  reaper.RecursiveCreateDirectory(paths.get_data_dir(), 0)
end

return paths