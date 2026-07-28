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
