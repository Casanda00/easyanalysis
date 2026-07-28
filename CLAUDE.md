# CLAUDE.md — SimpleAnalysis Shiny App

Anchor context for working in this repo. Keep it short; update as constraints are discovered.

## Companion docs (read these for depth)
- **[DOCS.md](DOCS.md)** — **index of every document in the repo** (start here to find things, esp. after a context reset).
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — technical structure, state pools, module contract, memory management (§9), agent transport, (deprecated) browser build pipeline.
- **[DESIGN.md](DESIGN.md)** — audience, GeoLibre north star, layout idiom, the non-negotiable UX rules, agent UX.
- **[MEMORY.md](MEMORY.md)** — decision log, timeline, and the hard-won gotchas (terra wasm bug, shinylive pins, etc.).

## What this is
A **universal scientific analysis platform** — an R **Shiny** application for conducting
a very broad range of analyses: **statistical, machine learning, deep learning, spatial /
remote-sensing / LiDAR, time-series, survival, Bayesian, SEM**, and more. Users upload any
dataset, clean/engineer it, and run the appropriate method through point-and-click, aided
by an **AI Co-Pilot agent** that can run those analyses on request.

The **founding / reference domain** is Finnish NFI (National Forest Inventory / VMI) data
for forest trafficability & tree-growth modeling — that's where it started and where the
sample workflows come from — but the tool is deliberately **domain-general**: nothing in
the core is forestry-specific, and the goal is a single place to do rigorous analysis of
any kind of data without writing code. Keep this "universal tool" framing in mind when
adding features — prefer general-purpose capability over forestry-specific assumptions.

## Two builds from one codebase
- **Server build** (root `ui.R`/`server.R`/`global.R`) — classic Shiny via `runApp()` / shinyapps.io.
- **Browser build** (`webapp/` → `webapp_site/`) — the app compiled to **WebAssembly** via
  **Shinylive**. **DEPRECATED / being phased out.** The app is **LOCAL-FIRST**; the browser
  build proved too slow and limited (poor tester feedback). `webapp/` is a stale pre-Projects
  snapshot — do **NOT** invest in it or "re-sync" changes into it. Kept in ARCHITECTURE.md §6
  for reference only. **The server build run locally is the target.**

## Run it
- R lives at: `C:\Program Files\R\R-4.5.3\bin\Rscript.exe` (R 4.5.3). `Rscript` is **not** on PATH — call the full path (in PowerShell, prefix a quoted path with `&`).
- **Server build (THE way to run it — local-first):** the launcher runs the native app on the
  stable port 7788 and opens the browser:
  `& "C:\Program Files\R\R-4.5.3\bin\Rscript.exe" "<app>\launcher\run.R" "<app>"`
  (stop any old instance first so 7788 is free; override with `$EASYANALYSIS_PORT`). RStudio
  "Run App" or `Rscript -e "shiny::runApp(launch.browser=TRUE)"` also work.
- **Browser build:** DEPRECATED (see above) — do not build/serve it as part of normal work.
- Key package versions: **bslib 0.10.0**, **shiny 1.13.0** (Bootstrap 5).
- Secrets: `OPENAI_API_KEY` from `.Renviron` on the server build; in the browser build the user
  pastes their key into the Co-Pilot (gear icon) — it is **never hardcoded**.

## File layout
| File | Role |
|------|------|
| `project_store.R` | On-disk **projects = saved state**. Pure R (no Shiny), standalone-testable. |
| `mod_projects.R` | **Projects screen — the app's FIRST view.** Empty state + project cards. |
| `global.R` | Loaded once; shared libs, `app_theme`, and `source()`s each module (incl. `agent_tools.R`). |
| `ui.R` | `page_fillable` CSS-grid `.app-shell`; one `.viewPanel` per screen. |
| `server.R` | Shared reactive state (4 pools + `active_ds`) + wires each module server once. |
| `mod_*.R` | One self-contained Shiny module per screen (~35 modules). |
| `agent_tools.R` | AI Co-Pilot agent: OpenAI tool registry + dispatcher (runs the app's models). |
| `helpers.R`, `evaluation_function.R` | Shared plot engines + `uef_evaluation()`. |
| `webapp/` | Browser-build source (clean, secrets-free copy of the app). |
| `webapp_export.R` | Builds `webapp/` → `webapp_site/` with the wasm-specific patches. |
| `*_legacy.R` | Pre-rebuild monolith snapshot. **Not sourced.** Port logic FROM here. |

## AI Co-Pilot AGENT (mod_chat.R + agent_tools.R)
The Co-Pilot RUNS analyses, not just describes them, via OpenAI tool-calling.
`agent_tools.R` exposes `list_datasets` / `describe_dataset` / `run_analysis`
(methods: descriptive, lm, anova, ttest, lme, logistic, rf, clustering, pca) using the
app's own fitting functions. `mod_chat.R`'s `.ask_openai_agent()` runs the tool loop and
shows a transparency trace under each answer. Transport is dual-mode: `httr` on a server,
synchronous XHR via `webr::eval_js()` in the browser. (Browser build is DEPRECATED — no
`webapp/` re-sync needed anymore; edit the root files only.) Full details: ARCHITECTURE.md §5, MEMORY.md §4.

## File layout
| File | Role |
|------|------|
| `global.R` | Loaded once; shared libs, `app_theme`, and `source()`s each module. |
| `ui.R` | `page_navbar` shell; nav panels = one component each. |
| `server.R` | Shared reactive state (`raw_pool`, `dataset_pool`, `dataset_names`) + module wiring. |
| `mod_*.R` | One self-contained Shiny module per screen (e.g. `mod_linear_regression.R`). |
| `*_legacy.R` | Pre-rebuild monolith snapshot. **Not sourced.** Port logic FROM here. |
| `clean_vmi.R`, `evaluation_function.R` | Custom helper sources. |

## Current state: GeoLibre-inspired shell (incremental rebuild)
Rebuilding the UI from scratch as a single persistent frame (inspired by
github.com/opengeos/GeoLibre), adding one component at a time. The old single-file
UI is preserved in `*_legacy.R` for porting.

**Shell layout (`ui.R` = `page_fillable` with a CSS-grid `.app-shell`):**
- **Top menubar** — `.topMenu()`/`.topItem()` helpers; each item runs
  `Shiny.setInputValue('current_view', '<view>')` on click. Groups: Data /
  Models / Machine Learning / Spatial & LiDAR (ITD lives here).
- **Left rail** (`.app-left`) — global `fileInput("upload_files")` + clickable
  `uiOutput("datasets_list")` (each item sets `input$active_dataset`) + View Data button.
- **Center canvas** — `navset_hidden(id="canvas_view", ...)`, one `.viewPanel(value)` per view.
- **Right tools** — `navset_hidden(id="tools_view", ...)`, swapped in lockstep.
- **Status bar** (`.app-status`) — active dataset + dimensions.

**View switching:** `server.R` observes `input$current_view` and calls
`nav_select("canvas_view", v)` + `nav_select("tools_view", v)`. All view panels exist
at once (hidden); module servers are bound once. Default view = first panel (`data`).

**Global state (server.R owns it):** `raw_pool`, `dataset_pool` (reactiveValues);
`dataset_names` (reactive); `active_ds` (reactiveVal, set by rail clicks / newest upload);
`active_dataset()` (validated reactive). Upload + View Data modal are app-level.

## Module contract (canvas + tools split)
Each component exposes THREE things and is wired into the shell:
- `<name>CanvasUI(id)` → content for the center canvas (`.viewPanel("<view>", <name>CanvasUI("<id>"))`).
- `<name>ToolsUI(id)`  → content for the right tools panel.
- `<name>Server(id, dataset_pool, active_dataset, ...)` → called once in `server.R`.
Namespace everything with `ns()`. Done so far: **`mod_data.R`** (dataCanvasUI/dataToolsUI/dataServer).
`mod_linear_regression.R` still uses the OLD single `nav_panel` contract — must be
reshaped to canvas+tools before wiring.

Workflow per component: reshape → add `.viewPanel`s to both navsets → wire server →
verify build + `testServer` → **user confirms** → next.

## App-wide UX rules (non-negotiable — enforce in every module)
10. **No per-module dataset selector.** Modules NEVER show a `selectInput` / `uiOutput` for
    choosing a dataset. The active dataset is always driven by clicking in the left data rail,
    passed as the `active_dataset` reactive argument. Use `active_dataset()` directly in `.df()`
    or equivalent. Exception: spatial modules that must distinguish between pools
    (e.g. `vector_pool` vs `dataset_pool`) may show a single source picker labelled by type,
    but never a flat list of all datasets.
11. **Predictor/variable selectors use `selectizeInput(multiple=TRUE)`.** The rest of the app
    shows a dropdown multi-select with tag chips (selectize). Never use `checkboxGroupInput`
    for predictor selection — it wastes space and is inconsistent.
12. **No per-module plot download buttons.** A global JavaScript overlay already injects a PNG
    download button on hover over every `.shiny-plot-output` element. Do NOT add redundant
    `downloadButton(ns("dl_plot"), "Plot PNG", ...)` in module UIs. CSV/table/raster downloads
    still need their own `downloadButton` (data formats the hover can't handle).
13. **Spatial Annotator lives in Raster Analysis.** Annotation (draw shapes, label, export
    GeoJSON/CSV/COCO/GPkg/VOC) is an accordion panel inside `mod_raster.R`, not a standalone
    screen. Toggle "Draw mode" between "Operations" and "Annotate" in the map toolbar.

## PROJECTS = the app's saved state (`project_store.R` + `mod_projects.R`) — BUILT v0.7.16
The app now opens on a **Projects** screen, not on Data. A project is a **folder on disk**, so closing the
browser (or the whole app) and coming back resumes where the user stopped.
- Layout: `<home>/projects/<id>/{project.json, datasets.rds}`; `<home>` = `$EASYANALYSIS_HOME`, else
  `%LOCALAPPDATA%/EasyAnalysis`. Writes are **atomic** (temp file + rename).
- Tabular datasets are serialised into the project. **Spatial layers are stored as path REFERENCES** to the
  user's own files (never copy multi-GB .laz); a moved/deleted source is flagged `missing` on load.
- `server.R` owns `current_project`, `open_project()` (clear pools → rehydrate → restore active dataset +
  last view) and an autosave `observe()`. `.pool_names()` filters NULL-valued keys — see gotcha 14.
- `ui.R`: the `projects` viewPanel is FIRST in both navsets, which makes it the default view.
- Tests: `project_store` 22/22 standalone; server lifecycle 15/15; module render 15/15.
- **Not done yet:** reopening a project does not re-read spatial files back into the pools (`src_paths` is
  stubbed in the upload handler); no card previews; the tour button is a placeholder.

## Hard constraints / gotchas (learned the hard way)
14. **`reactiveValues[[k]] <- NULL` does NOT delete the key.** The name stays in `names()` with a NULL
    value, so anything counting/looping over pool names must filter NULLs (`.pool_names()` in server.R).
    This is the root cause of the older `ds_refresh` workaround too.
16. **`nav_select()` needs `session = session` when called from inside a MODULE.**
    `.switch_view()` in server.R is invoked from module observers (e.g.
    `projectsServer` → `open_project`). There `getDefaultReactiveDomain()` is the *module*
    session, so `nav_select("canvas_view", v)` looks for a NAMESPACED id, finds nothing, and
    **fails silently** — the pane stays `display:none`, its outputs stay suspended, and the
    screen sits on "recalculating" forever with **no error anywhere**. Always pass the
    top-level `session` explicitly. Symptom to recognise: a `renderUI` stuck recalculating,
    empty `.shiny-output-error`, and the target `.tab-pane` computed `display:none`.
17. **Outputs in hidden panes are SUSPENDED.** With `navset_hidden`, an output only renders
    once its pane is actually shown. A permanently "recalculating" output usually means the
    view never switched (see 16), not that the render is slow.
15. **`debounce()` never fires under `testServer`** — `session$elapse()` doesn't drive its timer, so
    debounced observers are untestable. The project autosave is a plain `observe()` for this reason; it
    only fires when a dependency actually changed. Don't reintroduce debounce without a test strategy.
1. **Quotes inside `tags$script`/`tags$style`.** JS/CSS lives inside an R double-quoted
   `HTML("...")` string. A literal `"` inside (e.g. `a[data-bs-toggle="tab"]`) **silently
   breaks R parsing of the whole file**. Use single quotes or no quotes in CSS/attr
   selectors (`a[data-bs-toggle=tab]`), or escape as `\"`.
2. **Do NOT hand-roll tab switching.** bslib + Bootstrap 5 switch `nav_panel`/`nav_menu`
   tabs natively via the `data-bs-toggle` attrs it emits, and sync `input$main_tabs`
   automatically (navbar `id`). A custom jQuery handler that `.hide()`s panes leaves an
   inline `display:none` Bootstrap can never clear → frozen tabs. This was the original bug.
3. **Every pane needs proper structure.** If a `nav_panel` renders without `id`/`active`/
   `html-fill-*` classes (check by dumping `as.character(ui)`), its parens/structure are
   wrong and bslib will mark the wrong pane active.
4. **Shiny modules:** namespace every `inputId`/`outputId` with `ns()` in the UI fn;
   `moduleServer` resolves them server-side. Pass shared state (`dataset_pool`,
   `dataset_names`) as **arguments**, not globals.
5. **Sidebar scroll:** in a `fillable` `page_navbar`, the `layout_sidebar` sidebar must
   scroll internally (`.sidebar { overflow-y:auto; max-height:100% }`) so expanding an
   accordion doesn't stretch the whole page.
6. **LiDAR 3D Viewer Disconnects (shinyapps.io):** Two causes: (a) `rgl` crashes on headless
   Linux unless `options(rgl.useNULL = TRUE)` is set **before** `library(rgl)` in `global.R`.
   (b) `lidR::readLAS()` loads the full point cloud into RAM before any display decimation —
   on shinyapps.io (≤1 GB RAM) this causes OOM for large files. **Fix:** call
   `readLASheader()` first, compute sampling fraction to cap at 500 k points, then
   `readLAS(filter = "-keep_random_fraction X")`. Display decimation (the snap_pts slider)
   still applies on top of this for the 3D viewer. Wrap `renderRglwidget` in `tryCatch`
   falling back to the static `scatterplot3d` render with a user notification.
7. **LME Convergence Errors (`iteration limit reached`):** `nlme::lme()` frequently fails to
   converge (`error code = 1`) in `mod_lme.R` if predictor variables are on vastly different
   scales, or if the model is over-parameterized. **Workaround:** Scale variables before
   fitting, or increase the optimizer limit via `control = lmeControl(opt = "optim", msMaxIter = 1000)`.
8. **Stale level pickers in Data module:** `delete_levels` selectInput is only refreshed when
   `input$delete_lvl_col` changes, NOT after merge/rename operations. **Fix:** call
   `updateSelectInput(session, "delete_levels", choices = ...)` at the end of each
   `apply_rename`, `apply_merge`, and `apply_delete_lvl` observer in `mod_data.R`.
9. **`uef_evaluation()` is available but unused:** `evaluation_function.R` defines
   `uef_evaluation(pred, obs)` → list(RMSE, R2, Bias, RelBias, RRMSE). It is sourced in
   `global.R` but NOT called in any model module. Use it in `lmServer`, `lmeServer`, and
   `rfServer` for the model metrics cards (call after fitting, pass `fitted(model)` and the
   observed response vector).

## Verify a change builds (without launching)
```sh
"C:\Program Files\R\R-4.5.3\bin\Rscript.exe" -e "suppressMessages({library(shiny);library(bslib);library(shinyWidgets)}); source('global.R'); source('ui.R'); source('server.R'); cat('OK', paste(class(ui),collapse=','), '\n')"
```
To inspect rendered tab structure: `as.character(ui)` and grep for `tab-pane`.

## Modules ported so far (canvas + tools contract, all on the new shell)
- `helpers.R` — shared plot engines: `show_placeholder`, `is_safe_cat`, `init_data`,
  `plot_relationships`, `plot_lm_diagnostics`, `plot_aov_diagnostics`. Sourced by `global.R`.
- `mod_data.R` — **Data & Exploration** (ETL toolbox + EDA). `dataCanvasUI`/`dataToolsUI`/`dataServer`.
- `mod_linear_regression.R` — **Linear Regression**. `lmCanvasUI`/`lmToolsUI`/`lmServer`.
- `mod_anova.R` — **ANOVA** (+ Tukey HSD). `anovaCanvasUI`/`anovaToolsUI`/`anovaServer`.
- `mod_lme.R` — **Linear Mixed Effects** (nlme::lme, button-triggered, Nakagawa R²/VIF).
- `mod_logistic.R` — **Logistic Regression** (nnet::multinom, confusion matrix/accuracy).
- `mod_rf.R` — **Random Forest** (button-trained, varImpPlot, button-triggered PDP).
- `mod_clustering.R` — **Clustering** (K-Means/Hierarchical + Gower/PAM; 6 diagnostic views).
- `mod_classification.R` — **Classification** (one-vs-all glm; F1/precision/recall, button-run).
- `mod_da.R` — **Discriminant Analysis** (9 methods + 5 assumption-check views; canvas is a
  `uiOutput` that switches on `main_mode`/`view`; optional pkgs guarded by requireNamespace).
- `mod_lidar.R` — **Spatial & LiDAR** (all 3 views share ONE `rv_lidar` state, so it's a
  single module wired with the same id `"lidar"`: Point Cloud/3D + CHM/ITD + Metric Eval).
  Extracted plot metrics are written to `dataset_pool` so they appear in the left rail.
- `mod_raster.R` — **Raster Analysis** (leaflet canvas; upload .tif/.img; crop/clip/mosaic/
  reproject/resample/band-calc/zonal-stats; exports to `dataset_pool`; `raster_pool` shared
  via `server.R`). `.to_wgs84()` and `.pal_colors()` are helpers defined locally — move to
  `helpers.R` before any module tries to reuse them.
- `mod_rs_search.R` — **Download Spatial Data** (formerly "Satellite Search & Download";
  leaflet map + draw toolbar; 14 sensors via `rstac`; COG streaming; cloud filter; map export).
All verified via build + `testServer`, and the **full app serves (HTTP 200)**.
**ALL 14 SCREENS ARE LIVE.** Statistical Models, Machine Learning, Spatial & LiDAR, and Spatial Analysis all done.
Note: module `conditionalPanel()` uses `ns = ns` so its JS `condition` resolves namespaced inputs.

## AI Co-Pilot (`mod_chat.R`) — DONE
Floating panel, app-level. `chatUI("chat")` in ui.R, `chatServer("chat", dataset_pool,
active_dataset, reactive(input$current_view), module_ctx)` in server.R. Uses OpenAI
(`OPENAI_API_KEY` from `.Renviron`; model in `.CHAT_MODEL`, default `gpt-4o-mini`).
**Rich context + vision:** every `mod_*.R` server (incl. `dataServer`) RETURNS
`list(context = <reactive>, plot = <function>)`. `server.R` collects them into `module_ctx`
keyed by view. On each send the Co-Pilot feeds the screen's dataset structure + fitted results
(text) AND captures the current plot to PNG→base64 via `capture_plot_as_base64()` (helpers.R,
needs `base64enc`), sent as an `image_url`. Strict system prompt: use ONLY the context+image,
never speculate, say so if no image. Model = `.CHAT_MODEL` (currently "gpt-5.4-nano" — **must be
vision-capable or it silently can't see plots**; switch to e.g. gpt-4o-mini to test).
Open/close: pure client-side `.open` class (FAB toggles; X = delegated `.copilot-x` click
handler — do NOT use inline onclick on a span, it was unreliable). Polished UI: gradient FAB,
slide-over panel, avatars, suggestion chips, screen subtitle, Enter-to-send, auto-scroll.

## DESIGN NORTH STAR: GeoLibre
The whole UI is modelled on GeoLibre (github.com/opengeos/GeoLibre) — slim top menubar, left
data rail, central canvas, right contextual tools, bottom status bar. Keep new screens in this
idiom. In particular the **Earth Engine screen, when enabled, should be map-centric** (leaflet
canvas + left/right panels) exactly like GeoLibre.

## LiDAR 3D snapshot (`mod_lidar.R`)
The interactive `rgl`/`rglwidget` cloud is browser WebGL — the server can't screenshot it (so AI
can't see it; no PNG). Added a **headless static 3D render** via `scatterplot3d` on a decimated
cloud (`snap_pts` slider) → downloadable + the image the Co-Pilot sees for LiDAR views. Chosen
over webshot2/Chrome because the target host is **shinyapps.io** (no reliable Chrome/WebGL).

## Earth Engine (`gee_dictionary.R` + `mod_gee.R`) — BUILT, NOT WIRED
Button-driven GEE via rgee, NO user code. `gee_dictionary()` = 24 popular ops in 8 groups
(Load / Filter / Composite / Indices / Terrain / Clip / Display / Extract-export); each entry
has `id,label,group,needs,params,run(state,p,aoi)`. `mod_gee.R` auto-generates buttons+inputs
from it and runs ops against a pipeline `ee` object; map = leaflet + `Map$addLayer`. Everything
is `requireNamespace()`-guarded so the app still builds without rgee/leaflet (canvas shows a
setup notice). **Deliberately un-wired:** rgee needs Python + a GEE account and does NOT run on
shinyapps.io. To enable later: `source()` both in global.R, add views to ui.R's two navsets +
a menu item, call `geeServer("gee")` in server.R — and build the canvas in the GeoLibre map idiom.

## Misc behaviours to know
- `options(shiny.maxRequestSize = 3*1024^3)` in global.R — allows large `.laz` uploads.
- Discriminant Analysis methods: LDA/WLDA/QDA/RLDA/KDA/LLDA/MMC only (RF & NN removed —
  they're general ML, RF has its own screen). Singular-matrix fits return a friendly hint.
- Classification screen = one-vs-all binary `glm(binomial)` per class (F1/precision/recall);
  distinct from the Logistic screen's single multinomial model.

## Wiring a component back (checklist)
1. Add its plot helper(s) to `helpers.R` if needed (port from server_legacy.R).
2. Create `mod_<name>.R` with `<name>CanvasUI(id)`, `<name>ToolsUI(id)`,
   `<name>Server(id, dataset_pool, active_dataset, ...)` — namespace all ids with `ns()`,
   read the dataset via `active_dataset()`, no own dataset picker.
3. `source("mod_<name>.R")` in `global.R`.
4. Replace the two `.todo()` placeholders for that view in `ui.R` (canvas_view + tools_view).
5. Add `<name>Server(...)` in `server.R`.
6. Verify: parse all + build `ui` + `testServer` driving the module's inputs/outputs.

---

## Phase 3 — Completed Changes (all verified with build check)

All 8 original changes from Phase 3 are complete. The 6 follow-up changes below are also done.

### 1. Rename label (trivial)
`ui.R` line 165 + `mod_rs_search.R` line 121: change `"Satellite Search & Download"` → `"Download Spatial Data"`.

### 2. Fix stale levels in Delete panel (`mod_data.R`)
After `apply_rename` / `apply_merge` / `apply_delete_lvl` each complete, call
`updateSelectInput(session, "delete_levels", choices = levels(rv$working_data[[col]]))`.
Currently only refreshed on column-change; post-mutation levels go stale. Extract a
`refresh_delete_levels()` helper inside `dataServer` and call it at the end of each handler.

### 3. Add RMSE / R² / Bias / RRMSE to model summaries
`uef_evaluation(pred, obs)` in `evaluation_function.R` already computes all four.
- `mod_linear_regression.R`: `uef_evaluation(fitted(model), model$model[[1]])` → new metrics card.
- `mod_lme.R`: same pattern alongside existing Nakagawa R² card.
- `mod_rf.R`: regression type → `uef_evaluation(model$predicted, obs)` (OOB preds); classification type → show OOB error rate instead.

### 4. Fix LiDAR crash on shinyapps.io (`global.R` + `mod_lidar.R`)
**Must do before Change 7** (Change 7 absorbs the upload handler).
- `global.R`: `options(rgl.useNULL = TRUE)` immediately before `library(rgl)`.
- `mod_lidar.R` upload: `readLASheader()` → compute fraction → `readLAS(filter="-keep_random_fraction X")` to cap at 500 k pts at read time, not just display time.
- Wrap `renderRglwidget` in `tryCatch`; fall back to static `scatterplot3d` render on error.
- `rv_lidar$raw_las` becomes the `LASheader` object (not the full LAS), saving RAM.

### 5. Data creation — users build datasets from scratch (`server.R`, `ui.R`)
- **"New Dataset" button** in left rail → modal with: dataset name field + `textAreaInput` for pasting CSV/TSV (Excel-compatible paste). Parsed with `read.csv(text=...)` → `init_data()` → into both pools.
- **Editable "View Data" modal**: change `DT::datatable()` in `server.R` to `editable = "cell"` + `observeEvent(input$view_table_cell_edit)` handler that writes back to `dataset_pool` via `DT::coerceValue()`.

### 6. LiDAR basemap — show location on leaflet (`mod_lidar.R`)
**Best after Change 7** (can use `las_pool` directly), but works before using `rv_lidar$las`.
- `lidarPointcloudCanvasUI`: split into `layout_columns(col_widths=c(5,7))` — left = `leafletOutput(ns("location_map"))`, right = existing 3D/static cards.
- After upload: `lidR::extent(las)` → project bbox to WGS84 (using LAS CRS) → `addPolygons` + `fitBounds` on a leaflet proxy.
- If CRS unknown: show `numericInput` for manual centre lat/lon → drop a circle marker instead.
- `leaflet` already a dependency via `mod_raster.R`.

### 7. Centralize all uploads in Datasets panel (`server.R`, `ui.R`, `mod_lidar.R`, `mod_raster.R`)
**Must precede Change 8** (`las_pool` needed by Surface module).
- `server.R`: add `las_pool <- reactiveValues()` and `vector_pool <- reactiveValues()`.
- `ui.R` left rail `fileInput`: expand `accept` to include `.tif/.laz/.las/.gpkg/.geojson/.shp`.
- `server.R` upload handler: `switch(ext)` routes by extension → tabular → `dataset_pool`; raster → `terra::rast()` → `raster_pool`; LAS → decimated `readLAS()` → `las_pool`; vector → `sf::st_read()` → `vector_pool`. Shapefiles are multi-file; write all parts to a `tempdir()` then read.
- `output$datasets_list`: show entries from all four pools with a small colour-coded dot per type (NO emoji — see DESIGN.md); active item sets `input$active_dataset` with a type prefix (`"tab:..."`, `"rst:..."`, etc.).
- `active_dataset()` reactive strips `"tab:"` prefix before indexing `dataset_pool`; model modules see no change.
- `mod_lidar.R`: remove `fileInput`; accept `las_pool` as server arg; `observe` latest entry in pool → `rv_lidar$las`.
- `mod_raster.R`: remove `fileInput`; the existing `observe` block syncing from `raster_pool` already does the work.
- Pass `las_pool` + `vector_pool` as args to `lidarServer` and `surfaceServer`.

### 8. Surface Models as standalone module (`mod_surface.R`) — **new file**
**Requires Change 7** (`las_pool` + `raster_pool` from server.R).
- New file `mod_surface.R`: `surfaceCanvasUI`/`surfaceToolsUI`/`surfaceServer(id, las_pool, raster_pool)`.
- Tools: input source picker (from `las_pool`), surface type radio (DTM/DSM/CHM/nDSM), resolution + algorithm params, output name, Run button, download.
- Canvas: leaflet map showing generated raster via `leafem::addGeoRaster()`.
- Move DTM logic (mod_lidar.R lines ~154-164) and CHM logic (~178-185) here.
- Result saved to `raster_pool[[output_name]]` → immediately visible in Raster Analysis.
- `mod_lidar.R` CHM/ITD view: replace inline DTM/CHM generation with a `selectInput` over `raster_pool` names to pick the CHM. Keep ITD unchanged.
- Wire: `source("mod_surface.R")` in `global.R`; add menu item "Surface Models" in `ui.R` Spatial Analysis dropdown; add `.viewPanel("surface", ...)` to both navsets; call `surfaceServer("surface", las_pool, raster_pool)` in `server.R`.
- **Before implementing:** move `.to_wgs84()` and `.pal_colors()` from `mod_raster.R` into `helpers.R` so `mod_surface.R` can reuse them without duplication.

### Phase 3 follow-up (6 items, all done)

1. **`names` error in `datasets_list`**: wrapped in `tryCatch` + helper `pool_nms()` with explicit NULL→`character(0)` guards.
2. **Dataset creation UX**: replaced CSV textarea with `rhandsontable` spreadsheet grid (`library(rhandsontable)` added to `global.R`). Modal has resize buttons and right-click row insert/delete. Blank rows auto-stripped; numeric-looking columns auto-coerced on save.
3. **Delete dataset**: each item in `datasets_list` gets a `×` button (inline, `event.stopPropagation()`). Server `observeEvent(input$delete_dataset)` removes from the appropriate pool.
4. **Undo in `mod_data.R`**: `prev_state <- reactiveVal(NULL)` + `snap()` helper called at the top of every `apply_*` handler. "↩ Undo" button restores previous state; "↺ Reset to Upload" restores from `raw_pool`. Both buttons are at the top of the tools panel (above the accordion).
5. **LiDAR CRS fallback**: replaced manual lat/lon inputs with (a) EPSG code textInput + "Apply CRS" button (calls `lidR::crs(las) <- sf::st_crs(code)`) and (b) draw toolbar on basemap (via `leaflet.extras::addDrawToolbar`). `input$location_map_draw_new_feature` → centre marker.
6. **LiDAR 3D view filters**: added `filter_z_ui`, `filter_intensity_ui`, `filter_class_ui` renderUI outputs (dynamic ranges from loaded LAS). `filtered_las_display()` reactive applies Z/intensity/classification filters. Apply/Reset buttons in the 3D Pre-Processing tools panel.

### Phase 3 follow-up round 2 (4 items, all done)

1. **Shapefile upload broken in LiDAR tools**: removed `fileInput(ns("lidar_file"), ...)` and `fileInput(ns("shp_file"), ...)` from `lidarPointcloudToolsUI`. All file uploads now go through the global left-rail "Add Data" handler. LAS comes from `las_pool`; vector/shapefile is picked from `vector_pool` via a `uiOutput(ns("shp_source_ui"))` selectInput.
2. **LiDAR basemap zoom**: fixed `las_bbox_wgs84` reactive — was checking `is.null(crs_obj$epsg)` which fails for CRS objects stored as WKT without an EPSG code. Now checks `is.na(crs_obj)` only. Replaced `lidR::extent(las)` + `@xmin` slot access with direct `las@data$X`/`$Y` min/max (works regardless of terra vs. raster Extent type). Basemap now fits bounds automatically after any LAS load.
3. **Undo/Reset button theme**: buttons now render inside a dark-green (`#2e7d32`) strip at the top of the Data tools panel — white ghost buttons on green background to match the app menubar.
4. **Dataset creation column headers**: modal now shows a "Column Names (comma-separated)" text input pre-filled with current names. "Apply" button renames `new_ds_df()` columns (uses `make.names()` to sanitize). Resize also updates the names field.

### Key gotcha: `rhandsontable` hot_context_menu

`hot_context_menu()` from rhandsontable accepts `allowRowEdit`, `allowColEdit`, and `customOpts`. Do NOT pass unknown parameters (e.g. `customOpts = list()` is fine; it renders without error).

### Key gotcha: LAS CRS detection

`sf::st_crs(las)$epsg` is NULL for many valid CRS objects (WKT-only, or non-EPSG authority). Always check `is.na(sf::st_crs(las))` — not `is.null($epsg)`. Likewise avoid `lidR::extent(las)@xmin` slot access; it fails on `terra::SpatExtent`. Use `las@data$X` min/max directly.

---

## Future Work Queue (document here so it survives context resets)

### Plain-English statistical interpretations
Every model screen should auto-generate a plain-language sentence like:
> "Group A (mean = 42.3) is significantly higher than Group B (mean = 38.1), p = 0.02. Effect size (Cohen's d) = 0.54 — moderate."

**Implementation approach:** template strings per module (fill with fitted values) OR route through the existing AI co-pilot `context()` reactive. Template example for t-test in `mod_tests.R`:
```r
.interp_ttest <- function(res, alpha=0.05) {
  sig <- res$p.value < alpha
  paste0(
    if(sig) "Significant difference detected" else "No significant difference",
    sprintf(" (t=%.3f, df=%.1f, p=%s).", res$statistic, res$parameter,
            format.pval(res$p.value, digits=3)),
    sprintf(" %s (mean=%.3f) vs %s (mean=%.3f).",
            names(res$estimate)[1], res$estimate[1],
            names(res$estimate)[2], res$estimate[2])
  )
}
```
Add one `verbatimTextOutput` / `uiOutput` card per module labelled "Interpretation". Priority: mod_tests.R, mod_anova.R, mod_linear_regression.R.

### Per-module download buttons (CSV for tables, PNG for plots)
**Global plot download already works** — a JavaScript overlay injects a `PNG` download button on hover over every `.shiny-plot-output` element (added to `ui.R` `tags$head` script block). No per-module code needed for R plots.

**CSV downloads** still need per-module `downloadButton` + `downloadHandler`. Standard pattern:
```r
# In ToolsUI or canvas card_footer:
downloadButton(ns("dl_results"), "Download CSV", class="btn-sm btn-outline-secondary", icon=icon("download"))

# In Server:
output$dl_results <- downloadHandler(
  filename = function() paste0("results_", Sys.Date(), ".csv"),
  content  = function(f) write.csv(result_df(), f, row.names=FALSE)
)
```
Modules that still need CSV download buttons: mod_descriptive.R (stats table), mod_tests.R (test results), mod_linear_regression.R (coefficients), mod_lme.R (coefficients), mod_rf.R (importance table), mod_clustering.R (cluster assignments), mod_da.R (confusion matrix), mod_xgboost.R (importance), mod_survival.R (KM table).

### Proactive data quality diagnostics
When a dataset loads (`active_ds()` changes), auto-scan and notify:
- Missing > 5% in any column
- Duplicate rows
- Near-constant columns (< 3 unique values in numeric)
- High skewness (|skewness| > 2) → suggest log transform before regression
- Suspected ID columns (unique count = n rows)

Add `.quality_check(df)` to `helpers.R` returning a named list of issues; call from `server.R` `observeEvent(input$active_dataset, ...)` via `showNotification()`. Also surface issues as a collapsed accordion panel in the Recommend canvas.

### Business framing for non-academic users
Seed question templates per domain in `mod_recommend.R`:
- Operations: "Which warehouse has the highest defect rate?" → classify
- HR: "Do remote workers perform differently?" → test  
- Marketing: "Which channel converts best?" → test / classify
- Finance: "Can I predict next quarter's revenue?" → predict / forecast

Add a "Domain" selector (General / Business / Ecology / Medicine) to `recommendToolsUI` that pre-populates the question input with example questions for that domain.

---

## Planned Expansion: Spatial & Remote Sensing (Phase 2)

### Goal
Extend SimpleAnalysis into a full GIS + remote sensing platform: raster/vector processing, satellite data
acquisition (Sentinel-2), change detection, image classification, and ML improvements.
**GEE and GEDI are excluded** — GEE needs Python + a GEE account and cannot run on shinyapps.io.

### New menu structure (additions to ui.R)
```
Raster & Vector  →  Raster Analysis | Vector Analysis | Change Detection | RS Classification
Remote Sensing   →  Sentinel-2
Spatial & LiDAR  →  (existing 3 views unchanged)
Machine Learning →  + XGBoost  (added to existing dropdown)
```

### New modules (5 spatial + 1 ML)

| Module | View key(s) | Canvas | Description |
|--------|-------------|--------|-------------|
| `mod_raster.R` | `raster` | Leaflet map | Upload `.tif`/`.img`; crop/clip/mosaic/reproject/resample; band math; zonal stats (`exactextractr`); download |
| `mod_vector.R` | `vector` | Leaflet map | Upload `.shp`/`.gpkg`/`.geojson`; buffer/intersect/union/dissolve/spatial-join; CRS transform; download |
| `mod_sentinel.R` | `sentinel` | Leaflet map | Draw AOI → query Sentinel-2 via `rstac`; download; indices (NDVI/NDWI/NBR/EVI/NDRE); cloud mask (SCL) |
| `mod_change.R` | `change` | Leaflet/plot | Two-date raster differencing; NDVI/NBR change; threshold classification of change magnitude |
| `mod_rs_classify.R` | `rsclassify` | Leaflet map | Draw training polygons → RF classify raster stack; k-means unsupervised; accuracy/confusion matrix; export |
| `mod_xgboost.R` | `xgboost` | Plot canvas | XGBoost on tabular data; hyperparameter grid (eta/depth/rounds); feature importance; early stopping |

### ML improvements (in-place, not new modules)
- `mod_rf.R`: add mtry/ntree grid search, k-fold CV, confusion matrix download button.
- `mod_classification.R`: add precision-recall curve plot, download predictions.

### Map-centric module pattern (for raster/vector/sentinel/gedi/rsclassify)
Canvas = `leafletOutput` filling the center; tools panel = accordion with controls.
```r
# Canvas UI
<name>CanvasUI <- function(id) {
  ns <- NS(id)
  leafletOutput(ns("map"), width = "100%", height = "100%")
}
# Tools UI
<name>ToolsUI <- function(id) {
  ns <- NS(id)
  accordion(
    accordion_panel("Data", ...),
    accordion_panel("Operations", ...),
    accordion_panel("Export", downloadButton(ns("dl"), "Download"))
  )
}
```
Leaflet map initialised with provider tiles (OSM default; ESRI Satellite / CartoDB toggles).
AOI drawing: `leaflet.extras::addDrawToolbar()` → capture drawn shapes as `sf` polygon.

### New packages required
Add to `global.R` (with `requireNamespace()` guards for optional ones):

| Package | Use | Required? |
|---------|-----|-----------|
| `leaflet` | All map-centric canvases | Hard |
| `leaflet.extras` | AOI drawing toolbar | Hard |
| `leafem` | Display terra rasters in leaflet | Hard |
| `rstac` | Sentinel-2 STAC query | Hard |
| `exactextractr` | Fast zonal statistics | Hard |
| `xgboost` | XGBoost ML | Hard |
| `caret` | CV + model tuning helpers | Hard |
| `rgdal` / `gdal` | Raster format support via terra | Via terra |

### Dev sequence (one module at a time, verify after each)
1. **`mod_raster.R`** — foundation; establishes leaflet map pattern all others follow.
2. **`mod_vector.R`** — complements raster; same map pattern.
3. **`mod_sentinel.R`** — data acquisition (depends on raster display pattern).
4. **`mod_change.R`** — analysis (depends on raster upload/display).
5. **`mod_rs_classify.R`** — analysis (depends on raster + drawing toolbar).
6. **`mod_xgboost.R`** — standalone ML, independent of spatial stack.
7. RF/classification in-place improvements.

### Constraints specific to new modules
- **Raster display in leaflet:** project to WGS84 first (`terra::project(r[[band]], "EPSG:4326")`), then use `leafem::addGeoRaster()`. Large rasters must be downsampled before sending to browser.
- **STAC queries (Sentinel-2):** `rstac` returns item collections; download actual COG tiles with `rstac::assets_download()`. Clip before download where possible to limit size.
- **File uploads (raster/vector):** shapefiles are multi-file (.shp + .shx + .dbf etc). Use `multiple=TRUE` in `fileInput`; write all to a temp dir then read with `sf::st_read()`. Single-file formats (.gpkg, .geojson) use the datapath directly.
- **Leaflet draw shapes:** `input$<mapId>_draw_new_feature` fires on each drawn shape. Shiny auto-parses the GeoJSON into a named R list — parse directly: coords = `feat$geometry$coordinates[[1]]`, each element is `[lon, lat]`. No extra packages needed beyond sf.
- **Drawn shape CRS:** leaflet always draws in WGS84 (EPSG:4326). Transform to raster/vector CRS before spatial ops: `sf::st_transform(drawn_sf, terra::crs(raster))`.
- **`%||%`:** defined in `helpers.R` as `function(a, b) if (!is.null(a) && length(a) > 0) a else b`. Available to all modules via `global.R`.
- **XGBoost:** requires the response variable as numeric (0/1 for binary; integers for multiclass). Must call `xgb.DMatrix` not pass raw data frames.

---

## Phase 4 — Completed Changes (all verified with build check)

### 1. Rename: SimpleAnalysis → SimpleAnalysis (`ui.R`)
- Top-bar brand text: `"SimpleAnalysis"` → `"SimpleAnalysis"`.
- About panel name: same.
- About panel monogram: `"TT"` → `"SA"`.
- Documentation files (CLAUDE.md, README.md, spatial_design_reference.md) still say SimpleAnalysis — update separately if needed.

### 2. DA module — three decision boundary plots (`mod_da.R`)
Three independent `renderPlot` outputs (not patchwork/facets) for the 1-predictor case:
- **Decision Regions** (`output$lda_plot_regions`): `geom_tile(height=Inf)` background + `geom_rug` + `geom_vline` at class boundaries.
- **Class Lanes** (`output$lda_plot_lanes`): tile background + `geom_point` with each actual class in its own horizontal lane.
- **Class Density** (`output$lda_plot_density`): tile background + `geom_density` overlay.
All three share a unified `class_colors` named vector (`viridisLite::viridis`) so `scale_fill_manual` and `scale_color_manual` cover both `Predicted` and `Actual` levels.
Added to `lda_selected_plots` choices; grid UI wired with `output$lda_plot_regions/lanes/density`.
If > 1 numeric predictor, all three show a placeholder directing user to "LD Scatter/Density".

### 3. DA module — LLDA CV fix (`mod_da.R`)
`da_cv_result_r` LLDA branch: added jitter loop over numeric predictors in training fold (`tr_j`) identical to the fit-time jitter, preventing `loclda()` tie errors in CV.

### 4. Accuracy labels + validation accuracy under CV CMs (multiple modules)
- All training accuracy labels changed from method-specific strings (e.g., "Locally Linear DA Accuracy") to `"Training Accuracy: XX%"`.
- `textOutput(ns("val_acc_da"))` / `textOutput(ns("val_acc"))` added below every validation confusion matrix in: `mod_da.R`, `mod_logistic.R`, `mod_nnet_ml.R`, `mod_dtree.R`, `mod_svm.R`.
- `mod_rf.R`: `output$oob_val_acc` shows "OOB Accuracy: XX%" below the OOB CM.

### 5. DA class-level accuracy breakdown (`mod_da.R`)
`output$lda_accuracy` and `output$val_acc_da` changed from `renderText` → `renderPrint`, now showing:
```
Training Accuracy: 59.90%

Class breakdown:
  Moraine / Till             n=3444  correct=3365  (98%)
  Organic soil (>30cm peat)  n=1787  correct=422   (24%)
  Sorted mineral soil        n=1146  correct=33     (3%)
```
Canvas uses `verbatimTextOutput`; CM plot heights reduced 270px → 220px to accommodate.

### 6. Co-Pilot button moved to top bar (`ui.R`, `mod_chat.R`)
- FAB hidden via `.copilot-fab { display: none !important; }` in `mod_chat.R`.
- Button added to `.topbar-right` in `ui.R` using `.topbar-action-btn` class.
- Panel `bottom` adjusted from 110px → 56px to sit above the status bar.

### 7. DA method cross-validation (analysis, no code changes)
Compared all DA methods in `mod_da.R` against `simple.R` reference script. All implementations match exactly (WLDA inverse weights, RLDA gamma/lambda grids, KDA sigma=0.01/C=0.1/prob.model=TRUE, LLDA k=5 with jitter, MMC vanilladot/C=1). The previously reported singular-matrix errors were caused by users selecting only 1 predictor (e.g., `ih5_dm` only) instead of the full formula (`ih5_dm + Nutrient_class + Nutrient_add`). No code fixes were needed. The hidden rare-class guard (`min_n` block) was identified as undesirable hidden preprocessing — should be removed in a future cleanup so users manage class filtering themselves in the Data module.

### 8. DA sandbox (`sandbox.R`)
Standalone Shiny app (`shiny::runApp("sandbox.R")`) that mirrors `simple.R` DA code exactly — upload a cleaned CSV, pick target + predictors, run any DA method, see confusion matrix + class-level accuracy breakdown + raw R errors. No hidden preprocessing. Used to confirm app and simple.R produce identical results given the same formula.
