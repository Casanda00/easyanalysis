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

### Console: the script survives Run; plots open in a window (2026-07-29)

`run_code()` ended with `updateTextAreaInput(session, "code", value = "")` — every Run
threw away what the user had just written. The console is something you iterate in, so
the editor now keeps its contents; only "Clear" empties the log, and nothing empties the
editor but the user.

Plots no longer take space in the results column. They open in a floating window that is
**resizable** (the browser's own `resize: both` grip) and **maximizable** (a class that
sets `left/top/right/bottom`), draggable by its header, and deliberately **not dockable** —
a plot is something you look at beside your code, not a permanent region competing with
the editor for the dock's height. Maximizing stashes and clears inline geometry first,
because styles left by dragging would otherwise out-specify the `.max` rules. A
`ResizeObserver` dispatches a window `resize` so the plot re-renders at the new size —
the CSS grip fires no event of its own, and Shiny only listens for window resize.

### One map, everything overlays (fixed 2026-07-29)

The automatic fit re-ran whenever the layer signature changed, so **adding a file yanked
the view away** from whatever the user was looking at. It now fires only for the FIRST
spatial layer — enough to get off the default world view — and re-framing afterwards is
on request via Zoom to layers. `fit_sig` is re-armed when the spatial pools empty, so a
newly opened project still frames itself. Verified: panned to Helsinki, changed the layer
set, view held at 60.1699 / zoom 11.

### Point clouds are drawn, not just outlined (2026-07-29)

A LAZ layer showed only its footprint. It now draws the cloud itself, height-shaded
(viridis over Z), as a decimated sample — leaflet creates one DOM element per marker and
the pool holds up to 500k points, so the full cloud would lock the browser. The footprint
stays as an outline around it.

Density is user-controlled: a small slider floats over the map, visible **only while a
point cloud is the selected layer**, from 500 up to `min(50k, points loaded)`. It is its
own `uiOutput` inside the map container rather than part of `.map_ui()`, so selecting a
layer does not re-create the leaflet element and rebuild the map. The sample is cached per
(layer, budget), and the legend states the decimation outright: "showing 4,000 of 500,802
points". Verified: 4,000 -> 12,000 markers with the view preserved.

### LAZ: sampled on load, full cloud reachable from the slider (2026-07-29)

Loading is capped for RAM, so the pool holds a SAMPLE (500,802 of this file's
18,685,539 points). The slider is therefore bounded by the **file's** count, not the
sample's, and the extra points are read from disk only when the slider asks for them
(`.las_at()`, a `-keep_random_fraction` read proportional to the request, cached one
cloud deep). Nothing extra is read at load time.

Points are **never rasterized** — a LAZ layer is a point cloud, not a surface. The map is
built with `preferCanvas`, so markers are painted onto a canvas instead of becoming one
DOM node each; that is what keeps large clouds drawable.

The **3D view** is a small button at the right-hand end of the map header strip (not a
tab), visible only while a point cloud is the selected layer, toggling into the existing
`lidarPointcloudCanvasUI` viewer and back. Selecting a non-cloud layer while in 3D
returns to the map rather than stranding the user on a view with no way back.

### Settings and About point at their own sections (2026-07-29)

`Preferences…`, `Keyboard shortcuts` and `About EasyAnalysis` all called a bare
`openSettings()`, which dumped the reader at the top of the panel — About in particular
looked like it "opened the settings". `openSettings(section)` now scrolls to the named
section (`set-display`, `set-keys`, `set-about`) and flashes it briefly.

Bootstrap's button variables were added to the surfaces block: like the tables and
accordions, `--bs-btn-bg` and friends are declared ON `.btn`, so the `:root` remap never
reached them.

### Plot titles, axis labels and colour (2026-07-29)

The chart builder takes a title, X and Y labels, and a colour. Blank means "use the
default" — clearing a label restores the column name rather than blanking the axis.
Verified at the ggplot level: defaults give `x: dbh / y: height / no title / #2E7D32`;
customised gives the supplied title, both labels and `#B4531F`.

**Scope note:** this currently covers the workspace chart builder only. Applying it to
every analysis and model screen needs a shared mechanism rather than 35 copies — see the
open item in the response accompanying this change.

### Plot appearance, app-wide (2026-07-29)

Users can set a plot's **title, X label, Y label and colour**, and it had to work on
every analysis and model screen rather than be re-implemented ~35 times.

**The seam is `print.ggplot`.** Shiny's `renderPlot` prints the ggplot object, and S3
dispatch finds the `print.ggplot` defined in `helpers.R` (global env) before ggplot2's —
so every ggplot in the app passes through `ea_style_gg()` with no module changes at all.
The read happens inside `renderPlot`'s reactive context, so changing an option
re-renders the affected plot on its own. It must call
`getFromNamespace("print.ggplot", "ggplot2")` explicitly or it recurses.

Settings are stored **per screen** (`plot_opts` in server.R, keyed by the workspace's
current tool), so configuring the LM screen does not restyle Random Forest. Only what
the user actually set is overridden; an untouched plot keeps exactly the labels its
module chose. Colour is applied only to layers carrying a FIXED colour/fill — layers
mapped to a variable are left alone, because overriding those would destroy the encoding.

The controls are one block (`.plot_opts_ui()`) used twice: inline in the Data view's
chart bar, and stacked in the tool panel for every non-map tool.

Verified: nothing set -> module's own labels and colour survive; set on screen `lm` ->
title/x/y/colour all applied; screen `rf` unaffected; `print.ggplot` resolves to
`R_GlobalEnv`; and with no store installed at all, ggplot and base plots both render
normally and `ea_opt()` returns its default.

**Base-R plots are NOT covered by the seam** — they bake `main`/`xlab`/`ylab` in at draw
time. `ea_opt("title", default)` exists for those modules to call when building their
arguments. Deliberately not applied wholesale: most base plots here are **multi-panel
diagnostic grids** (`plot_lm_diagnostics` and friends), where one shared title and axis
pair across every panel would be actively wrong — each panel means something different.
Single-panel base plots are the sensible candidates; that pass is still open.

### Base-R plots: the per-call-site pass (2026-07-29)

The `print.ggplot` seam cannot reach base graphics — `main`/`xlab`/`ylab` are baked in at
draw time — so the 43 base call sites were done by hand. They split two ways, and the
split is the whole point:

**Single-panel (22 sites)** take the options directly:
`hist(x, main = ea_main("Distribution of x"), xlab = ea_xlab("x"), col = ea_col("#4caf50"))`.
`ea_main()/ea_xlab()/ea_ylab()/ea_col()` return the module's own default whenever the
user has set nothing, so an untouched plot is byte-identical to before.

**Multi-panel (21 sites)** deliberately do NOT take per-panel labels. A diagnostic grid
is Residuals, Residuals-vs-Fitted and a Q-Q side by side; stamping one title and one axis
pair across all three would be wrong for every panel. They get an **overall figure title**
instead: `ea_multi_par()` reserves an outer margin *only when a title is set* (`oma`
0,0,2.2,0 vs 0,0,0,0 untouched), and the title is drawn inside the existing
`on.exit({ ea_fig_title(); par(old_par) })` — before the reset, while the margin still
exists. Verified visually: panels keep "Residuals" / "Residuals vs Fitted" / "Normal Q-Q"
with the overall title above them, and the untitled version wastes no space.

One site was reverted: `mod_rconsole.R`'s example chip is sample code shown to the user,
not a plot call.

Files touched: helpers.R (shared engines, so this covers several screens at once),
clustering, da, data, descriptive, hydro, land_classify, raster, suitability, svm,
terrain, timeseries, workspace, lidar, lme, ntl, linear_regression.

### Wiring the plot options end-to-end (2026-07-29)

Three real bugs, none of which the R-level tests could have caught — they only showed up
driving the actual UI with a project that has a table:

1. **`object 'plot_opts' not found`.** The store lives in server.R but the module
   referenced it directly. It broke the **entire Data view**, not just the controls.
   `plot_opts` is now a `workspaceServer` argument, and the accessors tolerate `NULL`
   for tests/standalone use.
2. **The controls rebuilt themselves on every keystroke.** `.popt()` read the store
   reactively from inside `.data_ui()` — the very panel holding the controls — so typing
   invalidated the panel, rebuilt it and wiped the box mid-edit. The reads are now
   `isolate()`d; the plot still updates because the dependency is taken in `renderPlot`.
3. **`print.ggplot` was the wrong seam.** `ea_style_gg()` worked when called directly in
   the live session, yet plots rendered unstyled — Shiny's render path does not reliably
   dispatch to an S3 method defined in the global env. Styling now happens explicitly
   inside the `renderPlot` wrapper, alongside `ea_plot_dep()`. No S3 override remains.
   patchwork objects inherit `"ggplot"` but are composites, so they are skipped.

Verified in the browser against a seeded project: setting title/X/Y/colour changed the
rendered PNG, with 1,271 pixels of the chosen `#B4531F` and 645 pixels of title ink in
the top band, and the inputs held their values throughout.

A **"Plot options test"** project (180 rows: dbh_cm, height_m, age_yr, site) is seeded
locally for exercising this.
