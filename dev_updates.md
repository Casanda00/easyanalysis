# Development Updates log

This document tracks all developer actions, user requests (with timestamp), and changes made to resolve issues.

## [2026-06-23T00:25:53+03:00] User Request: Nested screens still not changing; broken color rules (3 shades of green)

### Reported Issues:
1. **Screen Switch Failure**: In the main application (not sandbox), clicking options under "Statistical Models" dropdown does not change the active screen.
2. **Color Theme Rule Broken**: The user requested exactly three shades of green to be used throughout the software. Some UI components or highlights contain colors outside this rule (e.g. Zephyr theme default blue accents, resizer active styling borders, etc.).

### Planned Actions:
1. **Add Diagnostic Console Printing** (Temporary):
   - Add an `observe` block in `server.R` to print `input$main_tabs` on change to verify if click events reach the server.
2. **Correct Non-Green CSS Rules**:
   - Change `.chat-ai` background from light blue (`#d1ecf1`) to light green (`#e8f5e9`).
   - Change `.chat-user` background from light grey (`#e9ecef`) to medium-light green (`#c8e6c9`).
   - Change the resizing sidebar border color from blue (`#0d6efd`) to green (`#4caf50`).
3. **Align Server-Side Tab Name Checks**:
   - Update tab value checks in `server.R` from old names (e.g. `"3. Linear Regression"`) to the new names (e.g. `"Linear Regression"`) to ensure matching works.

## [2026-06-23T00:47:05+03:00] User Request: Dropdown screens blocked; Random Forest not displaying; enforce three shared greens

### Work Completed:
1. Added explicit `value` fields for main navbar screens, including `Random Forest`, so screen switching uses stable Shiny tab IDs.
2. Raised navbar/dropdown z-index above the fixed footer and co-pilot layer, and lowered those fixed layers so dropdown clicks are not visually or interactively blocked.
3. Defined the shared green palette in CSS as three shades only for green UI accents:
   - Dark: `#2e7d32`
   - Medium: `#4caf50`
   - Pale: `#e8f5e9`
4. Overrode Bootstrap button/status/header variants so warning, danger, info, success, and primary actions stay within the green visual system.
5. Parse-checked `ui.R` and `server.R` with the installed R 4.5.3 `Rscript.exe`; both parsed successfully.

### Notes:
- `Rscript` was not on PATH, so validation used `C:\Program Files\R\R-4.5.3\bin\Rscript.exe` directly.
- `apply_patch` could not run because the Windows sandbox helper failed to start; edits were applied with PowerShell file patching instead.

## [2026-06-23T00:52:53+03:00] Fix: Restore dynamic app startup

### Issue:
- `shiny::runApp()` failed before the UI opened with: `path does not exist: 'VMI9-NEW.xlsx'`.

### Work Completed:
1. Removed startup reads of `VMI9-NEW.xlsx`, `VMI11-NEW.xlsx`, and `VMI12-NEW.xlsx` from `global.R`.
2. Kept dynamic upload handling intact in `server.R`; Excel files are still read only when the user uploads them through the UI.
3. Verified no hardcoded VMI Excel startup reads remain in `global.R`, `ui.R`, or `server.R`.
4. Parse-checked `global.R`, `ui.R`, and `server.R` successfully.
5. Confirmed `shiny::shinyAppDir('.')` builds the app object successfully after the fix.
