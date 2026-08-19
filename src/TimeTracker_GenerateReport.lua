-- TimeTracker_GenerateReport.lua
--
-- Milestone 7: Report v2 / Milestone 8: Email handoff
-- Reads time_data.json, validates version/corruption rules, and generates
-- a comprehensive HTML report complete with project totals and a full
-- chronological session log. Offers to open a client email draft afterwards.

local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "../lib/?.lua;" .. package.path

local tt_paths = require("tt_paths")
local tt_data = require("tt_data")
local tt_shell = require("tt_shell")
local tt_email = require("tt_email")

local METER_SEGMENTS = 24

local function format_hours(seconds)
  return string.format("%.2f hrs", seconds / 3600)
end

-- Splits an epoch timestamp into a short weekday/date line and a 12-hour
-- clock line, falling back to the raw ISO string if the epoch is missing
-- (older data files that predate the _raw_start/_raw_end fields).
local function format_display_time(raw_epoch, iso_fallback)
  if not raw_epoch or raw_epoch == 0 then
    return { date = "", clock = iso_fallback or "Unknown" }
  end
  local clock = os.date("%I:%M %p", raw_epoch):gsub("^0", "")
  return { date = os.date("%a %d %b", raw_epoch), clock = clock }
end

-- Escapes user-controlled strings (project display names come from filenames
-- and are otherwise dropped straight into the HTML template).
local function html_escape(s)
  s = tostring(s or "")
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
  return s
end

-- Cheap deterministic string -> hue mapping so each project gets a stable
-- identity tag color across the totals panel and the session log.
local function hash_hue(s)
  local h = 0
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 360
  end
  return h
end

-- Renders a fixed-width LED ladder in the style of an analog VU meter: the
-- color zones (green / amber / red) are properties of the ladder position,
-- not of the value, exactly like real meter hardware. `pct` only controls
-- how many segments are lit.
local function build_meter(pct)
  local filled = math.max(1, math.floor((pct / 100) * METER_SEGMENTS + 0.5))
  local parts = {}
  for i = 1, METER_SEGMENTS do
    local zone = "seg-green"
    if i > METER_SEGMENTS * 0.85 then
      zone = "seg-red"
    elseif i > METER_SEGMENTS * 0.6 then
      zone = "seg-amber"
    end
    local state = (i <= filled) and "on" or "off"
    parts[#parts + 1] = string.format('<span class="seg %s %s"></span>', zone, state)
  end
  return table.concat(parts)
end

local function generate_html(data)
  -- Flatten to a sortable project list (deterministic order, largest first)
  local project_list = {}
  local grand_seconds = 0
  for guid, proj in pairs(data.projects or {}) do
    local total_sec = proj.total_seconds or 0
    grand_seconds = grand_seconds + total_sec
    table.insert(project_list, {
      guid = guid,
      name = proj.display_name or "Unknown Project",
      total_seconds = total_sec,
      sessions = proj.sessions or {},
    })
  end
  table.sort(project_list, function(a, b) return a.total_seconds > b.total_seconds end)

  local max_sec = 1
  for _, proj in ipairs(project_list) do
    if proj.total_seconds > max_sec then max_sec = proj.total_seconds end
  end

  -- Flatten every session across every project into one true chronological
  -- log (newest first), rather than grouping by project iteration order.
  local all_sessions = {}
  for _, proj in ipairs(project_list) do
    for _, sess in ipairs(proj.sessions) do
      table.insert(all_sessions, {
        project_name = proj.name,
        project_guid = proj.guid,
        start_time = sess.start_time or "Unknown",
        end_time = sess.end_time or "Unknown",
        duration_seconds = sess.duration_seconds or 0,
        raw_start = sess._raw_start or 0,
        raw_end = sess._raw_end or 0,
        is_active = sess._is_active,
      })
    end
  end
  table.sort(all_sessions, function(a, b) return a.raw_start > b.raw_start end)

  local project_rows = ""
  for _, proj in ipairs(project_list) do
    local hours_str = format_hours(proj.total_seconds)
    local pct = math.min(100, math.max(2, math.floor((proj.total_seconds / max_sec) * 100)))
    local hue = hash_hue(proj.guid)

    project_rows = project_rows .. string.format([[
      <tr>
        <td>
          <div class="proj-name"><span class="chip" style="background: hsl(%ddeg 45%% 42%%);"></span>%s</div>
          <div class="proj-guid">%s</div>
        </td>
        <td>
          <div class="meter">%s</div>
        </td>
        <td class="num-cell">
          <div class="hours-readout">%s</div>
          <div class="pct-readout">%d%% of peak</div>
        </td>
      </tr>
    ]], hue, html_escape(proj.name), html_escape(proj.guid), build_meter(pct), hours_str, pct)
  end

  local session_rows = ""
  for _, sess in ipairs(all_sessions) do
    local dur_str = format_hours(sess.duration_seconds)
    local hue = hash_hue(sess.project_guid)
    local live_badge = sess.is_active and '<span class="live-badge">&#9679; live</span>' or ""
    local start_disp = format_display_time(sess.raw_start, sess.start_time)
    local end_disp = format_display_time(sess.raw_end, sess.end_time)

    session_rows = session_rows .. string.format([[
      <tr>
        <td><span class="chip" style="background: hsl(%ddeg 45%% 42%%);"></span>%s</td>
        <td class="time-cell"><div class="time-date">%s</div><div class="time-clock mono">%s</div></td>
        <td class="time-cell"><div class="time-date">%s</div><div class="time-clock mono">%s</div></td>
        <td class="num-cell mono">%s%s</td>
      </tr>
    ]], hue, html_escape(sess.project_name), start_disp.date, start_disp.clock, end_disp.date, end_disp.clock, dur_str, live_badge)
  end

  local grand_hours = grand_seconds / 3600
  local counter_str = string.format("%08.1f", grand_hours)
  local generated_str = os.date("%d %b %Y, %H:%M")

  return [[
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>TimeTracker Session Report</title>
  <style>
    :root {
      --chassis: #24221d;
      --chassis-hi: #302d25;
      --chassis-line: #17150f;
      --panel: #f3ead8;
      --panel-line: #e1d3b3;
      --ink: #2b2318;
      --ink-soft: #7a6c52;
      --silk: #d8cbab;
      --silk-dim: #8c8064;
      --copper: #c17a3d;
      --copper-hi: #e0a05a;
      --led-green: #6f9a52;
      --led-green-hi: #8fbf6a;
      --led-red: #b5533f;
    }

    * { box-sizing: border-box; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background:
        radial-gradient(ellipse at top, var(--chassis-hi), var(--chassis) 70%),
        repeating-linear-gradient(180deg, rgba(255,255,255,0.015) 0px, rgba(255,255,255,0.015) 1px, transparent 1px, transparent 3px);
      color: var(--silk);
      margin: 0;
      padding: 48px 20px 60px;
      line-height: 1.5;
    }

    .rack { max-width: 920px; margin: 0 auto; }

    .masthead {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 24px;
      background: linear-gradient(180deg, var(--chassis-hi), var(--chassis));
      border: 1px solid var(--chassis-line);
      border-top: 1px solid rgba(255,255,255,0.08);
      border-radius: 12px;
      padding: 26px 32px;
      box-shadow: 0 12px 28px rgba(0,0,0,0.35), inset 0 1px 0 rgba(255,255,255,0.04);
      position: relative;
    }

    .masthead::before, .masthead::after {
      content: "";
      position: absolute;
      top: 14px;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: radial-gradient(circle at 35% 35%, #6b6353, #171510);
    }
    .masthead::before { left: 14px; }
    .masthead::after { right: 14px; }

    .wordmark .brand {
      font-size: 1.9rem;
      font-weight: 800;
      letter-spacing: 0.09em;
      color: var(--silk);
      text-transform: uppercase;
    }
    .wordmark .tagline {
      font-size: 0.78rem;
      letter-spacing: 0.18em;
      text-transform: uppercase;
      color: var(--silk-dim);
      margin-top: 6px;
    }

    .counter-unit {
      background: var(--panel);
      border: 1px solid var(--panel-line);
      border-radius: 7px;
      padding: 10px 20px;
      box-shadow: inset 0 2px 6px rgba(0,0,0,0.35), inset 0 -1px 0 rgba(255,255,255,0.4);
      text-align: right;
      min-width: 200px;
    }
    .counter-display {
      font-family: ui-monospace, "SF Mono", "Cascadia Mono", "JetBrains Mono", Consolas, monospace;
      font-size: 2.1rem;
      font-weight: 700;
      color: var(--ink);
      letter-spacing: 0.04em;
      line-height: 1;
      font-variant-numeric: tabular-nums;
    }
    .counter-label {
      font-size: 0.62rem;
      letter-spacing: 0.14em;
      text-transform: uppercase;
      color: var(--ink-soft);
      margin-top: 6px;
    }

    .meta-strip {
      margin: 20px 4px 28px;
      font-size: 0.78rem;
      letter-spacing: 0.03em;
      color: var(--silk-dim);
      text-transform: uppercase;
    }

    .panel {
      background: var(--panel);
      border: 1px solid var(--panel-line);
      border-top: 1px solid #fffdf6;
      border-radius: 10px;
      padding: 30px 32px 12px;
      margin-bottom: 26px;
      box-shadow: 0 10px 24px rgba(0,0,0,0.28);
    }

    .panel-title {
      margin: 0 0 18px;
      font-size: 1.02rem;
      font-weight: 800;
      letter-spacing: 0.05em;
      text-transform: uppercase;
      color: var(--ink);
    }
    .panel-title .panel-sub {
      font-weight: 500;
      text-transform: none;
      letter-spacing: 0;
      color: var(--ink-soft);
      font-size: 0.85rem;
      margin-left: 8px;
    }

    table { width: 100%; border-collapse: collapse; }
    th {
      text-align: left;
      font-size: 0.68rem;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--ink-soft);
      font-weight: 700;
      padding: 0 10px 10px;
      border-bottom: 1px solid var(--panel-line);
    }
    td {
      padding: 14px 10px;
      border-bottom: 1px solid var(--panel-line);
      vertical-align: middle;
      color: var(--ink);
    }
    tr:last-child td { border-bottom: none; }
    tbody tr:nth-child(even) { background: rgba(43,35,24,0.035); }

    .num-cell { text-align: right; }
    .mono { font-family: ui-monospace, "SF Mono", "Cascadia Mono", "JetBrains Mono", Consolas, monospace; font-size: 0.86rem; }

    .time-cell { white-space: nowrap; }
    .time-date { font-weight: 600; font-size: 0.86rem; color: var(--ink); }
    .time-clock { font-size: 0.76rem; color: var(--ink-soft); margin-top: 3px; letter-spacing: 0.02em; }

    .chip {
      display: inline-block;
      width: 8px;
      height: 8px;
      border-radius: 50%;
      margin-right: 8px;
      box-shadow: 0 0 0 2px rgba(255,255,255,0.5);
    }
    .proj-name { font-weight: 700; }
    .proj-guid {
      font-family: ui-monospace, "SF Mono", "Cascadia Mono", "JetBrains Mono", Consolas, monospace;
      font-size: 0.72rem;
      color: var(--ink-soft);
      margin-top: 3px;
      margin-left: 16px;
    }

    .hours-readout {
      font-family: ui-monospace, "SF Mono", "Cascadia Mono", "JetBrains Mono", Consolas, monospace;
      font-weight: 700;
      font-variant-numeric: tabular-nums;
    }
    .pct-readout { font-size: 0.68rem; color: var(--ink-soft); margin-top: 2px; }

    .meter { display: flex; gap: 2px; min-width: 220px; }
    .seg { flex: 1; height: 15px; border-radius: 1px; background: var(--panel-line); box-shadow: inset 0 1px 2px rgba(0,0,0,0.15); }
    .seg.on.seg-green { background: linear-gradient(180deg, var(--led-green-hi), var(--led-green)); box-shadow: 0 0 4px rgba(111,154,82,0.6); }
    .seg.on.seg-amber { background: linear-gradient(180deg, var(--copper-hi), var(--copper)); box-shadow: 0 0 4px rgba(193,122,61,0.6); }
    .seg.on.seg-red { background: linear-gradient(180deg, #cf6d55, var(--led-red)); box-shadow: 0 0 4px rgba(181,83,63,0.6); }

    .live-badge {
      display: inline-block;
      margin-left: 8px;
      font-size: 0.66rem;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      color: #fff;
      background: var(--led-green);
      padding: 2px 7px;
      border-radius: 20px;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }

    .empty-state { text-align: center; color: var(--ink-soft); padding: 30px 0; }

    .fine-print {
      text-align: center;
      font-size: 0.72rem;
      letter-spacing: 0.03em;
      color: var(--silk-dim);
      margin-top: 32px;
      padding: 0 20px;
    }

    @media print {
      :root {
        --chassis: #ffffff;
        --chassis-hi: #ffffff;
        --chassis-line: #cccccc;
        --silk: #111111;
        --silk-dim: #444444;
      }
      body { background: #fff; }
      .masthead, .panel { box-shadow: none; }
      .masthead::before, .masthead::after { display: none; }
    }
  </style>
</head>
<body>
  <div class="rack">
    <header class="masthead">
      <div class="wordmark">
        <div class="brand">TimeTracker</div>
        <div class="tagline">Studio Session Report</div>
      </div>
      <div class="counter-unit">
        <div class="counter-display">]] .. counter_str .. [[</div>
        <div class="counter-label">Total Hours Logged</div>
      </div>
    </header>

    <div class="meta-strip">Generated ]] .. generated_str .. [[ &middot; ]] .. tostring(#project_list) .. [[ project(s) &middot; ]] .. tostring(#all_sessions) .. [[ session(s)</div>

    <section class="panel">
      <h2 class="panel-title">Project Totals<span class="panel-sub">relative share of tracked time</span></h2>
      <table>
        <thead>
          <tr>
            <th style="width: 30%;">Project</th>
            <th style="width: 40%;">Meter</th>
            <th style="text-align: right; width: 30%;">Total</th>
          </tr>
        </thead>
        <tbody>
          ]] .. (project_rows ~= "" and project_rows or '<tr><td colspan="3" class="empty-state">No signal &mdash; no project time recorded yet.</td></tr>') .. [[
        </tbody>
      </table>
    </section>

    <section class="panel">
      <h2 class="panel-title">Session Log<span class="panel-sub">chronological, newest first</span></h2>
      <table>
        <thead>
          <tr>
            <th>Project</th>
            <th>Start</th>
            <th>End</th>
            <th style="text-align: right;">Duration</th>
          </tr>
        </thead>
        <tbody>
          ]] .. (session_rows ~= "" and session_rows or '<tr><td colspan="4" class="empty-state">No sessions recorded yet.</td></tr>') .. [[
        </tbody>
      </table>
    </section>

    <p class="fine-print">Time recorded via active-window focus tracking inside REAPER. Generated automatically by TimeTracker.</p>
  </div>
</body>
</html>
  ]]
end

-- Renames a corrupt data file aside, per PLAN.md's interface contract. This
-- script is the only one that does so, so two scripts can't race on the file.
local function quarantine_corrupt_file()
  local data_file = tt_paths.get_data_file()
  local timestamp = os.date("%Y%m%dT%H%M%S")
  local corrupted = data_file:gsub("time_data.json$",
    "time_data.corrupted-" .. timestamp .. ".json")
  os.rename(data_file, corrupted)
  reaper.ShowMessageBox(string.format(
    "Your data file appeared corrupted and was saved as time_data.corrupted-%s.json "
      .. "for inspection.", timestamp),
    "TimeTracker - Corrupted Data", 0)
end

local function main()
  local data, message, kind = tt_data.load()

  if not data then
    if kind == "corrupt" then
      quarantine_corrupt_file()
    else
      local title = (kind == "version") and "TimeTracker - Version Mismatch"
        or "TimeTracker Report"
      reaper.ShowMessageBox(message, title, 0)
    end
    return
  end

  -- Confidentiality gate: a report handed to one client must not disclose
  -- other clients' project names and hours.
  data = tt_data.prompt_for_scope(data, "TimeTracker - Report Scope")
  if not data then return end

  local html_content = generate_html(data)
  local html_path = tt_paths.get_data_dir() .. package.config:sub(1, 1) .. "time_report.html"

  local out = io.open(html_path, "w")
  if not out then
    reaper.ShowMessageBox("Failed to write HTML report file.", "TimeTracker Error", 0)
    return
  end
  out:write(html_content)
  out:close()

  -- Reveal the generated report in Finder/Explorer/file manager.
  tt_shell.open(tt_paths.get_data_dir())

  -- 4 = Yes/No buttons; 6 = Yes.
  local answer = reaper.ShowMessageBox(
    "Report generated successfully!\n\nFile location:\n" .. html_path
      .. "\n\nOpen an email draft for the client now?",
    "TimeTracker Report", 4)

  if answer == 6 then
    tt_email.compose(data)
  end
end

main()
