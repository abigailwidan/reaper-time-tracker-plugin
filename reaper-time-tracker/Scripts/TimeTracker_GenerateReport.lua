-- TimeTracker_GenerateReport.lua
--
-- Milestone 7: Report v2
-- Reads time_data.json, validates version/corruption rules, and generates
-- a comprehensive HTML report complete with project totals and a full
-- chronological session log.

local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "../lib/?.lua;" .. package.path

local tt_paths = require("tt_paths")
local tt_json = require("tt_json")

local EXPECTED_VERSION = 1

local function format_hours(seconds)
  return string.format("%.2f hrs", seconds / 3600)
end

local function generate_html(data)
  local project_rows = ""
  local session_rows = ""
  
  -- Find max seconds for relative bar widths
  local max_sec = 1
  for _, proj in pairs(data.projects or {}) do
    if (proj.total_seconds or 0) > max_sec then
      max_sec = proj.total_seconds
    end
  end

  for guid, proj in pairs(data.projects or {}) do
    local name = proj.display_name or "Unknown Project"
    local total_sec = proj.total_seconds or 0
    local hours_str = format_hours(total_sec)
    local pct = math.min(100, math.max(2, math.floor((total_sec / max_sec) * 100)))
    
    -- Project Summary Row & Bar Chart representation
    project_rows = project_rows .. string.format([[
      <tr>
        <td><strong>%s</strong><br><small style="color: #886; font-family: monospace;">%s</small></td>
        <td>
          <div style="background: #eee; border-radius: 4px; overflow: hidden; width: 100%%; height: 16px;">
            <div style="background: #007acc; width: %d%%; height: 100%%;"></div>
          </div>
        </td>
        <td style="text-align: right; font-weight: bold;">%s</td>
      </tr>
    ]], name, guid, pct, hours_str)

    -- Session Log Rows
    for _, sess in ipairs(proj.sessions or {}) do
      local start_t = sess.start_time or "Unknown"
      local end_t = sess.end_time or "Unknown"
      local dur_str = format_hours(sess.duration_seconds or 0)
      
      session_rows = session_rows .. string.format([[
        <tr>
          <td>%s</td>
          <td style="font-family: monospace; font-size: 0.9em;">%s</td>
          <td style="font-family: monospace; font-size: 0.9em;">%s</td>
          <td style="text-align: right;">%s</td>
        </tr>
      ]], name, start_t, end_t, dur_str)
    end
  end

  return [[
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>TimeTracker Client Report</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 900px; margin: 40px auto; padding: 0 20px; color: #333; background: #fdfdfd; line-height: 1.5; }
    h1 { border-bottom: 2px solid #eee; padding-bottom: 10px; margin-bottom: 5px; }
    h2 { margin-top: 40px; border-bottom: 1px solid #ddd; padding-bottom: 8px; }
    p.subtitle { color: #666; margin-top: 0; margin-bottom: 30px; }
    table { width: 100%; border-collapse: collapse; margin-top: 15px; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.1); border-radius: 6px; overflow: hidden; }
    th, td { text-align: left; padding: 12px 16px; border-bottom: 1px solid #eee; }
    th { background: #f8f9fa; font-weight: 600; }
    tr:last-child td { border-bottom: none; }
  </style>
</head>
<body>
  <h1>TimeTracker Client Report</h1>
  <p class="subtitle">Generated automatically via REAPER ReaScript background telemetry.</p>

  <h2>Project Totals & Distribution</h2>
  <table>
    <thead>
      <tr>
        <th style="width: 35%;">Project Name</th>
        <th style="width: 45%;">Relative Share</th>
        <th style="text-align: right; width: 20%;">Total Time</th>
      </tr>
    </thead>
    <tbody>
      ]] .. (project_rows ~= "" and project_rows or '<tr><td colspan="3" style="text-align:center; color:#777;">No project data recorded yet.</td></tr>') .. [[
    </tbody>
  </table>

  <h2>Chronological Session Log</h2>
  <table>
    <thead>
      <tr>
        <th>Project Name</th>
        <th>Start Time</th>
        <th>End Time</th>
        <th style="text-align: right;">Duration</th>
      </tr>
    </thead>
    <tbody>
      ]] .. (session_rows ~= "" and session_rows or '<tr><td colspan="4" style="text-align:center; color:#777;">No sessions recorded yet.</td></tr>') .. [[
    </tbody>
  </table>
</body>
</html>
  ]]
end

local function main()
  local data_file = tt_paths.get_data_file()
  local f = io.open(data_file, "r")
  
  if not f then
    reaper.ShowMessageBox("No time tracking data found yet. Track some active project time first!", "TimeTracker Report", 0)
    return
  end
  
  local content = f:read("*a")
  f:close()
  
  if content == "" then
    reaper.ShowMessageBox("Time data file is empty.", "TimeTracker Report", 0)
    return
  end
  
  local data = tt_json.decode(content)
  
  if not data or type(data) ~= "table" then
    local timestamp = os.date("%Y%m%dT%H%M%S")
    local corrupted_filename = data_file:gsub("time_data.json$", "time_data.corrupted-" .. timestamp .. ".json")
    os.rename(data_file, corrupted_filename)
    reaper.ShowMessageBox(string.format("Your data file appeared corrupted and was saved as time_data.corrupted-%s.json for inspection.", timestamp), "TimeTracker - Corrupted Data", 0)
    return
  end
  
  if data.version ~= EXPECTED_VERSION then
    reaper.ShowMessageBox(string.format("This report expects data version %d but found version %s. Update TimeTracker_GenerateReport.lua to match, or restore an older backup of time_data.json.", EXPECTED_VERSION, tostring(data.version)), "TimeTracker - Version Mismatch", 0)
    return
  end
  
-- Generate HTML output
  local html_content = generate_html(data)
  local html_path = tt_paths.get_data_dir() .. package.config:sub(1,1) .. "time_report.html"
  
  local out = io.open(html_path, "w")
  if not out then
    reaper.ShowMessageBox("Failed to write HTML report file.", "TimeTracker Error", 0)
    return
  end
  out:write(html_content)
  out:close()

  -- Automatically reveal and select the generated HTML report file in Finder/Explorer
  os.execute('open "' .. tt_paths.get_data_dir() .. '"')

  -- Fallback message if SWS/CF functions aren't active, giving exact path confirmation
  reaper.ShowMessageBox(
    "Report generated successfully!\n\nFile location:\n" .. html_path,
    "TimeTracker Report",
    0
  )
end

main()