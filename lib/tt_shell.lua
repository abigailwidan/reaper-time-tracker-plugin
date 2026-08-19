-- lib/tt_shell.lua
-- Cross-platform helpers for handing a URI or path to the OS, and for
-- compressing a file before it is attached to an email.
--
-- Exists because os.execute('open "..."') is macOS-only; calling it directly
-- fails silently on Windows and most Linux setups.

local shell = {}

-- Percent-encodes a string for safe inclusion in a URI query component.
-- CR/LF become %0D%0A, which is what mail clients expect for body line breaks.
function shell.urlencode(s)
  return (s:gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- Hands a URI (mailto:, https:) or a filesystem path to the OS default handler.
function shell.open(target)
  local os_name = reaper.GetOS()
  if os_name:match("^Win") then
    -- The empty "" is the window-title argument; without it, start treats the
    -- quoted target as the title and opens a blank console instead.
    os.execute('start "" "' .. target .. '"')
  elseif os_name:match("OSX") or os_name:match("macOS") then
    os.execute('open "' .. target .. '"')
  else
    os.execute('xdg-open "' .. target .. '" &')
  end
end

-- Compresses a single file into a sibling .zip archive.
--
-- Why this exists: mail clients (Mail.app, Gmail, Outlook) preview a bare
-- .html attachment inline as unstyled text rather than offering a download,
-- which destroys the report's layout, and many corporate filters quarantine
-- .html attachments outright as a phishing vector. A .zip is always treated
-- as a download, so the client gets an intact file that opens in a browser.
--
-- Returns the archive path on success, or nil if compression failed (caller
-- should fall back to attaching the original file).
function shell.zip_file(dir, filename)
  local os_name = reaper.GetOS()
  local sep = package.config:sub(1, 1)
  local base = filename:gsub("%.html?$", "")
  local zip_path = dir .. sep .. base .. ".zip"

  -- Both zip and Compress-Archive append to, or refuse, an existing archive.
  os.remove(zip_path)

  if os_name:match("^Win") then
    os.execute(string.format(
      'powershell -NoProfile -Command "Compress-Archive -Path \'%s\' '
        .. "-DestinationPath '%s' -Force\"",
      dir .. sep .. filename, zip_path))
  else
    -- -j junks the directory structure, so the client unzips to a bare file
    -- rather than a nested folder tree. -q keeps it silent.
    os.execute(string.format('cd "%s" && zip -j -q "%s" "%s"',
      dir, zip_path, filename))
  end

  local f = io.open(zip_path, "r")
  if f then
    f:close()
    return zip_path
  end
  return nil
end

return shell
