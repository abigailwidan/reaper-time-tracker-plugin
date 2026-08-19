# REAPER TimeTracker
A background ReaScript plugin that automatically tracks active work time within REAPER projects, providing transparent time logs for hourly-billed creatives and musicians.

<div align="center">

![Lua](https://img.shields.io/badge/Lua-232C2D72?logo=lua&logoColor=white)
![JSON](https://img.shields.io/badge/JSON-000000?logo=json&logoColor=white)
![HTML5](https://img.shields.io/badge/HTML5-E34F26?logo=html5&logoColor=white)
![CSS](https://img.shields.io/badge/CSS3-1572B6?style=flat-square&logo=css3&logoColor=white)
![REAPER](https://img.shields.io/badge/REAPER-1DB4EF?style=flat-square&logo=reaper&logoColor=white)
</div>

## Overview
 
TimeTracker automates verifiable time logging by monitoring active REAPER project focus and accumulating work hours. It eliminates manual time tracking whilst maintaining accurate records for billing and portfolio documentation.
 
**See it in action:** [Watch the demo video](reaper-time-tracker/docs/demo.mov)

## Key Features
 
- ✓ **Automatic project detection** — Tracks time per project with persistent GUIDs
- ✓ **OS-level window focus monitoring** — Credits contemplative work (reviewing/listening)
- ✓ **Atomic autosaving** — 45-second save intervals ensure data integrity
- ✓ **HTML report generation** — Export professional time logs with charts
- ✓ **Zero audio DSP overhead** — Runs independently in the background
- ✓ **Single-file architecture** — Pure ReaScript with vendored dependencies

## Origin
 
**Stellenbosch University Music Technology** — Project 5, 2026
 
A collaborative initiative to provide music professionals and students with transparent billing infrastructure for hourly creative work.

## Installation
 
### Requirements
- REAPER 6.82+ (tested on macOS)
- [`js_ReaScriptAPI`](https://forum.cockos.com/showthread.php?t=212174) extension (for OS window-focus access)

### Quick Start
 
1. **Install `js_ReaScriptAPI`:**
   - Download from the [Cockos forum thread](https://forum.cockos.com/showthread.php?t=212174)
   - Extract into your REAPER `UserPlugins` directory
   - Restart REAPER
2. **Install TimeTracker via ReaPack** (recommended):
   - Open REAPER → `Extensions` → `ReaPack` → `Browse Packages`
   - Search for `TimeTracker`
   - Install and enable
3. **Or install manually:**
   - Clone this repo: `git clone https://github.com/yourusername/reaper-time-tracker.git`
   - Copy `Scripts/` folder to your REAPER `Scripts` directory
   - Copy `lib/` folder to `Scripts/`
   - Load `TimeTracker_Background.lua` as a startup action
4. **Verify installation:**
   - Open REAPER and create a new project
   - Open `Actions` → find `TimeTracker: Start Background Tracking`
   - Run the action; you should see tracking begin in the console

## Usage
 
### Start Tracking
- Action: `TimeTracker: Start Background Tracking` (recommended as startup action)

### Generate Report
- Action: `TimeTracker: Generate Report`
- Opens an HTML report in your default browser with:
  - Total hours by project
  - Per-session breakdowns
  - Visual charts and timelines

### Data Location
- Tracking data stored in: `REAPER_RESOURCE_PATH/TimeTracker/data.json`
- Reports exported to desktop by default


## Architecture
 
```
reaper-time-tracker/
├── README.md
├── .gitignore
├── Scripts/
│   ├── TimeTracker_Background.lua      # Main tracking loop (defer-based)
│   └── TimeTracker_GenerateReport.lua  # Report generation & export
├── lib/
│   ├── tt_json.lua                     # Vendored JSON encoder/decoder
│   ├── tt_paths.lua                    # Data directory resolution
│   ├── tt_project_id.lua               # Project GUID management
│   ├── tt_deps.lua                     # Dependency verification
│   └── tt_report_html.lua              # HTML/CSS report template
├── docs/
│   └── DOCS.md                         # Technical documentation
└── tests/
   ├── extstate_test.lua                # ExtState persistence
   ├── extstate_carryover_test.lua      # Cross-session data integrity
   ├── basic_test.lua                   # Sandbox testing
   └── while_true_do_end_test.lua       # Loop execution verification
```
 
## Technical Highlights

### Design Decisions
- **ReaScript + `js_ReaScriptAPI`** — Optimal OS-level window access without plugin compilation overhead
- **ExtState persistence** — Leverages REAPER's built-in project metadata for data durability
- **Deferred loop architecture** — Non-blocking background execution via `defer()`
- **Window focus over idle detection** — Ensures listening/reviewing work is properly credited
### Project Identity
Projects are identified by persistent GUIDs generated via `reaper.genGuid()`. "Save As" operations force a new GUID to prevent data merging between separate projects.
 
## Known Limitations
 
- **Single-machine scope** — Does not sync across networked machines
- **Unsaved projects** — Temporary GUIDs for unsaved projects may orphan tracking data if not saved
- **Focus-based detection** — Could over-count in multi-monitor setups with manual focus switching

## License
To be determined

## Contributing
 
We welcome contributions! Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes with clear messages
4. Submit a pull request with documentation
For significant changes, please open an issue first to discuss proposed changes.
