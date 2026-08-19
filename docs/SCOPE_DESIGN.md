# Scope & Design Documentation

## Overview & Motivation

This project is a REAPER ReaScript tool that automatically tracks how long a user actively works within a REAPER project. It is not an audio-DSP effect — no signal passes through it, and it makes no claim to musical or sonic contribution. Its scope sits entirely in the business layer of freelance creative work: accurate, low-effort time logging for creatives who bill hourly.

Many creatives working on commission — mixers, composers, sound designers — charge per hour. Manually tracking that time is tedious and easy to neglect, and even honest freelancers can mis-estimate from memory, leaving the commissioner no way to verify the invoice beyond the creative's word. This tool records active REAPER usage automatically and turns it into a report to hand over alongside the invoice — shifting the relationship from "trust me" to "here's the log," without needing to understand or touch the audio itself.

## Architecture

The system has five components:

| Component | What it does | Why it's built this way |
|---|---|---|
| **Background tracking loop** | `defer()`-based ReaScript polls window focus once/sec via `JS_Window_GetForeground` (`js_ReaScriptAPI`). Confirms the foreground window's top-level ancestor is *this* REAPER instance (`reaper.GetMainHwnd()`) — exact API sequence in `PLAN.md`. | Runs independently of the audio engine, so tracking is correct regardless of playback state, and a second open instance can't be mistaken for this one. |
| **Per-project accumulation** | Each project (persistent GUID, see Project Identity) accumulates its own duration. Tab switch stops the outgoing timer, starts the incoming one. Blips under 5s discarded; gaps under 15s merged — fixed thresholds in `PLAN.md`. | A session spanning multiple client projects splits correctly without manual intervention. |
| **Persistence** | Local JSON, per-project session log (start, end, duration). Autosaved every 45s, atomic writes (temp file + rename). | A crash or forced quit loses at most the current interval, not the whole session, and can't corrupt the log mid-write. |
| **Report generation** | Reads the JSON, produces a static self-contained HTML file: per-project LED meter, totals, and one chronological session log across all projects, newest first. Styled as a studio-console panel — colour chip per project (deterministic from GUID), "live" badge on a running session, print stylesheet for a clean PDF. | Deliberately an offline generated document, not a hosted dashboard — no server, no account, no ongoing dependency. A document handed to a client alongside an invoice is doing presentation work as well as reporting work. |
| **Email handoff** | After a report generates, offers a pre-addressed `mailto:` draft with billing figures already in the body. Standalone re-send action does the same without regenerating. Client email/name and sender name persist between sessions. | A handoff, not a send — see Key Design Decisions. |

The email body is composed to be sendable without editing — reasoning being that a half-finished message next to an invoice damages trust more than no message at all: client's name in the greeting (not a bare "Hi"), period covered (from session timestamps, not send date), each project in decimal hours (billing) and h/m (sanity-check), zero-time projects omitted, filenames cleaned of `.RPP`/underscores, signed off with the sender's name, subject naming the period rather than today's date.

## Project Identity

Each project is tracked by a persistent GUID (`reaper.genGuid()`, braces stripped for use as a JSON key), stored in the project's own ExtState rather than keyed by file path, so tracking survives renames and moves.

| Case | Handling |
|---|---|
| **Save As** | Treated as a new billable project. Rather than assuming REAPER won't carry the GUID into the duplicate, the tracker actively detects it (pointer unchanged, path changed) and overwrites ExtState with a fresh GUID — ExtState copying on Save As is standard REAPER behaviour and can't be assumed away. |
| **Unsaved ("Untitled") project** | Temporary, session-only GUID prefixed `TEMP-`. Saved before REAPER closes → accumulated time migrates to the real GUID. Otherwise orphaned in the JSON — a known limitation. |

Exact API calls, detection logic, fixed thresholds, and where the implementation currently deviates from plan live in `PLAN.md`, to avoid the two documents drifting apart.

## Technology Choice Rationale

ReaScript was chosen over the two other options the brief allows:

| Option | Verdict | Why |
|---|---|---|
| **JSFX** | Ruled out | No OS-level window-focus access, only executes during audio processing — can't run passively while REAPER is idle or the transport is stopped, which is precisely when a lot of tracked time occurs (e.g. mixing decisions made while paused). |
| **VST3** | Ruled out | Requires the full plugin lifecycle (track/FX-chain instantiation, host processing callbacks) purely to host a background timer with no DSP function — overhead with no corresponding benefit. |
| **ReaScript** | Chosen | `defer()` runs independently of the audio engine with direct API access to project and window state — lightest-weight fit for passive background observation. |

Depends on the community **js_ReaScriptAPI** extension for `JS_Window_GetForeground`, since stock ReaScript has no OS-level window-focus query. Widely-used and actively maintained, but still external to stock REAPER. If missing, the background script detects it on startup, points the user to installing it via ReaPack, and exits gracefully rather than failing silently or logging incorrect data. The report generator and email action carry no such dependency.

## Known Limitations & Scope Boundaries

| Limitation | Detail |
|---|---|
| **Single-machine scope** | Local JSON file, no cross-device sync — a freelancer alternating studio/laptop gets two unmerged logs. A stated scope boundary, not an oversight: merging/syncing adds conflict-resolution and storage/auth complexity disproportionate to a Project 5 submission. |
| **Focus-based over-counting** | REAPER left focused while the user steps away over-counts — unresolved by design; see Key Design Decisions. |
| **Unsaved-project time loss** | Never saved before REAPER closes → temp-GUID session data orphaned in the JSON permanently, rather than reconciled to a real project. |
| **Report scope chosen per send** | One `time_data.json` holds every client's work; an unfiltered report to one client would disclose the others' — a confidentiality failure, not untidiness. Both report generator and email action prompt for scope whenever 2+ projects exist, naming the disclosure risk explicitly rather than presenting the choice neutrally. |
| **Manual email attachment** | `mailto:` carries recipient/subject/body but no attachment mechanism. The tool opens the draft and reveals the report folder, leaving the user to drag the file in — a constraint of the no-credentials design, not an incomplete implementation. |
| **Report zipped for email** | Mail clients render bare `.html` as an unstyled inline preview, and corporate filters often quarantine `.html` as a phishing vector, so the report is compressed first (one extra step for the recipient). Falls back to raw HTML, with a note, if compression is unavailable. |
| **Email body length capped** | 1800 characters, truncated with a visible marker — several mail clients silently truncate long `mailto:` URIs, and a silent truncation would produce a half-finished summary the sender never sees. |
| **No DSP or audio involvement** | Correctness is measured by time-logging accuracy, not audio fidelity. |

## Key Design Decisions

| Decision | Why |
|---|---|
| **Focus-based tracking, not idle detection** | A large amount of genuine creative work — listening back, sitting with an arrangement, thinking through an edit — involves no mouse/keyboard input. An idle timer would misclassify this as inactivity and under-bill for real work, a worse failure mode here than over-counting. The over-counting risk (REAPER left focused while away from the desk) is left honest and unresolved by design, not treated as solved; the session-by-session log (not just a total) gives the commissioner visibility to sanity-check unusually long sessions if needed. |
| **`mailto:` handoff, not SMTP delivery** | Sending mail directly from Lua would mean shelling out to `curl` with the user's SMTP host and an app password stored somewhere on disk — in practice, plaintext in REAPER's resource folder. That buys an automatic attachment at the cost of the exact stored-credential dependency the rest of this design avoids, and would contradict the "no server, no account, no ongoing dependency" claim made for report generation. For a tool whose entire value proposition is *verifiable trust*, that trade isn't worth one saved drag-and-drop. A secondary benefit: because the body must be plain text, the per-project and grand totals are written directly into the email — the client sees the billable figures without opening anything, and the attached report exists to substantiate them rather than deliver them. |
