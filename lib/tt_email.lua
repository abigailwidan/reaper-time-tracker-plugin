-- lib/tt_email.lua
--
-- Composes a client-facing time summary and hands it to the OS default mail
-- client as a pre-filled mailto: draft. No network access, no credentials,
-- no stored account -- consistent with the offline-document stance in
-- SCOPE_DESIGN.md.
--
-- mailto: cannot carry attachments, so the report is not attached
-- automatically. The report folder is revealed instead, and the HTML is zipped
-- first so the recipient gets a real download rather than a mangled inline
-- preview (see tt_shell.zip_file for the reasoning).
--
-- The draft is written to be sendable as-is. A message arriving with an empty
-- greeting or an unsigned sign-off reads as unfinished, which undercuts the
-- tool's entire purpose: this document sits next to an invoice.

local tt_paths = require("tt_paths")
local tt_shell = require("tt_shell")

local email = {}

local EXT_SEC = "TimeTracker"
local EXT_KEY_EMAIL = "ClientEmail"
local EXT_KEY_CLIENT = "ClientName"
local EXT_KEY_SENDER = "SenderName"

-- Practical mailto ceiling. Windows' ShellExecute and several mail clients
-- truncate long URIs without warning, which would produce a half-finished
-- invoice summary the sender never sees.
local MAX_BODY_CHARS = 1800

local function format_hours(seconds)
  return string.format("%.2f", (seconds or 0) / 3600)
end

-- Decimal hours are the billing convention, but a client sanity-checking the
-- figure thinks in hours and minutes, so both are shown.
local function format_hm(seconds)
  local total_min = math.floor((seconds or 0) / 60 + 0.5)
  local h, m = math.floor(total_min / 60), total_min % 60
  if h == 0 then return string.format("%dm", m) end
  if m == 0 then return string.format("%dh", h) end
  return string.format("%dh %02dm", h, m)
end

local function pluralise(n, word)
  return string.format("%d %s%s", n, word, n == 1 and "" or "s")
end

-- Turns a project filename into something presentable to a client.
-- "ClientX_Mix_v3.RPP" -> "ClientX Mix v3". The client did not commission a
-- filename, and the .RPP extension means nothing to them. Display only --
-- the GUID remains the identity everywhere that matters.
local function presentable_name(display_name)
  local name = tostring(display_name or "Untitled Project")
  name = name:gsub("%.[Rr][Pp][Pp][%-%w]*$", "")
  name = name:gsub("[_]+", " ")
  name = name:gsub("%s+", " "):match("^%s*(.-)%s*$")
  if name == "" then return "Untitled Project" end
  return name
end

-- Earliest start and latest end across the included sessions, so the email
-- states the period being billed rather than just the day it was sent.
local function period_bounds(projects)
  local first, last
  for _, proj in ipairs(projects) do
    for _, sess in ipairs(proj.sessions or {}) do
      local s, e = sess._raw_start, sess._raw_end
      if s and s > 0 and (not first or s < first) then first = s end
      if e and e > 0 and (not last or e > last) then last = e end
    end
  end
  if not first then return nil end
  return first, last or first
end

local function format_period(first, last)
  if not first then return nil end
  if os.date("%Y%m%d", first) == os.date("%Y%m%d", last) then
    return os.date("%d %B %Y", first)
  end
  if os.date("%Y", first) == os.date("%Y", last) then
    return os.date("%d %B", first) .. " to " .. os.date("%d %B %Y", last)
  end
  return os.date("%d %B %Y", first) .. " to " .. os.date("%d %B %Y", last)
end

-- attachment_note describes whatever the user is about to attach, so the body
-- never promises a format that isn't actually there.
local function build_body(data, attachment_note, client_name, sender_name)
  local ordered, grand_total, total_sessions = {}, 0, 0

  for _, proj in pairs(data.projects or {}) do
    -- Projects with no recorded work are noise on a client-facing document.
    if (proj.total_seconds or 0) > 0 then
      table.insert(ordered, proj)
      grand_total = grand_total + proj.total_seconds
      total_sessions = total_sessions + #(proj.sessions or {})
    end
  end

  if #ordered == 0 then
    return nil, "There is no recorded project time to report yet."
  end

  -- Largest engagement leads, matching the report's own ordering.
  table.sort(ordered, function(a, b)
    return (a.total_seconds or 0) > (b.total_seconds or 0)
  end)

  local period = format_period(period_bounds(ordered))

  local greeting = (client_name ~= "") and ("Dear " .. client_name .. ",")
    or "Hello,"

  local lines = { greeting, "" }

  if period then
    table.insert(lines, "Below is a summary of working time recorded for the "
      .. "period " .. period .. ".")
  else
    table.insert(lines, "Below is a summary of working time recorded to date.")
  end
  table.insert(lines, "")

  for _, proj in ipairs(ordered) do
    table.insert(lines, string.format("  %s - %s hrs (%s) across %s",
      presentable_name(proj.display_name),
      format_hours(proj.total_seconds),
      format_hm(proj.total_seconds),
      pluralise(#(proj.sessions or {}), "session")))
  end

  table.insert(lines, "")
  -- A single-project report doesn't need a total restating the line above it.
  if #ordered > 1 then
    table.insert(lines, string.format("  TOTAL: %s hrs (%s) across %s",
      format_hours(grand_total), format_hm(grand_total),
      pluralise(total_sessions, "session")))
    table.insert(lines, "")
  end

  table.insert(lines, attachment_note)
  table.insert(lines, "")
  table.insert(lines, "Time is recorded automatically while the project is open "
    .. "and in active use, session by session, rather than estimated after the "
    .. "fact.")
  table.insert(lines, "")
  table.insert(lines, "Kind regards,")
  if sender_name ~= "" then
    table.insert(lines, sender_name)
  end

  local body = table.concat(lines, "\r\n")

  if #body > MAX_BODY_CHARS then
    body = body:sub(1, MAX_BODY_CHARS)
      .. "\r\n\r\n[Summary truncated -- see the attached report for the full breakdown.]"
  end

  return body, nil, period
end

-- Locates the HTML report and zips it for attachment.
-- Returns: path to attach (string|nil), body wording (string), UI hint (string)
local function prepare_attachment()
  local sep = package.config:sub(1, 1)
  local dir = tt_paths.get_data_dir()
  local html_path = dir .. sep .. "time_report.html"

  local exists = io.open(html_path, "r")
  if not exists then
    return nil,
      "A full session-by-session breakdown is available on request.",
      "No report file exists yet -- run Generate Report first if you want to "
        .. "attach the full session log."
  end
  exists:close()

  local zip_path = tt_shell.zip_file(dir, "time_report.html")

  if zip_path then
    return zip_path,
      "A full breakdown showing the start time, end time and duration of every "
        .. "individual session is attached (time_report.zip). Unzip it and open "
        .. "the HTML file in any web browser.",
      "Attach time_report.zip from the folder that just opened:\n" .. zip_path
  end

  -- Compression failed (no zip binary, permissions, read-only volume).
  -- Fall back to the raw HTML rather than sending nothing at all.
  return html_path,
    "A full breakdown showing the start time, end time and duration of every "
      .. "individual session is attached. Save the HTML file and open it in a "
      .. "web browser.",
    "Could not create a zip archive, so attach the HTML directly:\n" .. html_path
end

-- REAPER's GetUserInputs returns fields comma-separated, so a comma typed into
-- one field would split it into two. Stripping commas is lossy but predictable;
-- silently mangling the client's name would be worse.
local function sanitise(s)
  return (tostring(s or ""):gsub(",", " "):gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

-- Prompts for recipient details, opens a draft, and reveals the report folder.
-- Returns true if a draft was opened, false if the user cancelled or errored.
function email.compose(data)
  local attach_path, attachment_note, ui_hint = prepare_attachment()

  -- All three persist (persist flag = true), so a repeat send to the same
  -- client is a matter of pressing OK.
  local ok, input = reaper.GetUserInputs("Email Time Report", 3,
    "Client email address:,Client name (for greeting):,Your name (for sign-off):,extrawidth=220",
    table.concat({
      reaper.GetExtState(EXT_SEC, EXT_KEY_EMAIL),
      reaper.GetExtState(EXT_SEC, EXT_KEY_CLIENT),
      reaper.GetExtState(EXT_SEC, EXT_KEY_SENDER),
    }, ","))
  if not ok then return false end

  local address, client_name, sender_name = input:match("^([^,]*),([^,]*),(.*)$")
  address = sanitise(address)
  client_name = sanitise(client_name)
  sender_name = sanitise(sender_name)

  if not address:match("^[^@%s]+@[^@%s]+%.[^@%s]+$") then
    reaper.ShowMessageBox("That doesn't look like a valid email address.",
      "TimeTracker - Email Report", 0)
    return false
  end

  local body, body_err, period = build_body(data, attachment_note,
    client_name, sender_name)
  if not body then
    reaper.ShowMessageBox(body_err, "TimeTracker - Email Report", 0)
    return false
  end

  reaper.SetExtState(EXT_SEC, EXT_KEY_EMAIL, address, true)
  reaper.SetExtState(EXT_SEC, EXT_KEY_CLIENT, client_name, true)
  reaper.SetExtState(EXT_SEC, EXT_KEY_SENDER, sender_name, true)

  -- The subject names the period covered, not the day the mail happened to be
  -- sent, so it stays meaningful in the client's archive months later.
  local subject = period and ("Time report: " .. period)
    or ("Time report -- " .. os.date("%d %B %Y"))

  tt_shell.open(string.format("mailto:%s?subject=%s&body=%s",
    tt_shell.urlencode(address),
    tt_shell.urlencode(subject),
    tt_shell.urlencode(body)))

  if attach_path then
    tt_shell.open(tt_paths.get_data_dir())
  end

  reaper.ShowMessageBox(
    "A draft has been opened in your mail client.\n\n" .. ui_hint
      .. "\n\nReview the draft before sending.",
    "TimeTracker - Email Report", 0)

  return true
end

return email
