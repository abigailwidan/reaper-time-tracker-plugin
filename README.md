# REAPER TimeTracker

A background ReaScript plugin that automatically tracks active work time within REAPER projects, providing transparent, client-ready time logs for hourly-billed creatives and musicians.

<div align="center">

![Lua](https://img.shields.io/badge/Lua-232C2D72?logo=lua&logoColor=white)
![JSON](https://img.shields.io/badge/JSON-000000?logo=json&logoColor=white)
![HTML5](https://img.shields.io/badge/HTML5-E34F26?logo=html5&logoColor=white)
![CSS](https://img.shields.io/badge/CSS3-1572B6?style=flat-square&logo=css3&logoColor=white)
![REAPER](https://img.shields.io/badge/REAPER-1DB4EF?style=flat-square&logo=reaper&logoColor=white)
![License](https://img.shields.io/badge/License-GPLv3-blue.svg)

</div>

## Why

Freelancers who bill by the hour — mixers, composers, sound designers — rely on manual time tracking or memory, which is tedious, easy to neglect, and gives the client no way to verify an invoice. TimeTracker closes that trust gap: it captures active REAPER usage per project automatically and turns it into a report you can hand over alongside the invoice. It has no effect on audio — it only watches window focus.

## Key Features

- ✓ **Automatic project detection** — tracks time per project with persistent GUIDs
- ✓ **OS-level window focus monitoring** — credits contemplative work (reviewing/listening)
- ✓ **Atomic autosaving** — 45-second save intervals with temp-file-then-rename writes
- ✓ **HTML report generation** — studio-console-styled report with per-project meters and a full session log
- ✓ **Client email handoff** — pre-addressed, client-ready `mailto:` draft with the report zipped for attachment
- ✓ **Zero audio DSP overhead** — runs independently in the background
- ✓ **Single-file-per-concern architecture** — pure ReaScript with vendored dependencies, no external services

## Origin

**Stellenbosch University Music Technology** — Project 5, 2026

A collaborative initiative to provide music professionals and students with transparent billing infrastructure for hourly creative work.

## Architecture

| Component | What it does |
|---|---|
| **Background tracking loop** | `defer()`-based ReaScript polls window focus once/sec via `js_ReaScriptAPI`, independent of the audio engine. |
| **Per-project accumulation** | Tracks time against a persistent GUID per project, not a global total. Tab switches stop/start the timer; blips under 5s are discarded; gaps under 15s are merged into one session. |
| **Persistence** | Local JSON file, one entry per project with a session log. Autosaves every 45s via a temp-file-then-rename atomic write. |
| **Report generation** | Reads the JSON and renders a static, self-contained HTML report — per-project LED meters, totals, and a full chronological session log — with a print stylesheet for saving as a PDF. |
| **Email handoff** | Opens a pre-addressed, client-ready `mailto:` draft (name, billing period, hours in decimal + h/m, sign-off). Zips the report and reveals its folder for manual attachment. No SMTP, no stored credentials. |

## Project Identity

Projects get a persistent GUID (`reaper.genGuid()`, braces stripped) stored in the project's own `ExtState` — not the file path — so tracking survives renames and moves.

| Case | Behaviour |
|---|---|
| **Save As** | Same project tab, changed path → a fresh GUID is written so the duplicate doesn't inherit the original's time log. |
| **Unsaved project** | Gets a temporary `TEMP-`-prefixed GUID. Saving before close migrates its data to a permanent GUID; closing without saving orphans it (documented limitation). |

## Technology Choice Rationale

| Option | Verdict | Why |
|---|---|---|
| **ReaScript** | Chosen | `defer()` runs independently of the audio engine with direct access to project/window state. |
| **JSFX** | Ruled out | No OS-level window-focus access; only executes during audio processing. |
| **VST3** | Ruled out | Full plugin lifecycle overhead just to host a background timer. |

Depends on the community `js_ReaScriptAPI` extension for window-focus queries. If missing, the background script warns and exits without tracking; the report generator and email action have no such dependency.

## Demo & Sample Output

- **`docs/sample-report.html`** — a generated report, opened in any browser.
- **`docs/TimeTracker Advert (Final).m4v`** — a promo video of the tool in use. It's kept locally in this folder but is **not tracked in git** (`.gitignore`) since it's well over GitHub's per-file size limit; ask whoever has it if you need a copy.

## Installation

### Requirements

- REAPER 6.82+ (tested on macOS)
- [`js_ReaScriptAPI`](https://forum.cockos.com/showthread.php?t=212174) extension (for OS window-focus access)

### Quick Start

1. Get the repo onto your machine, either:
   - `git clone https://github.com/abigailwidan/reaper-time-tracker-plugin.git`, or
   - on the [GitHub page](https://github.com/abigailwidan/reaper-time-tracker-plugin), **Code → Download ZIP** and unzip it.
2. In REAPER: **Options → Show REAPER resource path in finder**.
3. Copy the whole `reaper-time-tracker-plugin/` folder into the `Scripts` folder shown there.
4. **Actions → Show action list → New action ▾ → Load ReaScript…**, then load all three files from `reaper-time-tracker-plugin/src/`.
5. Install `js_ReaScriptAPI` via ReaPack (**Extensions → ReaPack → Browse packages**) if not already present, and restart REAPER.

`lib/` must remain a sibling of `src/`; the scripts resolve their modules via a relative `../lib/?.lua` path. The folder names themselves are not load-bearing, but that sibling relationship is.

### Verify installation

- Open REAPER and create a new project.
- Open `Actions` → find `TimeTracker_Background` and run it; you should see tracking begin in the console.

## Usage

| Action | Script | Notes |
|---|---|---|
| **Start tracking** | `TimeTracker_Background.lua` | Run once as a startup action (not a hotkey). Runs silently in the background. |
| **Generate report** | `TimeTracker_GenerateReport.lua` | Writes `time_report.html`, opens its folder, then offers to open an email draft. |
| **Email a report** | `TimeTracker_EmailReport.lua` | Re-sends an existing report without regenerating it. Prompts for client email / client name / sender name (persisted between runs). |

If the data file holds more than one project, Generate Report and Email a Report both ask whether to include every project or just the active one — so a report sent to one client can't disclose another client's project names and hours.

**Data location:**

| File | Path |
|---|---|
| Tracking data | `<REAPER Resource Path>/Data/TimeTracker/time_data.json` |
| Generated report | `<REAPER Resource Path>/Data/TimeTracker/time_report.html` |

## Known Limitations & Scope Boundaries

| Limitation | Detail |
|---|---|
| **Single-machine scope** | No cross-device sync — data is local only. |
| **Focus-based over-counting** | Time accrues whenever REAPER is the focused window, even away from the desk. |
| **Unsaved-project loss** | Never-saved projects are orphaned under a temporary GUID if REAPER closes first. |
| **Report scope per send** | Multi-project files prompt to scope down, rather than defaulting to "all" and risking cross-client disclosure. |
| **Commas stripped from names** | `GetUserInputs` is comma-delimited, so commas in a name would split the field — stripped instead of mangling it. |
| **Manual email attachment** | `mailto:` can't carry attachments; report is zipped (not raw `.html`) since mail clients often inline-preview or quarantine bare HTML. |
| **Email body length** | Capped at 1800 chars with a visible truncation marker — some mail clients silently truncate long `mailto:` URIs. |
| **No audio involvement** | Zero impact on audio output or mix quality. |

## Key Design Decisions

| Decision | Why |
|---|---|
| **Focus-based tracking, not idle detection** | Credits contemplative work (listening back, sitting with an arrangement) instead of misreading it as inactivity. |
| **`mailto:` instead of SMTP** | Sending mail directly would mean storing SMTP credentials in plaintext on disk — not worth it for a tool whose whole value is verifiable trust. Full argument in `docs/SCOPE_DESIGN.md`. |

## File Structure

```
reaper-time-tracker-plugin/
├── README.md
├── LICENSE                                 # GPLv3
├── .gitignore
├── docs/
│   ├── PLAN.md                             # implementation plan, schema, edge cases
│   ├── sample-report.html                  # example of generated report output
│   ├── SCOPE_DESIGN.md                     # scope, architecture, design rationale
│   └── TimeTracker Advert (Final).m4v      # promo video (local only, gitignored)
├── lib/
│   ├── tt_data.lua                         # read-only load, validation, report scoping
│   ├── tt_deps.lua                         # js_ReaScriptAPI presence check
│   ├── tt_email.lua                        # mailto: body composition and draft handoff
│   ├── tt_json.lua                         # vendored pure-Lua JSON encode/decode
│   ├── tt_paths.lua                        # data file locations via reaper.GetResourcePath()
│   ├── tt_project_id.lua                   # project identity, GUID assignment, Save As detection
│   └── tt_shell.lua                        # cross-platform open + zip helpers
├── src/
│   ├── TimeTracker_Background.lua          # defer() loop, tracks the active project
│   ├── TimeTracker_EmailReport.lua         # standalone re-send of an existing report
│   └── TimeTracker_GenerateReport.lua      # reads JSON, writes HTML, offers email draft
└── tests/
    ├── tt_json_test.lua                    # automated: lib/tt_json.lua round-trip (`lua tests/tt_json_test.lua`)
    ├── tt_data_test.lua                    # automated: lib/tt_data.lua's REAPER-free functions
    ├── basic_test.lua                      # manual: REAPER-console sandbox for genGuid/EnumProjects/dirty-flag
    ├── extstate_test.lua                   # manual: ExtState read/write/delete/namespace isolation
    ├── extstate_carryover_test.lua         # manual: GUID persistence across tab switches & restarts
    └── while_true_do_end_test.lua          # manual: confirms defer() doesn't block REAPER's UI/DSP

Runtime data is created under REAPER's own resource path
(<resource path>/Data/TimeTracker/) and is not shipped with the project.
```

The `tt_json` and `tt_data` tests are plain Lua with no REAPER dependency and can be run from a terminal. Everything else touches the `reaper` global and must be run as a loaded ReaScript inside REAPER, with the console open.

## License

Licensed under the [GNU General Public License v3.0](LICENSE). If you modify and distribute this project, your version must also be released as open source under GPLv3.

## Commit Messages

[Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <description>`

| Type | When |
|---|---|
| `feat` | New user-facing capability. |
| `fix` | Bug fix. |
| `chore` | Setup, tooling, config, dependencies. |
| `docs` | `.md` file changes. |
| `test` | Changes relating to tests. |
| `refactor` | Restructuring, no behaviour change. |
| `ci` | CI/pipeline config changes. |

**Scope** — the module touched, roughly matching this project's own `lib`/`src` split:

| Scope | Covers |
|---|---|
| `background` | `TimeTracker_Background.lua` — the `defer()` polling loop |
| `project-id` | `lib/tt_project_id.lua` — GUID assignment, tab/Save As detection |
| `data` | `lib/tt_data.lua`, `lib/tt_paths.lua`, `lib/tt_json.lua` — persistence, loading, report scoping |
| `report` | `TimeTracker_GenerateReport.lua` — HTML report generation |
| `email` | `TimeTracker_EmailReport.lua`, `lib/tt_email.lua`, `lib/tt_shell.lua` — the `mailto:` handoff |
| `deps` | `lib/tt_deps.lua` — `js_ReaScriptAPI` presence check |
| `docs` | `README.md`, `docs/*.md` |
| `tests` | `tests/` |
| `repo` | Root-level config — `.gitignore`, `LICENSE`, folder structure |

Example: `feat(email): add mailto draft composition`

This repo has no issue tracker wired up yet. If one gets added later, append the issue ID at the end: `feat(email): add mailto draft composition (TEA-10)`.

`develop → main` merges happen once reviewed and tested by another group member.

## Contributing

We welcome contributions! Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes following the format above
4. Submit a pull request with documentation

For significant changes, please open an issue first to discuss proposed changes.
