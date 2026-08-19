# REAPER TimeTracker

## Overview & Motivation
A background REAPER ReaScript designed to automatically track active work time within projects, operating independently of audio DSP.

**Demo:** [Watch the demo video](docs/demo.mov) to see TimeTracker in action—tracking project tabs, detecting focus, auto-saving, and generating reports.

## Value Proposition
Automates verifiable time logging for hourly-billed creatives to provide transparent records for commissioners.

## Architecture
1. Background tracking loop via `defer()`
2. Per-project accumulation using ExtState GUIDs
3. Persistence via JSON with 45-second atomic autosaves
4. Static HTML report generation

## Project Identity
Projects are identified using persistent GUIDs. *Confirmed:* `reaper.genGuid()` outputs braces, which are stripped for JSON keys. "Save As" detects path changes and forces a new GUID overwrite.

## Technology Choice Rationale
ReaScript and `js_ReaScriptAPI` provide optimal OS-level window-focus access without the overhead of maintaining a plugin lifecycle.

## Known Limitations & Scope Boundaries
Single-machine scope, potential focus-based over-counting, and unsaved-project temporary GUIDs remaining orphaned.

## Key Design Decisions
Relies on OS window focus rather than input idle detection to ensure contemplative work (listening/reviewing) is credited.

## File Structure

```text
reaper-time-tracker/
├── Scripts/
│   ├── TimeTracker_Background.lua      # defer() loop, tracks active project
│   └── TimeTracker_GenerateReport.lua  # reads JSON, writes HTML, outputs plain text path string
├── lib/
│   ├── tt_json.lua                     # vendored pure-Lua JSON encode/decode
│   ├── tt_paths.lua                    # resolves data file location via reaper.GetResourcePath()
│   ├── tt_project_id.lua               # project identity resolution
│   ├── tt_deps.lua                     # js_ReaScriptAPI presence check
│   └── tt_report_html.lua              # HTML/CSS/chart template as a Lua string
├── docs/
│   ├── DOCS.md
│   └── README.md                       # install via ReaPack, first-run instructions
├── tests/
│   ├── extstate_carryover_test.lua     # Verifies ExtState data persistence across project tabs and restarts
│   ├── extstate_test.lua               # Validates basic writing/reading of ExtState for GUID tracking
│   ├── basic_test.lua                  # General sandbox for isolated API testing
│   └── while_true_do_end_test.lua      # Tests background loop execution and blocking UI behavior
└── data/                               # NOT shipped — created at runtime