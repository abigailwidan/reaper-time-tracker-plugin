# REAPER TimeTracker

A background Lua ReaScript for REAPER that automatically tracks how long a user actively works within a project and generates verifiable HTML time logs for client billing[cite: 1].

## Features Implemented

*   **Passive Background Polling:** Uses `js_ReaScriptAPI` to poll OS-level window focus independently of the audio engine[cite: 1]. It tracks active work seamlessly, even when the transport is stopped[cite: 1].
*   **Robust Project Identity:** Tracks projects via persistent GUIDs stored in REAPER's `ExtState`, meaning time tracking survives file renames and moves[cite: 1, 2]. 
    *   *First Saves:* Gracefully migrates session data from a temporary in-memory GUID to a permanent one upon saving[cite: 1, 2].
    *   *Save As Detection:* Automatically detects duplicate project states and forces a new GUID so cloned projects do not share time logs[cite: 1, 2].
*   **Smart Session Logic:**
    *   *Noise Filtering:* Outright discards focus blips under 5 seconds[cite: 1, 2].
    *   *Merge Gaps:* Automatically merges sessions on the same project if the gap between them is less than 15 seconds, preventing rapid alt-tabbing from cluttering the log[cite: 1, 2].
*   **Crash-Proof Persistence:** Performs atomic disk writes (writing to a `.tmp` file before renaming) to a local `time_data.json` file every 45 seconds[cite: 1, 2]. 
*   **Startup Recovery:** If REAPER freezes or is force-quit, the script detects the dangling session on the next startup and cleanly caps the log using the last successful autosave timestamp[cite: 1, 2].
*   **Automated HTML Reporting:** Includes a standalone report generator script that reads the JSON data and outputs a self-contained HTML dashboard featuring a bar chart of relative project hours, project totals, and a full chronological session log[cite: 1, 2].

## File Structure
*   `Scripts/TimeTracker_Background.lua` - The core `defer()` loop and autosave engine.
*   `Scripts/TimeTracker_GenerateReport.lua` - Reads the JSON data, handles version/corruption checks, and builds the HTML dashboard.
*   `lib/` - Modular dependencies (`tt_deps.lua`, `tt_project_id.lua`, `tt_paths.lua`, `tt_json.lua`).