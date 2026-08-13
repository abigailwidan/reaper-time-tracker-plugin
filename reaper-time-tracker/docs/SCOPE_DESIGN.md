# Scope & Design Documentation

## Overview & Motivation

This project is a REAPER ReaScript tool that automatically tracks how long a user actively works within a REAPER project. It is not an audio-DSP effect (sound modification created using Digital Signal Processing) — no signal ever passes through it — and it makes no claim to musical or sonic contribution. Its scope sits entirely in the business layer of freelance creative work: solving the practical problem of accurate, low-effort time logging for creatives who bill hourly.

## Value Proposition

Many creatives working on commission — mixers, composers, sound designers — charge per hour. Manually tracking that time is tedious and easy to neglect, and even honest freelancers can under- or over-estimate hours worked from memory. This creates a quiet but real trust problem: the commissioner has no way to verify the invoice beyond the creative's word.

This tool removes the manual step entirely. It records active REAPER usage automatically, per project, and turns that record into a report the creative can hand to the commissioner alongside an invoice. The relationship shifts from "trust me" to "here's the log" — verifiable honesty in place of a good-faith estimate. The tool doesn't need to understand or touch the audio to deliver this value; it only needs to know when the user is working.

## Architecture

The system has four components:

**1. Background tracking loop.** A ReaScript running via `defer()` polls, once per second, whether REAPER is the OS foreground window, using `JS_Window_GetForeground` from the js_ReaScriptAPI extension. This runs independently of REAPER's audio engine, so tracking continues (or correctly pauses) regardless of playback state. The check also confirms the foreground window's top-level ancestor belongs to *this* REAPER instance (via `reaper.GetMainHwnd()`), so a second open instance can't be mistaken for this one — see PLAN.md for the exact API sequence.

**2. Per-project accumulation.** Time is not logged as a single global total. Each REAPER project (identified by a persistent GUID — see Project Identity, below) accumulates its own duration. When the user switches project tabs, the active timer for the previous project is stopped and the timer for the newly active project starts — so a session spanning multiple client projects splits correctly without manual intervention. Very short focus blips (under 5 seconds) are discarded as noise, and sessions on the same project separated by a small gap (under 15 seconds) are merged into one — see PLAN.md for the fixed thresholds.

**3. Persistence.** Tracked time is written to a local JSON file, structured per project with a chronological log of individual work sessions (start time, end time, duration). The file is autosaved at a fixed 45-second interval rather than only on close, so a REAPER crash or forced quit loses at most the current interval, not the whole session. Writes are atomic (temp file + rename) to avoid corrupting the log mid-write.

**4. Report generation.** A separate "Generate Report" script reads the JSON file and produces a static, self-contained HTML file — a bar chart of hours per project, a chronological session log, and totals — which opens automatically in the default browser. This is deliberately a generated offline document rather than a hosted dashboard: no server, no account, no ongoing dependency. The creative runs the script, gets a file, and sends that file (or its contents) to the commissioner.

## Project Identity

Each project is tracked by a persistent GUID (via `reaper.genGuid()`, stored in the project's own ExtState), not by file path, so tracking survives renames and moves. The GUID is assigned in memory as soon as the project is seen, but the ExtState write that actually persists it — and, as a side effect, marks the project dirty — is deferred until the project has a first qualifying session (≥5 seconds of real focus). This means simply opening and closing a project never prompts an unrelated save.

Save As is treated as a new billable project: rather than assuming REAPER won't carry the GUID over into the duplicated file, the tracker actively detects a Save As (project pointer unchanged, path changed) and overwrites the ExtState with a fresh GUID, since ExtState copying on Save As is standard REAPER behaviour for project state in general and can't be assumed away. Unsaved ("Untitled") projects get a temporary, session-only GUID; if the project is saved before REAPER closes, its accumulated time is migrated to the new real GUID, otherwise it's orphaned in the JSON as a known limitation.

Full mechanics — exact API calls, detection logic, and the values for all fixed thresholds — live in PLAN.md rather than being duplicated here, to avoid the two documents drifting out of sync.

## Technology Choice Rationale

ReaScript was chosen over the two other options the brief allows:

- **JSFX** was ruled out because it has no OS-level window-focus access and only executes during audio processing — it cannot run passively in the background when REAPER is idle or the transport is stopped, which is precisely when a lot of tracked time occurs (e.g. mixing decisions made while REAPER is paused).
- **VST3** was ruled out because it would require the full plugin lifecycle (instantiation in a track/FX chain, host processing callbacks) purely to host a background timer with no DSP function — significant overhead for no corresponding benefit.

ReaScript's `defer()` loop runs independently of the audio engine and has direct access to project and window state via the API, making it the lightest-weight fit for a tool whose entire job is passive background observation.

The tool depends on the **js_ReaScriptAPI** extension for `JS_Window_GetForeground`, since REAPER's native ReaScript API has no OS-level window-focus query. This is a widely-used, actively maintained community extension, not a fringe dependency, but it is external to stock REAPER. If it isn't installed, the script detects this on startup, alerts the user with a message pointing to the extension's installation via ReaPack, and exits gracefully rather than failing silently or logging incorrect data.

## Known Limitations & Scope Boundaries

- **Single-machine scope.** Tracking data lives in a local JSON file with no cross-device sync. A freelancer alternating between a studio machine and a laptop would get two separate, unmerged logs. This is a stated boundary of the current scope, not an oversight — merging or syncing logs is a reasonable extension but adds complexity (conflict resolution, storage/auth) disproportionate to a Project 5 submission.
- **Focus-based tracking can over-count** if REAPER is left focused while the user steps away — see Key Design Decisions, below.
- **Unsaved-project time can be lost.** If a project is never saved before REAPER closes, its temporary-GUID session data is orphaned in the JSON permanently rather than reconciled to a real project — see Project Identity, above.
- **No DSP or audio involvement.** The tool has no bearing on mix quality or audio output; its correctness is measured by accuracy of time logging, not audio fidelity.

## Key Design Decisions

**Focus-based tracking, not idle detection.** Time is counted whenever REAPER is the OS-focused window, and paused the moment focus moves elsewhere. This was a deliberate choice over adding mouse/keyboard idle detection. A large amount of genuine creative work — listening back to a take, sitting with an arrangement, thinking through an edit — involves no mouse or keyboard input at all. An idle timer would misclassify this as inactivity and under-bill for real work, which is a worse failure mode for this tool's purpose than the alternative.

The known limitation is honest and unresolved by design: a user could leave REAPER focused while away from their desk, which would over-count. This is not treated as solved. Focus-based tracking is presented as the more defensible default for this specific use case — protecting against under-billing genuine thinking/listening time — rather than a general-purpose activity tracker, and the report format (session-by-session log, not just a total) gives the commissioner visibility to sanity-check unusually long uninterrupted sessions if needed.