# REAPER TimeTracker

## Overview & Motivation
This tool is a REAPER ReaScript designed to automatically track active work time within REAPER projects. Operating entirely within the business layer of freelance creative work, it addresses the challenge of accurate, low-effort time logging for hourly-billed creatives. It functions independently of audio DSP and makes no modifications or contributions to the audio itself.  

## Value Proposition
Freelancers such as mixers, composers, and sound designers frequently bill by the hour. Manual time tracking is tedious and prone to neglect, while reliance on memory often leads to inaccurate estimates. This creates a trust gap between the creative and the commissioner, who lacks a way to verify invoices. 

The tool automates this process by capturing active REAPER usage per project. It converts this data into a verified report that can be provided alongside an invoice, shifting the dynamic from a good-faith estimate to a transparent record.

## Architecture
The system consists of four primary components:

- Background tracking loop: A ReaScript executed via `defer()` polls once per second to determine if REAPER is the foreground window using `JS_Window_GetForeground` from the `js_ReaScriptAPI` extension. This runs separately from the audio engine to track time regardless of playback state, confirming the top-level ancestor belongs to the specific REAPER instance via `reaper.GetMainHwnd()`.

- Per-project accumulation: Time is tracked per project using a persistent GUID rather than a global total. Switching project tabs stops the previous timer and starts the new one. Focus blips under 5 seconds are discarded, and sessions on the same project separated by less than 15 seconds are merged.

- Persistence: Data is written to a local JSON file structured by project with a chronological session log. Autosaves occur every 45 seconds using atomic writes (temporary file followed by a rename) to prevent corruption.

- Report generation: A separate script parses the JSON file to generate a static, self-contained HTML document featuring project totals and a chronological session log which opens automatically in the default browser.

## Project Identity
Projects are identified using persistent GUIDs generated via `reaper.genGuid()` and stored in the project's `ExtState`. The GUID is assigned in memory immediately, but the `ExtState` write is deferred until the project accumulates its first qualifying session (at least 5 seconds of real focus) to avoid marking unopened or briefly viewed projects as dirty.

- Save As Handling: To prevent cloned projects from sharing time logs, a Save As action (same project pointer, changed path) is detected and forces a new GUID overwrite.
- Unsaved Projects: Unsaved ("Untitled") projects are assigned a temporary session-only GUID. Saving before closing migrates the accumulated data to a new permanent GUID; otherwise, it remains orphaned in the JSON file as a documented limitation.

Technology Choice Rationale
- ReaScript: Chosen because its `defer()` loop runs independently of the audio engine and provides direct access to project and window state.
- JSFX: Ruled out because it lacks OS-level window-focus access and only executes during audio processing.
- VST3: Ruled out due to the high overhead of maintaining a plugin lifecycle purely for a background timer.

The tool relies on the external community extension `js_ReaScriptAPI` for window focus queries. If missing, the script detects the absence on startup, displays a message pointing to ReaPack, and exits gracefully.

## Known Limitations & Scope Boundaries
- Single-machine scope: Tracking data is stored locally without cross-device synchronization.
- Focus-based over-counting: Time is counted whenever REAPER is the focused window, which can over-count if left focused while away from the workstation.
- Unsaved-project loss: Data from projects that are never saved prior to closing is permanently orphaned under a temporary GUID.
- No audio involvement: The tool has no impact on audio output or mix quality.

## Key Design Decisions
Focus-based tracking over idle detection: Time is tracked based on OS window focus rather than mouse or keyboard input. This ensures that contemplative work, such as listening to takes or reviewing arrangements without active input, is properly credited.

## File Structure
```
reaper-time-tracker/
├── Scripts/
│   ├── TimeTracker_Background.lua      # defer() loop, tracks active project
│   └── TimeTracker_GenerateReport.lua  # reads JSON, writes HTML, opens browser
├── lib/
│   ├── tt_json.lua                     # vendored pure-Lua JSON encode/decode
│   ├── tt_paths.lua                    # resolves data file location via reaper.GetResourcePath()
│   ├── tt_project_id.lua               # project identity resolution
│   ├── tt_deps.lua                     # js_ReaScriptAPI presence check
│   └── tt_report_html.lua              # HTML/CSS/chart template as a Lua string
├── docs/
│   ├── DOCS.md
│   └── README.md                       # install via ReaPack, first-run instructions
└── data/                               # NOT shipped — created at runtime
```