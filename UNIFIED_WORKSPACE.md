# UNIFIED_WORKSPACE.md — the one-workspace rebuild (build spec)

**Status: approved direction, not yet built.** Concept artifact (the pinned target):
https://claude.ai/code/artifact/1f075e27-12e1-4454-a38a-80f5bc8c90bf

## Goal
Collapse the ~35 fragmented analysis screens into **ONE workspace**. A "screen" stops being a
place you navigate to and becomes a **tool you open as a panel**. Modelled on **GeoLibre**
(github.com/opengeos/GeoLibre): one persistent canvas, tools as panels, a Layers panel as the
spine. **Local-first server build only** — the browser/wasm build is deprecated (see
[local-first](CLAUDE.md), MEMORY.md §2).

## KEY DECISION — two views: MAP VIEW and DATA VIEW (2026-07-26)
The workspace has **two top-level views** (toggle in the menubar). **Both use the SAME
GeoLibre-style frame** — left spine (layers/data) + centre canvas + right tool panel + docking.
Only the canvas and the tool set differ:

- **MAP VIEW** — *purely GeoLibre-inspired.* Layers spine + **map canvas** (spatial layers with
  per-layer legend/style) + **attribute-table dock** (bottom) + spatial tools (clip, extract, terrain,
  hydrology, RS, LiDAR). Predictions map back here.
- **DATA VIEW** — the **same structural type** as the map view, but for data/modelling (for users who
  *only model and don't want a map*). Canvas = the active table + a **chart / plot builder**. Tools
  (stats/ML) are picked from a **dropdown / search**, and each opened operation **docks open** (its
  settings panel; results dock as **resizable pop-out mini-screens**). Same paradigm, data canvas.

**Why two views, not one auto-switching canvas:** a pure modeller wants no map frame; a GIS user wants
the map front-and-centre. Two views let each audience live in their preferred mode while sharing
**one project, one data list, one tool set, one results dock**. Bridge between them: *Extract values*
(Map view) → a table (Data view); *predictions* (Data view) → a layer (Map view).

**View arrangement (refinement, 2026-07-26): not only switchable tabs — a resizable SPLIT.** Each view
is a **pane** with three states — *full · split · minimized/closed*:
1. **Switched** — a tab click makes one view fill the canvas.
2. **Side by side** — both panes shown with a **draggable slider** between them to set the ratio
   (e.g. map 60% / data 40%), so you can watch the map while a model runs on the data.
3. **Minimized / closed** — collapse a pane to a thin bar (restore later) or close it.
Mirrors the results mini-screens (same full/split/minimized idea). Build note: a splitter — a draggable
divider on the canvas (or `shinyjqui` / custom JS) with min/max widths and a per-pane collapse toggle.
The Step-1 scaffold ships plain tabs; the split is the next iteration on the same frame.

## Shared components (both tabs)
- **Layers panel (left) = the spine.** Every dataset/layer in one list: visibility eye, colour swatch,
  name (click = make active), type tag; expandable → **per-layer legend + style** (ramp for raster,
  symbol for vector, rows×cols for a table). This folds in the GeoPackage-symbology gap.
- **Tool panel (right) = the active tool's settings.** Search (already built) or menu → pick a tool →
  its `*ToolsUI` loads here → **Run**. This *is* the old per-screen tools panel, now opened on demand.
  Default = a tool launcher / "no tool open" state.
- **Tool search** in the menubar → sets the active tool (reuse the existing `#tool_search`).
- **Results dock (far-right vertical rail).** Model results park as chips → click to pop out a
  **resizable, draggable** mini-screen (compare side by side). Three states of one object:
  *in the result area → expanded mini-screen → minimized chip.*
- **Status bar**: active layer · active tool · results count · memory meter · saved location.

## Canvas per view
- **Map-view canvas** = leaflet map (reuse `mod_raster.R`'s map pattern), layers rendered with
  styling/legend; **attribute-table dock** at the bottom (active layer's features, or raster band
  stats) — resizable + collapsible; feature ⇄ row selection sync.
- **Data-view canvas** = a **chart / plot builder** (esquisse-style: geom · x · y · colour → plot)
  over the active table, with the **data table docked** below. Model-result plots render here or pop
  out. This chart builder also delivers the long-requested flexible plot builder (tester gap) inside
  the workspace — no separate EDA screen.

## Interaction / sync
- Map ⇄ table linked: select a feature ↔ highlight its row (and back).
- **Spatial op result → a new layer** (Map). **Model result → a result panel** (Modeling / pop-out).
  **Predictions → a layer** mapped back to the Map tab.
- **Extract values** (at points / zonal) = the bridge raster → modellable table.

## Tool-as-panel contract (the refactor)
Today each module is `<name>CanvasUI(id)` + `<name>ToolsUI(id)` +
`<name>Server(id, dataset_pool, active_dataset, …)`, wired into two `navset_hidden`s (ui.R
`canvas_view` + `tools_view`), one pane per screen, swapped by `input$current_view`.

Target:
- `*ToolsUI` → the **right tool panel**, rendered when that tool is active (driven by a new
  `current_tool` reactive set by search/menu). Reuse the existing ToolsUI mostly as-is.
- `*CanvasUI`/`renderPlot` output → **routed to the active tab** (Map: becomes a layer; Modeling: a
  result plot / pop-out) instead of a dedicated pane. Reuse existing plot engines (`helpers.R`) and
  `uef_evaluation()`.
- Replace the 35-pane navsets with: **Map tab + Modeling tab**; the right panel swaps `*ToolsUI` by
  active tool. Module servers stay **bound once** (as now); they read `active_dataset()` and write
  results into a shared results store.

## Staged build plan (do NOT break the working app)
1. **Two-tab shell** — add Map tab + Modeling tab as the frame; keep current views reachable during
   transition (feature-flag / parallel) so nothing breaks mid-migration.
2. **Layers panel** — extend the left `datasets_list` to all 4 pools with visibility + type + per-layer
   legend/style (a `layers` reactive over dataset/raster/las/vector pools).
3. **Tool-panel host** — a right panel that renders the active tool's `*ToolsUI` from `current_tool`
   (search/menu sets it). Start with 3–4 tools: `lm`, `rf`, `clip`, `extract`.
4. **Results store + dock** — a `reactiveValues` `results`; each model run appends
   `{id, title, plot_fn, metrics}`; render the dock + resizable/draggable pop-out panels
   (evaluate `shinyjqui` for drag/resize, or the artifact's CSS-`resize` + JS-drag).
5. **Modeling-tab chart builder** — evaluate `esquisse`; the active-table plot builder = the Modeling
   canvas.
6. **Attribute-table dock** (Map tab) — `DT` of the active layer; resizable/collapsible; select ⇄
   highlight sync with the map.
7. **Migrate modules one at a time** (screen → tool): verify each (build check + `testServer` +
   user confirm), then retire the old pane. Priority order: Data/EDA → lm/rf/anova/tests →
   clip/extract/raster → the rest.

## Constraints / carry-overs (must hold)
- Local-first **server build only**; do not touch `webapp/` (deprecated).
- **No emojis**; brand mono font (`--mono`); **glassy popups** (translucent + blur, centered);
  dark forest theme from `theme.R`.
- Canvas-follows-data; **no per-module dataset picker** (use `active_dataset()`).
- Reuse existing plot engines, `uef_evaluation`, and module `*ToolsUI`.
- Pop-out mini-screens need a drag/resize mechanism (shinyjqui or custom JS).
- Run models on an explicit **Run button** (DESIGN rule #8), never reactively.

## THE UI SPEC — GeoLibre's real menubar (2026-07-27, SUPERSEDES the artifacts)
The concept artifacts are **old**. The source of truth is **GeoLibre's actual UI** (screenshots
supplied by the user). Build the workspace chrome to match this.

### Top bar = icon + label menus, each a dropdown
```
Project | Edit | View | Add Data | Processing | Controls | Plugins | Settings | Help
```
Flat, single row, every item a dropdown. Nothing else lives up there (no analysis lists, no
per-screen menus). This replaces our current `Projects | Workspace` bar.

### `Project` dropdown (what you get once a project is OPEN)
Header "Project", then:
```
New…
Open From        ▸   (submenu)
Open Recent      ▸   (submenu; greyed out when empty)
──
Save
Save As…
Share…
Export as HTML…
Collaborate…
──
Print Layout…
Offline Basemap…
──
Story Map…
```
Grouped by separators; each item has a small leading icon; submenus show a `▸` chevron;
unavailable items render **disabled/greyed** (e.g. Open Recent with no history), not hidden.

### `Processing` dropdown = where OUR TOOLS live
Header "Processing", then GeoLibre's shape (mapped onto our modules):
```
AI Assistant                 -> our Co-Analyst (already merged with Recommend)
Whitebox
Conversion       ▸
Hydrology        ▸           -> mod_hydro.R
LiDAR            ▸           -> pointcloud / chm_itd / metrics
Network          ▸
Projection       ▸
Raster           ▸           -> mod_raster.R, surface, terrain
Remote Sensing   ▸           -> rs_search, ntl, climate_trend
Terrain          ▸           -> mod_terrain.R
Vector           ▸
GeoLibre         ▸
──
SQL Workspace
Python Console
Jupyter Notebook
Dashboard
History
Planetary Computer
Earth Engine
```
**Our adaptation:** keep this shape, but the submenus list *our* tools — the `MODUI` registry in
`mod_workspace.R`, grouped Data / Statistics / Machine Learning / Spatial & LiDAR, plus
**R Console** (below). A tool still opens in the right-hand tool panel; only the *launcher* moves
from the current dropdown into this menubar.

### R Console = a BOTTOM dock
Clicking R Console **slides a console up from the bottom** of the workspace (a bottom drawer,
resizable/collapsible like the attribute dock) — not a screen, not a pop-out.

### Keep the view toggle
The **Map view / Data view / Split** toggle stays as built (draggable split + per-pane collapse).

### Basemaps (Map view)
The map ships a **basemap switcher** (in `View`): Dark (CartoDB.DarkMatter, default), Light
(CartoDB.Positron), OpenStreetMap, Satellite (Esri.WorldImagery), Topographic (Esri.WorldTopoMap),
Terrain (OpenTopoMap), and None. Switching swaps the tile layer via `leafletProxy` without touching
the data layers (they live in the `ws_layers` group).

### DEV PLAN (staged; each stage build-checked AND browser-verified)
| # | Stage | What lands | Status |
|---|-------|-----------|--------|
| M1 | **Menubar shell** | The 9 dropdowns (`Project…Help`) rendered server-side from a menu spec; click-to-open, click-outside-to-close, keyboard-dismissable; separators, leading icons, `▸` submenus, greyed-disabled items | DONE |
| M2 | **Project menu wired** | New… / Open From / Open Recent (greyed when empty) / Save / Save As… (.eap download) / Import / Close project → real project actions | DONE |
| M3 | **Processing menu = our tools** | Built from the `MODUI` registry, grouped Data / Statistics / ML / Spatial & LiDAR (+ AI Assistant → Co-Analyst, R Console); picking one opens it in the right tool panel | DONE |
| M4 | **View menu + basemaps** | Basemap switcher (7 options) + panel toggles (layers rail, tool panel, attribute dock) | DONE |
| M5 | **Add Data menu** | Add data… (browser picker), Create dataset, sample data | DONE |
| M6 | **R Console bottom dock** | Slides up from the bottom, resizable + collapsible; hosts `rconsole` | TODO |
| M7 | **Retire the old tool dropdown** | Once Processing covers everything, remove the `tool_pick` select from the view bar | TODO |
| M8 | **Controls / Plugins / Settings / Help** | Settings → existing drawer; Help → docs/about/tour; Controls → map controls; Plugins → placeholder | PARTIAL |

Keep: the **Map view / Data view / Split** toggle, the layers spine, the right tool panel, the
results dock and pop-outs.

## Current build state (2026-07-26) — how to run & test locally

**Shipped so far (all in `mod_workspace.R`, wired via ui.R + server.R; the old app is untouched —
the workspace is a PARALLEL screen reached from the `Workspace` menu item):**
- **Step 1** two-view frame (Map view / Data view tabs) + layers/data spine + tool-panel host.
- **Step 2** Layers panel: per-layer visibility (eye), active selection, expandable legend/style.
- **Step 3** tool-panel host: a tool dropdown → per-tool settings from the active data.
- **Step 4** results store + dock: model runs REALLY fit (lm/rf) with `uef_evaluation` metrics +
  observed-vs-predicted plot, shown as **draggable, resizable pop-out mini-screens** (dock chips, min/close).
- **Step 5** Data-view **chart builder** (geom · X · Y over the active table) + docked data table.
- **Step 6** Map-view **leaflet basemap** + collapsible/resizable **attribute-table dock** for the active layer.
- **Step 7 (started)** the REAL `lm` module is migrated in (`lmServer("ws_lm",…)` + a `MODUI` entry) —
  picking "Linear regression" shows its live ToolsUI + CanvasUI.

**Not yet done:** migrate the other ~34 modules (same recipe), spatial ops → real map layers + select↔row
sync, retire old panes, and the resizable Map/Data split. Troubleshooting deferred by the user until the
whole thing is built.

### Run it
```
& "C:\Program Files\R\R-4.5.3\bin\Rscript.exe" "<app>\launcher\run.R" "<app>"
```
(stop any running instance first so port 7788 is free; opens at http://127.0.0.1:7788; first boot ~30–60 s).
Build-check without launching: the one-liner in [CLAUDE.md](CLAUDE.md).

### Test walkthrough
1. Menu → **Workspace**. Open a project that has a table (or add a CSV) so there's data.
2. **Layers panel** (left): click a layer name (active highlight); toggle its **eye**; click **▶** to open its legend/style.
3. **Data view** tab: use the **chart builder** (geom / X / Y) — the plot redraws; the table is docked below.
4. **Tool** panel (right): pick **Random Forest** → set Response + Predictors → **Run** → a result **pops out**;
   drag its header, drag the corner to resize, run another and set them side by side; use the dock chips + –/×.
5. Pick **Linear regression** → you get the **real lm module** (its settings + canvas) inside the workspace.
6. **Map view** tab: a dark **basemap** + the **attribute table** dock (drag its header to resize, ▾ to collapse).
7. Confirm the **old app is unchanged**: the other menu items (Data, Statistics, Spatial…) still work as before.

## References
- Concept artifact: https://claude.ai/code/artifact/1f075e27-12e1-4454-a38a-80f5bc8c90bf
- [DESIGN.md](DESIGN.md) (GeoLibre north star, UX rules), [ARCHITECTURE.md](ARCHITECTURE.md)
  (shell, pools, module contract, memory mgmt), [MEMORY.md](MEMORY.md) (gotchas).
- Claude private memories: `unified-workspace-direction`, `workspace-canvas-rule`,
  `product-thesis-one-place`, `local-first-direction`.

### Project file cleanup (fixed 2026-07-28)
Removing a spatial layer used to leave the copy the project had made of it in
`<project>/files`, so orphans accumulated. Two functions in `project_store.R`
fix it:

- `ea_project_remove_file(id, path)` — deletes the copy when a layer is removed,
  and takes a shapefile's sidecars with it.
- `ea_project_prune_files(id, keep)` — run on project open, clears orphans left
  by earlier versions.

**Safety:** both refuse to touch anything outside `ea_project_files_dir(id)`, so a
layer that points at the user's own file is never deleted. Verified with a test
covering: copied raster removed, shapefile sidecars removed, a path outside the
project refused, and orphan pruning that keeps referenced files.

### Colour sets: bslib bakes the DEFAULT palette in (fixed 2026-07-28)

`ea_theme()` compiles Bootstrap ONCE from `ea_palette` (the dark forest set), so
Bootstrap's own variables (`--bs-body-bg`, `--bs-table-bg`, `--bs-accordion-bg`,
`--bs-card-bg`, ...) hold dark hex values that `html[data-ea-theme]` never touches.
Switching to a light set re-skinned only the hand-written `.ea-*` chrome; anything
Bootstrap rendered stayed near-black — DT tables and the Co-Analyst accordions were
the visible cases (`#0F1310` cells on a `#F7F8F4` page).

The earlier legibility block fixed **text colour** only. `ui.R` now also carries a
**surfaces** block that restates those variables from the tokens. Two rules:

- Bootstrap declares component vars **on the component class**, not on `:root`, so a
  `:root` override never reaches them — restate per component (`.table`, `.accordion`,
  `.card`, `.modal`, `.dropdown-menu`, `.nav-tabs`).
- Inputs (`.form-control`, `.form-select`, `.selectize-input`) compile to literal hex
  with no variable at all — set those properties outright.

Verified: 0 mismatched surfaces across all six sets (dark surface on a light page or
vice versa). **When measuring after `eaSetTheme()`, force a reflow first** — otherwise
`getComputedStyle` returns the previous set's values.

### renderUI panels must carry the user's selections (fixed 2026-07-28)

Workspace panels are `renderUI`-built, so any dependency change rebuilds them and every
`selectInput` reverts to its default. Flipping the chart's Static/Interactive toggle
rebuilt the whole chart bar and silently reset X and Y; adding a layer wiped the model
tool's Response/Predictors the same way.

`.keep_sel(id, choices, default, multi = FALSE)` in `mod_workspace.R` returns the
current value when it still exists among the new choices, and the default only when it
genuinely went away. Used by `cgeom`/`cx`/`cy`, `resp`/`preds`, `in_layer`/`clip_to`.
**Any new selector inside a renderUI panel should use it.**

### The guided tour lives in the workspace (moved 2026-07-28)

It used to run on the welcome/project screens — pointing at the one place that already
explains itself. The six steps now target the workspace: Layers panel, the menus, the
view tabs, the tool panel, the results dock, the Co-Analyst. `start()` switches to the
workspace and polls for `.ea-wsx-grid` before rendering (view panes are hidden and their
outputs suspended until Shiny switches them); a step whose anchor is missing is skipped.
Single entry point: **Help > Take the tour** in the workspace menubar.

### Map layers: build them WITH the map, never through a proxy (fixed 2026-07-29)

**Symptom:** the map zoomed to the raster but drew nothing.

The zoom already ran at map-build time (that was the earlier fix); the layers were
still added afterwards through `leafletProxy`. The map element is re-created whenever
the canvas re-renders or the basemap changes, and a proxy message arriving around that
moment is dropped — so the fit survived and the data did not. Tiles, view and layers
are now built in ONE pass inside `renderLeaflet` via `.draw_layers(m)`; there is no
proxy left in the workspace map.

Three further defects found while verifying, each independently able to hide a raster:

- **Full-res reprojection failed.** `.to_wgs84(r[[1]])` was called on the ORIGINAL
  raster and downsampled only afterwards, so a 33 M-cell orthomosaic was warped at full
  resolution — 18.1 s, and under memory pressure it died outright with
  `[project] warp failure`, which `tryCatch` swallowed into an empty map. Downsampling
  first (cheap, in the native CRS) takes **6.4 s**, keeps the same 56.9 % valid cells,
  and moves the extent by ~0.7 m. `.disp_raster()` also **memoises** the result, because
  the bounds and the image each used to build their own copy — the cost was paid twice
  per map build. The cache is bounded (6 entries) like the results store.
- **`return()` inside `.layer_bounds()`'s loop.** It returns from the whole function,
  so one empty pool entry discarded the bounds of every other layer. Yield `NULL`.
- **Point clouds were never drawn** — `lidar` was missing from the layer filter, so a
  LAZ-only project opened on a blank world map with nothing to zoom to. LAS/LAZ now
  contributes its footprint (`.las_bbox()`, which reads a `LASheader` or a full `LAS`)
  and draws as a rectangle. Points themselves stay in the LiDAR screen.

**Stacking:** `addRasterImage` builds a *canvas tile layer* that lives in the **tilePane**
— the same pane as the basemap — so at equal z-index only DOM order separated them. The
basemap is now pinned with `providerTileOptions(zIndex = 0)`; verified in the browser as
basemap z-index 0 / data z-index 1.

**Measuring leaflet in a non-compositing browser pane:** every tile reads
`opacity: 0`, basemap included, because Leaflet's fade-in runs on `requestAnimationFrame`.
Do not read that as a broken layer — check `_tiles` and the canvas pixel data instead.

### Multi-band rasters: true-colour composites (added 2026-07-29)

Rasters used to be drawn as **band 1 through a viridis ramp**, so a drone orthomosaic
showed up as a purple-green heatmap instead of a photograph.

`leaflet::addRasterImage` *can* composite, but only down one specific path:

```r
if (terra::has.RGB(x))      x <- terra::colorize(x, "col")
else if (terra::nlyr(x) > 1) x <- x[[1]]   # warns "using the first layer in 'x'"
```

So the channels must be declared with `terra::RGB(x) <- 1:3`, and the values must be
**bytes** — an orthomosaic carries float reflectance (this one 0.0004-0.63), which
`colorize` renders near-black. `.stretch_byte()` therefore applies the standard
remote-sensing 2-98% per-band percentile stretch to 0-255 first.

**Band order is NOT assumable.** A 3/4-band ortho is normally stored R,G,B, but a 5-band
multispectral cube is typically B,G,R,(RedEdge,NIR) — so bands 1,2,3 give a cyan
false-colour image and the true-colour composite is **3,2,1**. The default is a
documented heuristic (`>= 5 bands -> 3,2,1`, else `1,2,3`) and the layers panel exposes
a per-layer R/G/B mapping plus a True-colour / Single-band toggle. Picking NIR for the
red channel gives the usual false-colour infrared composite.

The band pickers are plain `<select>` elements firing one `{nm, ch, b}` event, not
`selectInput`s: the panel is rebuilt for every layer on every render, so per-layer Shiny
inputs would mean N observers all fighting that rebuild.

Verified in the browser by sampling canvas pixels: true colour is green-dominant
(102 G vs 4 B) with natural greens and browns; NIR-in-red flips it to red-dominant
(126 R vs 29 G); single band returns the viridis purple (165 B).

### R Console: themed, side-by-side, and dockable (2026-07-29)

- **Theme.** The console hardcoded a near-black (`#0f1a12`) plus fixed greens and greys,
  so it stayed dark on every light colour set. All of it now comes from tokens
  (`--sunk`, `--ink`, `--canopy`, `--danger`, `--bark`), including the log text, the
  error colour and the editor.
- **Layout.** Editor and results were stacked, with a `46vh` log and a permanently
  reserved plot card. They are now a two-column grid — editor left, results right — each
  column a flex chain with `min-height: 0` so it fills the dock instead of overflowing.
  The plot slot only exists once something has actually been plotted.
- **Modes.** Like the tool panels, the console can **dock / float / minimize**. Floating
  uses `position: fixed`, which takes it out of the flex column so the workspace above
  reclaims the space rather than leaving a gap. Minimized keeps the header bar only.
  **Docking always returns it to the bottom**, clearing any inline geometry left by
  dragging. Mode changes are class swaps (`window.eaConsole`), so the editor contents and
  scroll position survive. Header drag resizes when docked and moves when floating.

### Zoom to layer (fixed 2026-07-29)

Three separate defects:

- **"Zoom to active layer" was wired to the same input as "Zoom to layers"**, so it always
  framed everything. It now has its own input and `.layer_bounds(only = )` targets one
  layer — ignoring that layer's visibility, since naming a layer is an explicit request.
- **No explicit-fit path.** Both commands nudged the same `fit_sig`/auto-fit machinery
  that also decides the *automatic* first fit, so a zoom could be skipped whenever the
  layer signature already matched. There is now a `fit_req` reactiveVal holding bounds to
  apply on the next build, and it outranks both the auto-fit and the preserved view.
- **lidar was missing from the fit signature**, so a LAZ-only project never got its
  first automatic fit.

Failure is now reported: zooming to a layer with no location shows a notification naming
the layer instead of doing nothing.

**Zooming must not recompute pixels.** A fit requires a full map rebuild (there is no
proxy), which re-ran `.stretch_byte` and rebuilt the composite every time — on a 33 M-cell
orthomosaic that walked the session into `cannot allocate vector` and GDAL block-cache
failures after a handful of zooms. `.rgb_raster()` caches the finished composite, keyed by
layer and band mapping. Verified: five pan-away/zoom-to-layers cycles produce **2**
reprojections total and zero allocation errors.
