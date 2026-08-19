# Plan

Data lives at `reaper.GetResourcePath() .. "/Data/TimeTracker/time_data.json"` — REAPER's own per-user resource path, not the script folder, so it survives ReaPack updates and works identically cross-platform. One JSON file for every project, not one file per project, so the report script never needs a directory-listing step.

## JSON Schema

```json
{
  "version": 1,
  "last_saved": 1755600000,
  "projects": {
    "b3f1a2c4-...": {
      "display_name": "ClientX_Mix_v3.RPP",
      "last_known_path": "/Users/abi/Projects/ClientX/ClientX_Mix_v3.RPP",
      "total_seconds": 12345,
      "sessions": [
        {
          "start_time": "2026-08-10T14:02:11+02:00",
          "end_time": "2026-08-10T15:47:02+02:00",
          "duration_seconds": 6291,
          "_raw_start": 1755500000,
          "_raw_end": 1755506291,
          "_is_active": true
        }
      ]
    }
  }
}
```

| Field                     | Meaning                                                                                                                                       |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `version`                 | Lets the report script (or a future migration) detect schema changes.                                                                         |
| `last_saved`              | Epoch time of the last successful atomic write. Startup recovery uses it as the checkpoint for closing a dangling session.                    |
| `last_known_path`         | Display-only, refreshed every session — never the lookup key (GUID is).                                                                       |
| `start_time` / `end_time` | ISO 8601 with UTC offset, so durations survive DST or a mid-session clock change. These are what the report displays.                         |
| `_raw_start` / `_raw_end` | Epoch equivalents for arithmetic and sorting, avoiding ISO reparsing. Underscore-prefixed = internal, not part of the client-facing contract. |
| `_is_active`              | Marks a session still accruing. Absent (not `false`) once finalised; its presence on load is what triggers crash recovery.                    |

Consumers must tolerate: an empty `sessions` array, a project with `total_seconds: 0`, and a session missing `_raw_start`/`_raw_end` (older files predate those fields — the report falls back to the raw ISO string).

## Tracker ↔ Report Interface

Implemented once in `lib/tt_data.lua` and shared by both consumer scripts so the contract can't drift between them.

| Rule                 | Detail                                                                                                                                                 |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Read path            | Fixed resource path, `time_data.json`.                                                                                                                 |
| Version check        | Must match `1`. Mismatch → show _"This report expects data version 1 but found version N..."_, write no HTML, exit cleanly.                            |
| Parse failure        | Rename to `time_data.corrupted-<timestamp>.json`, show a pointer to it, exit without writing a report.                                                 |
| Read-only            | Never assumes REAPER is running, never writes back — safe to re-run anytime.                                                                           |
| Failure reporting    | `tt_data.load()` returns a `kind` discriminator (`missing`/`empty`/`corrupt`/`version`) rather than acting on failure itself.                          |
| Quarantine ownership | Only `TimeTracker_GenerateReport.lua` renames a corrupt file — the email action reports and defers, so two scripts can't race to rename the same file. |
| Dependency           | Zero dependency on `js_ReaScriptAPI` — the JSON + report script can be handed to a machine without the extension and still work.                       |

## Email Handoff Interface

`lib/tt_email.lua` composes a `mailto:` URI and hands it to the OS default handler.

| Constraint                   | Detail                                                                                                                                                                                                                                                                                                        |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No attachments               | `mailto:` has no attachment mechanism (protocol limitation, not a gap). The draft opens, the report folder is revealed, and the exact filename is named.                                                                                                                                                      |
| Body cap                     | 1800 characters — Windows `ShellExecute` and several mail clients silently truncate long URIs. Truncated with a visible `[Summary truncated...]` marker.                                                                                                                                                      |
| Body carries the numbers     | Per-project + grand totals in the plain-text body (decimal hours for billing, h/m for sanity-checking), so the client can verify without opening the attachment. Grand-total line suppressed for a single-project report.                                                                                     |
| Sendable unedited            | Greeting uses the client's name (falls back to "Hello,"); sign-off uses the sender's name. Period is derived from earliest/latest `_raw_start`/`_raw_end`, collapsing to one date when applicable, and used in the subject line instead of the send date.                                                     |
| Display names cleaned        | `.RPP`/`.rpp` extensions and backup suffixes stripped, underscores → spaces: `ClientX_Mix_v3.RPP` → `ClientX Mix v3`. Display-only — GUID stays the identity.                                                                                                                                                 |
| Zero-time projects omitted   | A `0.00 hrs across 0 sessions` line is noise on an invoice-adjacent document.                                                                                                                                                                                                                                 |
| Fields collected & persisted | Client email, client name, sender name. `GetUserInputs` is comma-delimited, so commas are stripped from each field — lossy but predictable.                                                                                                                                                                   |
| Report zipped first          | Mail clients preview bare `.html` inline as unstyled text, and corporate filters often quarantine `.html`. `tt_shell.zip_file` uses `zip -j` (POSIX) / `Compress-Archive` (Windows); on failure, falls back to the raw HTML and adjusts the wording so the email never promises a format that isn't attached. |
| Address persistence          | `reaper.SetExtState(..., persist=true)` — survives a REAPER restart, typed once per client.                                                                                                                                                                                                                   |
| Validation                   | Address trimmed and pattern-checked before a draft opens, so a typo fails visibly.                                                                                                                                                                                                                            |

Full rationale for `mailto:` over SMTP: `SCOPE_DESIGN.md` → Key Design Decisions.

## Report Scope Selection

`tt_data.prompt_for_scope()` runs immediately after a successful load, before any HTML is written or draft composed.

| Aspect                | Detail                                                                                                                                                                  |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Why                   | One `time_data.json` holds every client's work. An unfiltered report to one client would disclose the others' — a confidentiality control, not a formatting preference. |
| When it fires         | Only when the file holds 2+ projects **and** the active REAPER project has a recorded GUID. Otherwise skipped.                                                          |
| Options               | Yes = every project. No = active project only. Cancel = abort, nothing written.                                                                                         |
| Active-project lookup | `reaper.GetProjExtState(0, "TimeTracker", "ProjectGUID")` — keeps the prompt free of any `js_ReaScriptAPI` dependency.                                                  |
| Scoping mechanism     | `scope_to_project` returns a filtered copy; the file on disk is never modified.                                                                                         |

## Project Identity

Each project gets a GUID via `reaper.genGuid()` on first encounter, persisted via `reaper.SetProjExtState`/`GetProjExtState`, and used as the schema's lookup key (`projects.<guid>`). Survives rename/move since it travels with the file content, not the path. `last_known_path` stays purely for display, refreshed every session.

_Confirmed during Milestone 2: `genGuid()` returns a brace-wrapped string; `lib/tt_project_id.lua` strips the braces before use as a JSON key._

| Case                             | Detection                                                                                                                                                                                  | Handling                                                                                                                                                                                                                                                                                                                                                                            |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Unsaved ("Untitled") project** | Same active-project tracking as tab changes: each poll, `reaper.EnumProjects(-1, "")` gives the current pointer + path. A pointer that previously had no path now having one = first save. | Temporary in-memory GUID prefixed `TEMP-` for that session; sessions still written to JSON under this GUID, labelled `"Unsaved Project"`. On first save, accumulated sessions migrate to a new entry keyed by the real GUID and the temp entry is deleted. If REAPER restarts before saving, the temp entry is orphaned permanently — documented limitation, not silently resolved. |
| **Save As**                      | Track `(project_pointer, path)` each poll; path changes while the pointer stays the same.                                                                                                  | Not taken on faith that ExtState won't travel with the duplicate — explicitly overwritten with a newly generated GUID on detection.                                                                                                                                                                                                                                                 |

## Dependency Check

| Step                            | Detail                                                                                                                                                        |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Where                           | Top of `TimeTracker_Background.lua`, before the first `defer()` call.                                                                                         |
| Test                            | `reaper.JS_Window_GetForeground` exists as a function — the standard extension-presence check, no package-name lookup needed.                                 |
| If missing                      | `reaper.ShowMessageBox` points to installing `js_ReaScriptAPI` via ReaPack; script returns immediately — no defer loop registered, no data written, no crash. |
| Report generator / email action | No such check — neither touches the extension.                                                                                                                |

## Timing Constants

Fixed values, not ranges, so behaviour is deterministic and testable.

| Constant                | Value           | Why                                                                                                                                                                                |
| ----------------------- | --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Focus poll rate         | 1/sec           | `defer()` runs at REAPER's native tick rate, but the script throttles its own `JS_Window_GetForeground` check via `reaper.time_precise()` comparisons to avoid polling every tick. |
| Autosave interval       | 45s             | —                                                                                                                                                                                  |
| Minimum session length  | 5s              | Sessions shorter are discarded as noise (e.g. a stray alt-tab), not work.                                                                                                          |
| Session merge gap       | 15s             | Two sessions on the _same_ project within this gap merge into one, covering rapid alt-tabbing without inflating the log.                                                           |
| Email body cap          | 1800 chars      | See Email Handoff Interface.                                                                                                                                                       |
| Report meter resolution | 24 LED segments | Colour zones are properties of ladder position, not value — matches real meter hardware.                                                                                           |

## Edge Cases to Account For

| Case                                         | Handling                                                                                                                                                                                                                                                                                                      |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| REAPER crash / force quit                    | Autosave every 45s plus atomic writes (temp file → `os.rename`); destination removed first since Windows' `os.rename` can fail if it already exists.                                                                                                                                                          |
| Dangling open session on restart             | End time set to the `last_saved` checkpoint in the file, `duration_seconds` recomputed from that (not "now"). Under the minimum session length → removed and subtracted from `total_seconds`. `atexit` also refreshes `last_saved` on a clean quit, so the same path closes out normal termination correctly. |
| Multiple REAPER instances                    | Foreground `HWND` via `JS_Window_GetForeground`, walked to its top-level ancestor (`JS_Window_GetRelated(hwnd, "ROOT")`, falling back to walking `JS_Window_GetParent`), compared to `reaper.GetMainHwnd()` for this instance. Only counts if they match.                                                     |
| Project closed/switched without saving       | Detected every poll via `reaper.EnumProjects(-1, "")` pointer comparison; stops the outgoing timer and starts the incoming one, independent of save state or window focus.                                                                                                                                    |
| File renamed on disk outside REAPER          | Handled by the GUID approach; `last_known_path` just refreshes next session.                                                                                                                                                                                                                                  |
| Save As duplicating a project                | New GUID explicitly assigned on detection, not assumed.                                                                                                                                                                                                                                                       |
| Focus flicker (rapid alt-tabbing)            | Handled by the fixed minimum-session-length and merge-gap rules.                                                                                                                                                                                                                                              |
| Corrupted/partial JSON                       | Report generator renames the file aside and exits with a pointer to it; the tracker logs the failure and continues with a fresh empty structure (see Known Deviations).                                                                                                                                       |
| HTML-significant characters in project names | `display_name` is user-controlled (from a filename); escaped (`&`, `<`, `>`, `"`) before the report template, percent-encoded before the `mailto:` URI.                                                                                                                                                       |
| Report with no data                          | Both tables render an explicit empty state; the email action reports nothing-to-send rather than opening a blank draft.                                                                                                                                                                                       |
| Multiple clients in one data file            | Scope prompt — see Report Scope Selection.                                                                                                                                                                                                                                                                    |
| Sessions missing epoch fields                | Period calculation skips them; if none have usable epochs, body falls back to "recorded to date" and subject to the send date.                                                                                                                                                                                |

## Build Order (each step independently testable)

1. **Dependency check + skeleton loop** — print foreground state to console only; verify graceful exit when the extension is missing, and correct ownership with two REAPER instances open.
2. **Project identity module** — resolve/generate the GUID per throttled poll; detect Save As and force a new GUID; log GUID + display name to console — no JSON persistence yet.
3. **In-memory session accumulation** — start/stop timers on focus and tab changes; apply minimum-session-length and merge-gap rules; handle temp-GUID-to-real-GUID migration. Still no disk writes.
4. **JSON persistence** — atomic periodic writes every 45s; verify file contents after a clean exit and a simulated crash.
5. **Startup recovery** — dangling-session handling on restart, using the `last_saved` checkpoint.
6. **Report v1** — read JSON, output a plain HTML totals table; confirm version-mismatch and corrupted-file messaging.
7. **Report v2** — LED meter, flattened chronological session log, deterministic ordering, HTML escaping, print stylesheet.
8. **Email handoff** — shared `tt_data` loader, cross-platform `tt_shell` open/zip helpers, `mailto:` composition, Yes/No prompt after report generation, standalone re-send action, per-send scope selection. Verify all four data-error paths, the zip fallback, both scope branches + cancel, and body composition with/without names.
9. **Edge-case hardening** — multi-instance handling, focus-flicker filtering, corrupted-file fallback.
10. **Polish** — ReaPack packaging, README, final pass against `SCOPE_DESIGN.md`.

## Known Deviations from This Plan

Recorded here rather than silently corrected above, so the plan and the implementation can be compared honestly.

| Deviation                                                    | Detail                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **ExtState write is immediate, not deferred**                | Plan called for deferring the `SetProjExtState` write until a project's first qualifying session, so opening-and-closing without real work never marks it dirty. `lib/tt_project_id.lua` writes immediately on first encounter of a saved project with no existing GUID. Consequence: merely opening an untracked project can mark it dirty and prompt a save on close. Deferred-write remains the intended design; not yet implemented. |
| **Tracker does not quarantine a corrupt file**               | Plan specified both consumers rename a corrupt file aside. Only the report generator does; the tracker logs the parse failure and starts fresh, leaving the corrupt file in place. Arguably safer (avoids two processes racing to rename the same file), but the corrupt file gets overwritten by the tracker's next autosave unless a report is generated first.                                                                        |
| **Recovery uses in-file `last_saved`, not filesystem mtime** | Plan specified the file's last-modified timestamp as the checkpoint. Implementation writes `last_saved` into the JSON on every save and reads that back instead — equivalent in practice, avoids a platform-specific `stat` call, but a different mechanism than planned.                                                                                                                                                                |
| **`os.date("%z")` assumed to return a numeric offset**       | ISO 8601 construction in `TimeTracker_Background.lua` assumes `%z` yields `+0200`-style output. On the Microsoft C runtime it can return a timezone _name_ instead, producing malformed timestamps. Untested on Windows.                                                                                                                                                                                                                 |
