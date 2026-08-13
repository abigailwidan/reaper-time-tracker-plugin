-- lib/tt_paths.lua
-- Resolves data file locations using REAPER's resource path.

local paths = {}
local sep = package.config:sub(1,1)

function paths.get_data_dir()
  return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "TimeTracker"
end

function paths.get_data_file()
  return paths.get_data_dir() .. sep .. "time_data.json"
end

function paths.get_temp_file()
  return paths.get_data_dir() .. sep .. "time_data.tmp"
end

function paths.ensure_dir()
  reaper.RecursiveCreateDirectory(paths.get_data_dir(), 0)
end

return paths