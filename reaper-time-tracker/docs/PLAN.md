# Plan

Data lives under `reaper.GetResourcePath() .. "/Data/TimeTracker/time_data.json"` — REAPER's own per-user resource path, not the script folder, so it survives ReaPack updates and works identically cross-platform.

**One JSON file, not one per project** — matches DOCS.md's "reads the JSON file" (singular) for the report script, and avoids a directory-listing step just to build the report.

## JSON Schema

```json
{
  "version": 1,
  "projects": {
    "b3f1a2c4-...": {
      "display_name": "ClientX_Mix_v3.RPP",
      "last_known_path": "/Users/abi/Projects/ClientX/ClientX_Mix_v3.RPP",
      "total_seconds": 12345,
      "sessions": [
        {
          "start": "2026-08-10T14:02:11+02:00",
          "end": "2026-08-10T15:47:02+02:00",
          "duration_seconds": 6291
        }
      ]
    }
  }
}
```

- `version` lets the report script (or a future migration) detect schema changes.
- `last_known_path` is display-only, refreshed each session — never used as the lookup key (see identity section below).
- Timestamps in ISO 8601 with UTC offset, so durations aren't corrupted by DST or a mid-session clock change.

## Tracker ↔ Report Interface

The report script's only contract:
- Read `time_data.json` from the fixed resource path.
- Check `version` matches what it expects (currently `1`). If it doesn't match, show the message *"This report expects data version 1 but found version N. Update TimeTracker_GenerateReport.lua to match, or restore an older backup of time_data.json."*, write no HTML file, and exit cleanly.
- If the file fails to parse as JSON: rename it to `time_data.corrupted-<ISO8601 timestamp>.json`, show *"Your data file appeared corrupted and was saved as time_data.corrupted-<timestamp>.json for inspection."*, and exit without writing a report.
- Never assume REAPER is running, and never write back to the file (report generation is read-only, so it's safe to re-run anytime).
- Tolerate an empty `sessions` array or a project with `total_seconds: 0`.

This means the report script has **zero dependency on js_ReaScriptAPI** — worth stating explicitly, since someone could hand the JSON + report script to another machine without the extension installed and it should still work.

## Project Identity

Each project gets a GUID generated via `reaper.genGuid()` on first encounter, persisted inside the project file via `reaper.SetProjExtState`/`GetProjExtState`. This is the schema's lookup key (`projects.<guid>`). It survives rename and move since it travels with the file content, not the path. *(Confirm `genGuid()`'s exact return format during Milestone 2 — some REAPER versions wrap it in braces `{...}`; strip these before using as a JSON key if so.)*

- `last_known_path` stays purely for display, refreshed every session.
- **Unsaved ("Untitled") projects**: temporary in-memory GUID for that REAPER session only, sessions are still written to JSON under this GUID and labelled `"Unsaved Project"` — so time isn't silently lost. Detected via the same active-project tracking used for tab changes (below): each poll, `reaper.EnumProjects(-1, "")` gives the current project pointer and path. If a project pointer that previously had no path now has one, the project has just been saved for the first time in this session — migrate its accumulated sessions from the temporary GUID entry into a new entry keyed by the newly-assigned real GUID, then delete the temporary entry. If REAPER restarts before the project is saved, the temporary entry is orphaned permanently in the JSON — this is a documented limitation, not silently resolved.
- **Save As**: assumed to get a fresh GUID, but ExtState normally travels with a duplicated project, so this is **not** taken on faith. Detection: track `(project_pointer, path)` each poll via `EnumProjects`; if the path changes while the pointer stays the same, that's a Save As. On detection, explicitly overwrite the ExtState with a newly generated GUID rather than assuming the copy didn't happen. *(Confirm actual copy-on-Save-As behaviour during Milestone 2 testing — determines whether this override is strictly necessary or purely defensive.)*
- **First-run/legacy handling**: if a project has no GUID in its ExtState yet, generate one **in memory** immediately on first defer cycle (needed to track at all) — but do **not** call `SetProjExtState` yet, since that write is what marks the project dirty. Defer the actual ExtState write until the project's *first qualifying session* is recorded (see Edge Cases — minimum session length). This means opening a project, glancing at it, and closing it without doing any real work never marks it dirty or prompts a save.

## Dependency Check

- Checked at the very top of `TimeTracker_Background.lua`, before the first `defer()` call — test for `reaper.JS_Window_GetForeground` existing as a function, since that's the standard way to detect the extension (no package-name lookup needed).
- If missing: `reaper.ShowMessageBox` with a message pointing to installing js_ReaScriptAPI via ReaPack, then the script returns immediately — no defer loop registered, no data written, no crash.
- The report generator has no such check, since it never touches the extension.

## Timing Constants

Fixed values, not ranges, so behaviour is deterministic and testable:

- **Focus poll rate**: `defer()` runs at REAPER's native tick rate, but the script throttles its own `JS_Window_GetForeground` check to once per second via `reaper.time_precise()` comparisons — avoids unnecessary polling every tick.
- **Autosave interval**: 45 seconds (fixed, replacing the original 30–60s range).
- **Minimum session length**: sessions under 5 seconds are discarded outright — treated as noise (e.g. a stray alt-tab), not work.
- **Session merge gap**: two sessions on the *same* project separated by less than 15 seconds are merged into one continuous session, rather than logged as two — covers rapid alt-tabbing without inflating the session log.

## Edge Cases to Account For

- **REAPER crash/force quit** — autosave every 45s (see Timing Constants) plus atomic writes (write to a temp file, then `os.rename`) so a mid-write crash can't corrupt the whole log. On Windows, `os.rename` can fail if the destination already exists — remove the destination first (or use a platform check) before renaming.
- **Dangling open session on restart** — if the script starts and finds a session with a `start` but no `end`: set `end` to the data file's own last-modified timestamp (the last point a successful atomic write proves the session was still open) and compute `duration_seconds` from that, rather than guessing at "now."
- **Multiple REAPER instances** — get the foreground `HWND` via `JS_Window_GetForeground`, walk to its top-level ancestor (`JS_Window_GetRelated(hwnd, "ROOT")`, falling back to walking `JS_Window_GetParent` in a loop if `"ROOT"` isn't supported), and compare that to `reaper.GetMainHwnd()` for *this* instance. Only count focus if they match. *(Confirm the exact js_ReaScriptAPI call during Milestone 1 testing with two REAPER instances open.)*
- **Project closed/switched without saving** — tab/project change is detected every poll via `reaper.EnumProjects(-1, "")` comparing the active project pointer to the previous poll's; a change stops the outgoing project's timer and starts the incoming one's, independent of save state or window focus (a tab switch can happen without a focus change).
- **File renamed on disk outside REAPER** — handled by the GUID approach above; `last_known_path` just gets refreshed next session.
- **Save As duplicating a project** — new GUID explicitly assigned on detection (see Project Identity above); not assumed to happen automatically.
- **Focus flicker** (rapid alt-tabbing) — handled by the fixed minimum-session-length and merge-gap rules above.
- **Corrupted/partial JSON** — on parse failure, rename to `time_data.corrupted-<timestamp>.json` and continue with a fresh empty data structure (tracker) or exit with a pointer to the renamed file (report) — see Tracker ↔ Report Interface above.

## Build Order (each step independently testable)

1. **Dependency check + skeleton loop** — print current foreground state to console only; verify graceful exit when the extension is missing. Also confirm the multi-instance ownership check (`JS_Window_GetRelated`/`GetMainHwnd` comparison) works correctly with two REAPER instances open.
2. **Project identity module** *(expanded scope)* — on each throttled poll, read the project's GUID from `GetProjExtState`; if absent, generate one in memory via `reaper.genGuid()` (confirm its return format), deferring the actual `SetProjExtState` write until a qualifying session exists. Detect Save As via pointer/path tracking and force a new GUID on detection. Test by: opening a fresh project (in-memory GUID assigned, no dirty flag), doing 5+ seconds of focused work (ExtState now written, project dirty), renaming the file on disk (GUID persists), Save As (new GUID forced, confirm whether REAPER would have copied the old one anyway), and leaving a project unsaved (temporary GUID, cleared on restart unless saved mid-session). Log the resolved GUID + display name to console — no persistence to the tracker's JSON yet.
3. **In-memory session accumulation** *(expanded scope)* — start/stop timers on focus and project-tab changes; apply the minimum-session-length discard and merge-gap rules; handle the temporary-GUID-to-real-GUID migration when an unsaved project is saved mid-session. Still no disk writes; verify all boundaries via console log.
4. **JSON persistence** — atomic periodic writes every 45s; verify file contents after both a clean exit and a simulated crash (kill the process).
5. **Startup recovery** — dangling-session handling on script restart, using the last-modified-timestamp checkpoint method above.
6. **Report v1** — read JSON, output a plain HTML totals table, confirm it opens and matches the data. Confirm version-mismatch and corrupted-file messaging.
7. **Report v2** — add the bar chart and full session log.
8. **Edge-case hardening** — multi-instance handling (retest with the confirmed API from Milestone 1), focus-flicker filtering, corrupted-file fallback.
9. **Polish** — ReaPack packaging, README, final pass against DOCS.md.

## Items to Confirm During Build

These are settled *decisions* above, but rely on REAPER/js_ReaScriptAPI behaviour that hasn't been directly verified yet:

- **`reaper.genGuid()` return format** — confirm whether it's wrapped in braces (`{...}`) and whether stripping is needed for use as a JSON key. *(Milestone 2)*
- **ExtState behaviour on Save As** — confirm whether `SetProjExtState` data is actually duplicated into the new file (this determines whether the explicit GUID-override logic is load-bearing or just defensive). *(Milestone 2)*
- **`JS_Window_GetRelated(hwnd, "ROOT")`** — confirm this function/parameter exists in the installed js_ReaScriptAPI version; if not, fall back to walking `JS_Window_GetParent` manually. *(Milestone 1, retested at Milestone 8)*
- **`reaper.EnumProjects(-1, "")` pointer stability** — confirm the returned project reference stays comparable (`==`) across consecutive poll cycles for the same open project, which the tab-change and Save-As detection both depend on. *(Milestone 2/3)*
- **Whether `SetProjExtState` actually triggers REAPER's unsaved-changes indicator** as assumed — confirm this is what the deferred-write approach is protecting against, and that deferring it truly avoids the dirty flag for no-op opens. *(Milestone 2)*