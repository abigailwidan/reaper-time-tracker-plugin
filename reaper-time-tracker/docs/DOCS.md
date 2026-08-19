# REAPER TimeTracker: Documentation & Development Plan

## 1. System Architecture & Data Flow

### 1.1 Core Mechanisms
*   **Background Polling:** The system utilizes a continuous `defer()` loop within `TimeTracker_Background.lua` to monitor the active state of REAPER.
*   **Focus Detection:** Contemplative work (listening/reviewing) is tracked by monitoring OS-level window focus rather than raw input idle time. 
*   **Window Management:** Multi-instance safety is ensured using `js_ReaScriptAPI` via `JS_Window_GetRelated("ROOT")` with a recursive `GetParent` fallback.
*   **Persistence:** Data is saved to a local JSON file with 45-second atomic autosaves to prevent data loss during crashes.

### 1.2 Project Identity & File Operations
*   **GUID Generation:** Projects are tracked using persistent GUIDs. Raw output from `reaper.genGuid()` includes braces, which the script actively strips to create clean JSON keys.
*   **"Save As" Handling:** The script detects path changes (e.g., when a user performs a "Save As" operation) and forces a new GUID overwrite to ensure discrete project tracking.
*   **Pointer Stability:** The system safely relies on `EnumProjects` pointers as stable references for active tabs.

---

## 2. File Reference

### 2.1 Main Scripts (User-Facing)
*   `Scripts/TimeTracker_Background.lua`: Manages the `defer()` loop, window focus polling, active project tracking, and autosaves.
*   `Scripts/TimeTracker_GenerateReport.lua`: Parses saved JSON data and renders the static HTML output. **Note:** HTML templates are embedded directly in this file, and the script outputs a plain text string of the generated file path (automated browser execution commands are strictly avoided).

### 2.2 Library Dependencies (`lib/`)
*   `tt_project_id.lua`: Manages ExtState, temporary in-memory GUIDs, and file operation detection.
*   `tt_json.lua`: Vendored JSON encode/decode utility.
*   `tt_deps.lua`: Validates the presence of `js_ReaScriptAPI` before execution.
*   `tt_paths.lua`: Resolves and manages data file locations and directory paths.

---

## 3. Development Plan & Implementation Status

### 3.1 Completed Milestones
*   [x] Establish background `defer()` loop.
*   [x] Implement OS window focus tracking via `js_ReaScriptAPI`.
*   [x] Configure GUID generation, brace-stripping, and "Save As" detection.
*   [x] Consolidate HTML template directly into the report generation script (bypassing the need for a separate `tt_report_html.lua`).
*   [x] Revert report execution logic to output a plain text string path to avoid automated path formatting failures.

### 3.2 Pending Tasks & Known Gaps
*   [ ] **JSON Error Handling (`TimeTracker_Background.lua`):** Implement safety logic for corrupted JSON files on startup. If parsing fails, the script must rename the corrupted file (e.g., to `data_corrupted.json`) rather than silently overwriting it with a fresh state.
*   [ ] **Orphaned GUIDs:** Investigate cleanup strategies for temporary GUIDs left behind by unsaved projects.

## 4. Known Limitations
*   Single-machine scope only.
*   Potential for focus-based over-counting if the REAPER window is left in focus while the user steps away from the workstation.