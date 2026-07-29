# BACKLOG — reported 2026-07-29

Raised in one batch after testing v0.8.1. Recorded before any work started, so nothing is
lost and nothing is silently reinterpreted. Each item keeps the reporter's wording, then
my reading of it, then what still has to be decided or checked. **Nothing here is done
yet.** Tick items off as they land, and move the write-up into `UNIFIED_WORKSPACE.md`.

**Settled decision:** voice input is **ruled out completely**. Not deferred — dropped.
Do not re-propose it. (Rationale, for the record: the browser Speech API streams audio to
a third party, which contradicts the local-first promise; local Whisper breaks the
no-toolchain install.)

---

## 1. Project loading shows no progress, and reloads work already done — FIXED 2026-07-29

> "when a project has many files and we click to open, it loads in the terminal but we
> dont see any progress of that in the app - can we make that possible with real info and
> not assumed info? even loaded files reloads, I think its being purged. can we cache this
> to improve load time too?"

**Three distinct problems in one item.**

- **No progress in the app.** The terminal shows the raster/LAS work happening, the UI
  shows nothing. Needs a real progress report during `open_project`.
- **"real info and not assumed info"** — this is a constraint, not a nicety. The progress
  must reflect actual work completed (file N of M, this file's name, this stage), not a
  fake timer or a bar that fills on a guess. Same standard as everywhere else in this app.
- **Files reload every time; suspected purge.** Opening a project re-reads sources that
  were already read. Wants a cache so re-opening is fast.

**Confirmed:** `open_project` does clear the pools and re-read every file, so "being
purged" was exactly right. The cost is almost entirely the point cloud — a 500k-point read
out of an 18.7M-point file.

**Progress.** A `shiny::Progress` now reports the real thing: the counter advances only
once a layer has finished, and each step names the file and what it is
("Loading 2 of 4 — kiihtelys.laz (point cloud)"), plus "cached" when it was not re-read.
No timer, nothing that fills on a guess. Verified in the browser on a cold open.

**Cache.** Keyed by **path + mtime + size**, so an edited file is re-read rather than
served stale. Measured: LAS **19.56 s -> 0.02 s**, vector 0.05 s -> 0.00 s. On the second
open the steps go by too fast to catch.

**Rasters are deliberately NOT cached** — `terra::rast()` only opens a handle, so there is
nothing to save and caching would pin memory for no gain.

**Bounded at 4 entries**, and cleared when the session ends. This is the one place the
memory lesson had to be respected: an unbounded cache of point clouds is precisely how the
app OOM-crashed before (`.read_las_capped`, CLAUDE.md).

Also fixed in passing: `return(NULL)` inside that loop returned from `open_project`
itself, so an unrecognised layer kind silently abandoned every remaining layer.

## 2. Search bar returns nothing — FIXED 2026-07-29

> "the search bar shows no result. maybe it is not wired properly"

**Cause:** the index scraped the OLD menubar for items whose `onclick` set `current_view`.
The unified workspace builds its menu from `.gm-item` and sets `workspace-tool_pick`, so
the index came back empty and every query found nothing. (The guess about `MODUI` vs
`TOOLS` was wrong — it was the menu markup, not the registry.)

**Fix:** index the real menu, and activate a hit by replaying the item's **own** click —
the menu already knows how to open each thing, so the search never models that itself and
cannot drift from it again. Rebuilt per query rather than cached, because the menubar is a
`uiOutput` and a cached index would hold dead element references. Fly-out *parents* are
skipped: a parent is itself a `.gm-item` containing the whole submenu, so its text is
every child concatenated.

Verified: 114 menu items indexed; "regression" returns Linear regression and Logistic
regression, "raster" and "lidar" return their screens, nonsense returns "No tools match";
clicking a hit opens the tool, closes the results, clears the box and closes the menus.

## 3. Black bar in the 3D view — FIXED 2026-07-29

> "in the 3d view, there is a black color there in the bar. it does not match the theme."

**Not a hardcoded hex — it was `card_header(class = "bg-light")`.** Bootstrap's `.bg-light`
is compiled by bslib from the DEFAULT (dark) palette, so it is a near-black that never
follows the theme. **51 card headers across the modules use it**, so this was the same bar
on many screens, not just the 3D one.

Fixed once in CSS rather than 51 times in R: `.bg-light`, `.bg-white`, `.bg-dark` and the
`.bg-body*` family now take the tokens. Every module inherits it, including ones not yet
looked at. Verified on the LiDAR screen: 5 bars, 0 mismatched — light theme
`rgb(238,241,234)`, forest `rgb(19,24,19)`.

## 4. 3D view should be 3D only, and the toggle should be obvious — FIXED 2026-07-29

> "3d view should remove the two pane, map and 3d. 3d is only 3d not map view on 3d. there
> is no way to switch back from 3d to the map view, perhaps, that 3d view should act as a
> toggle. yeah, the button does it but it is not clear."

**Split dropped.** The 3D view rendered `lidarPointcloudCanvasUI`, which pairs the viewer
with a basemap — sensible as a *screen*, wrong as a *view*: asking for 3D and getting a map
beside it is not 3D. A new `lidar3DOnlyUI()` renders the viewer and its static snapshot and
nothing else. Same module, same output ids, so no server logic changed and the basemap
still belongs to the LiDAR screen where it makes sense.

**Toggle now states itself.** Relying on the user guessing that a button labelled "3D view"
also *leaves* 3D is a puzzle, not a toggle. Label, icon and active styling all change:

| state | label | icon | tooltip |
|---|---|---|---|
| on the map | 3D view | cube | Open the 3D point cloud |
| in 3D | **Back to map** | map-location-dot | Return to the map view |

Verified both ways: entering 3D removes the map pane (`lidar-location_map` absent) and
keeps the viewer; the button flips to "Back to map" with active styling; clicking it
returns to Map view with the map present and the label back to "3D view".

## 5. One button on the map housing its controls

> "on the map, I think we can have that button that houses many controls like the zoom
> controls, clip function"

Apply the **`.ea-pop`** pattern (already built, documented in `UNIFIED_WORKSPACE.md`) to
the map: one icon opening a panel with zoom controls, clip, and the other map actions.
**Decide:** exactly which controls belong in it, and whether it replaces the existing
scattered controls or supplements them.

## 6. Right-click functionality

> "we can add some right click functionalities."

Context menus. **Needs scoping before building** — on what, and offering what? Likely
candidates: a layer in the Layers panel (zoom to, rename, remove, export), the map canvas
(clip here, add marker), a results card. Ask before implementing.

## 7. Vector attribute table not working — FIXED 2026-07-29

> "the vector attribute table isnt working really. I am trying to see the attribute table
> of a vector layer but nothing."

**The table was working; the data had no attributes.** A seeded GeoJSON rendered 6 rows
fine, while `ars_plots.shp` rendered blank. The file is 33 features with **0 attribute
columns**, and the project folder held only `ars_plots.shp` and `.shx` — no `.dbf`.

A shapefile keeps its attributes in the **.dbf**. Only the `.shp` had been uploaded;
`SHAPE_RESTORE_SHX=YES` let GDAL rebuild the index, so the layer loaded and drew
perfectly with no hint that the attributes were gone. The ingest code does copy every
sibling part — the parts simply never arrived.

**Fix — at both ends, since the information is lost at upload but noticed much later:**

- **At ingest:** a shapefile that loads with zero attribute columns now raises a warning
  naming the `.dbf` and telling the user to re-add it with every part selected. A missing
  `.dbf` among the uploaded parts warns even when columns did survive.
- **In the attribute dock:** a vector with geometry but no attribute columns states that
  plainly, with the feature count and the `.dbf` explanation, instead of rendering an
  empty grid that reads as a broken table.

Attributes that were never uploaded cannot be recovered — the file has to be added again
with its parts. Verified: the shapefile now explains itself ("33 features but no attribute
columns…"), and a proper vector still shows its real table (6 rows, plot_id/species/stems).

## 8. Linear regression colours, including black — FIXED 2026-07-29

> "the color viz on linear regression isnt good. some hardcoded ones are in there. the
> black too"

Inline hex throughout `mod_linear_regression.R`: grey body text (`#555`, `#888`), fixed
light panels (`#f8f9fa`, `#e9ecef`) and a hardcoded brand green. All now tokens.

The two remaining hex values are `abline(col = "#2e7d32")` inside base plots, left alone
deliberately: base graphics render on their own white device regardless of the app theme,
so a themed colour there would be wrong, not right.

## 9. Adjustable sidebar — FIXED 2026-07-29

> "can we make the sidebar adjustable?"

Both side panels take a drag handle on their shared border: a 6 px strip that stays
invisible until hovered, so it adds no visual noise.

The widths are **CSS variables on the grid** (`--ws-left`, `--ws-right`) rather than inline
widths on the panels. That matters because the panel-collapse classes rewrite
`grid-template-columns`: with fixed values they would have thrown away whatever width the
user had chosen. Written this way, hiding one panel zeroes only its own column and the
other keeps its size.

Clamped to 140-520 px, and a `resize` event fires on release so plots re-measure.

Verified: left 200 -> 290 on a +90 px drag, right 240 -> 310 on a -70 px drag, a 2000 px
drag clamps at 520, and with the left panel hidden the computed template is
`0px 1162.8px 310px 46px` — the right panel holds its custom width and the canvas takes
the freed space.

## 10. Regression output highlighting is unreadable — FIXED 2026-07-29

> "hightliighting the output from the regression cant really be seen due to color problems.
> this should be the same for others, i guess."

This is the assumption-check rows in `.as_row()`: fixed pastel backgrounds
(`#f1f8e9`, `#fff3e0`, …) with grey text, which is legible on a white page and unreadable
on every dark set.

The backgrounds are now a **translucent tint of the semantic colour**
(`color-mix(in srgb, var(--forest) 14%, transparent)`) rather than a fixed pastel, so the
row takes its lightness from whatever is behind it and works on every set. Status colours
map to `--forest` / `--warn` / `--danger` / `--canopy`.

Verified across light, forest and midnight: body text luminance flips 0.08 -> 0.92 -> 0.93
against page 0.97 -> 0.07 -> 0.00, and the tint itself shifts with the theme's green.

## 11. Results / Diagnostics / Assumptions tabs that may do nothing — VERIFIED, they work

> "why do we have results tab, disgnostics, and assumptions if that regression does not
> do it?"

**All three work. Nothing here should be removed.** They only ever looked empty because
the screen could not be run at all — the Response dropdown had no options (item fixed in
`81a6782`), so there was never a fitted model behind the tabs.

Fitting `height_m ~ dbh_cm + age_yr` on 180 rows:

| tab | what it produced |
|---|---|
| Results | plain-English reading (`explains 76.0% of variance … R² = 0.760, RMSE = 1.473, 1 predictor significant`), Model Summary, Performance Metrics, LOOCV, ANOVA table |
| Diagnostics | the diagnostic plot, with its Grid / Single switch |
| Assumptions | Shapiro-Wilk `W = 0.9966, p = 0.9591`, homoscedasticity by Spearman, and the rest |

**A second bug found and fixed while verifying.** The v0.8.1 repopulate fix was
timing-fragile: it bumped `ds_refresh` when a tool was *picked*, but if the panel had not
rendered at that instant the update was dropped again and nothing bumped a second time —
so the dropdown came up empty whenever a project was still loading. The bump now happens
in `session$onFlushed` **after the panel has been sent**, so the update message is
processed after the insert. Message ORDER is what guarantees the element exists.

Verified: all four columns present (`dbh_cm, height_m, age_yr, site`) on a single tool
open, with no repeat picks needed.

**Consequence for item 12:** that redesign is now a layout change over working content,
not a way to hide broken panes.

## 12. Stop competing for space — SELECT what to show, and it splits — FIXED 2026-07-29

> "maybe we should start competing for view and do the simple thing: use a drop down for
> view. this applies to model summary, performance metrics, LLOCV, ANOVA table, the plots,
> Assumption checks. they are too clutter. one view, a drop down to change."

Built first as a single-view dropdown, then extended on the reporter's suggestion: the
dropdown is **multi-select**, and picking more than one splits the area between them with
a draggable divider.

**The default is deliberately ONE.** That is the whole point — clutter you chose is fine,
clutter by default is what was wrong. Six outputs no longer arrive uninvited.

**Stacked, not side by side.** Summary, ANOVA and metrics are wide monospace text that
wraps badly at half width, and plots want width too. Stacking keeps full width for every
pane and trades height instead.

Header controls follow the selection: the CSV download appears when the summary is shown,
the Grid/Single switch when the plots are, and both together when both are.

**Presentation only** — every output id is unchanged, so the server renders exactly what
item 11 verified was already working.

Verified: one selection renders with no pane wrappers; selecting summary + ANOVA +
diagnostics gives 3 labelled panes and 2 dividers, each with real content (602 chars,
245 chars, 1 plot) and the header showing `CSV Grid Single`; dragging a divider moves
146/146/146 to 206/86/146, so it trades height between its two neighbours and leaves the
third alone.

**Rolled out to the other model screens 2026-07-29.** The pattern lives in `helpers.R` as
`ea_view_header()` + `ea_view_panes()`, so each screen is a few lines rather than a copy of
the layout. Converted: **PCA, Decision tree, SVM, XGBoost, Neural network, Survival** —
six screens, twenty-one tabs gone.

Each keeps its own outputs untouched; only the container changed. A tab whose body was
rich (the decision tree's Performance tab, with its own cards and tables) was moved across
whole rather than flattened, so nothing was lost in translation.

Verified in the browser across all six: every picker present with the right options,
each defaulting to ONE selection, no output errors; and selecting three PCA views gives
3 labelled panes with 2 dividers, confirming the shared helper works away from the screen
it was written for.

`mod_linear_regression.R` keeps its own copy because it also has per-view header controls
(the CSV download, the grid/single switch) that the generic helper does not model.

## 13. Plot appearance belongs above the plot — FIXED 2026-07-29

> "the plot appearance button should not be in the side bar, it should be on top of the
> plot. i think it only applies to single variables, what if we have multiple variables,
> does it handle it?"

**Moved.** The `.ea-pop` icon now sits in the result header, directly above the module's
canvas, and is gone from the tool panel. It changes what you are looking at, so it belongs
with it rather than across the screen. Verified: header reads
`Linear regression | Plot appearance … | ← back`, the icon is above the canvas, and no
copy remains in the sidebar.

**Multi-series colour:** parked at the reporter's request. Title and axis labels work
regardless; the single colour applies only to fixed-colour layers, and a palette for
multi-series plots is a separate piece of work.

**Console plots are NOT affected — deliberately.** Asked whether the tool colours plots
drawn from the R console. Tested: it does not (10 px of title ink in the top band, i.e.
none). It was true only by accident, because the console prints its ggplot itself rather
than returning it to the wrapper, so `mod_rconsole.R` now calls `shiny::renderPlot`
explicitly with a comment saying why. In the console **your code is the source of truth**:
if you write `geom_point(colour = "red")`, the app repainting it from a screen's settings
would be the app lying about what your script does.

---

## Cross-cutting

Items **3, 8, 10** are all the same underlying problem — hardcoded colours that ignore the
active theme — on three different screens. Worth one sweep with a browser check across the
colour sets rather than three separate patches, and note the measurement trap in CLAUDE.md
gotcha 24 when verifying.

Items **11, 12** are entangled: settle what actually works before redesigning around it.

Items **5, 13** both use the existing `.ea-pop` pattern, so they are cheap once its
placement rules are agreed.


---

# BACKLOG ROUND 2 — reported 2026-07-29 (after the round-1 fixes)

Recorded before any work starts. Reporter's wording first, then my reading, then what has
to be decided or checked. **Nothing here is done yet.**

Four of these look like they come from my own recent changes; they are marked
**LIKELY REGRESSION** so they are checked first rather than treated as new features.

---

## A. Theme / colour (same family as round-1 items 3, 8, 10)

### A1. Black on the packages page
> "black color on the packages page"

The package install/list modal. Round 1 fixed `.bg-light` and the Bootstrap surface
variables; this is somewhere those did not reach.

### A2. Black in the Project dropdown, including Share project
> "the share project has the black color thing. check everything in the dropdown under
> project for that black hardcoded color."

**Explicitly a sweep, not one fix** — check every entry under the Project menu.

### A3. Card and text colour in light mode
> "dont like the card color and the color of the text in light mode."

A judgement call rather than a defect. **Decide:** what should change — card background,
body text, or both? Worth a side-by-side before changing tokens that affect every screen.

---

## B. Data & Exploration

### B4. Dataset information missing from the options
> "in the data & exploration the dataset information is not being seen in the options"

### B5. Tabs do nothing — everything lands on Dataset Overview  **LIKELY REGRESSION**
> "the tabs in the data & exploration does not working. everything has been placed on
> dataset overview. column distributions and plot reslationships shows nothing."

Same shape as round-1 item 11 (tabs that looked broken). Check first whether this is the
lazy-render/repopulate problem again, or something the select-and-split rollout disturbed.
`mod_data.R` was NOT converted, so it should be untouched — which makes this worth
diagnosing rather than assuming.

### B6. Separate the commands, but keep them synced
> "separate the columns in data and exploration each command should now be separate but
> for course be synced."

Each ETL operation gets its own space rather than sharing one column, while still acting
on the same dataset. **Decide:** does this mean the select-and-split treatment, or
something else?

### B7. Batch apply on each data-processing tool
> "one key thing to add when processing data is batch apply. I think the position should
> be on each data processing tool."

Apply an operation to several columns/datasets at once, with the control living on each
tool rather than in one central place.

### B8. Edit data table does not work
> "edit data table does not work. no editing ability."

The View Data modal is built with `editable = "cell"` and has a `cell_edit` handler, so
this needs diagnosing rather than building.

---

## C. R Console / scripting

### C9. Working on a NEW dataset every time is wrong
> "it created a new dataset. creating a new dataset all the time if there is a change is
> not the best or smartest move. we need it working on the dataset selected."

From the round-1 write-back feature: `vmi9_transformed <- df %>% mutate(...)` correctly
became a new layer, but the reporter does not want a new dataset per edit. **Decide:**
should an assignment that transforms `df` UPDATE the active dataset instead of adding a
layer? That is a real design choice — overwriting loses the original, adding clutters.
Possibly: update in place when the result replaces `df`, add a layer when it is clearly
new. Needs a rule stated before code.

### C10. `df` for everything — can data be renamed?
> "is it possible to rename how the data is called? cus df is for everything."

Expose each dataset under its own name as well as `df` (the console already assigns
`make.names(name)`), and/or let the user choose the alias.

### C11. Run line-by-line, not the whole buffer
> "for the console, can we line running instead of running everything everytime we click
> run?"

Run the current line or the selection, like RStudio's Ctrl+Enter. Pairs with C13.

### C12. Load an R script, visible only in the terminal; editor tabs
> "is it possible to load r script but should only be visible in the terminal? and can the
> script editor have tabs?"

Open a `.R` file into the console editor without it becoming a project dataset, and hold
several scripts as tabs.

### C13. Environment pane as an adjustable third column
> "in r console, there is an environment view, can we make a third column next to rconsole
> and where the results are displayed? should also be adjustable."

Editor | Results | Environment, with draggable dividers. The pane-splitter pattern from
round-1 item 12 already exists and should be reused.

### C14. The toolbar fills for plots but not other commands
> "the tool bar fills for plots but not for other commands."

Needs clarifying: which toolbar, and what "fills" means.

---

## D. Views and switching

### D15. Active dataset does not change when another is clicked — FIXED 2026-07-29
> "the active dataset does not change when we click other datasets."

**Cause:** the layer row set only the workspace's own `activeLayer`. The app-level
`active_ds` — which every model screen, the status bar and the data view read — was never
touched, so the click highlighted a row and nothing downstream moved. Confirmed by the
reporter: "when we changed the data or selected another in the panel, the view in the
lower tab did not change."

**Fix:** clicking a **table** layer now also sets the app-level `active_dataset`.
Verified live: active dataset went from the CSV to `second_table` on click.

### D16. Tab switching should be complete — PARTLY FIXED 2026-07-29 (tab/view desync)
> "even though only csv or excel ... the default panel was Maps but the data view was
> kinda showing there. this should a complete tab switch. and even though there are only
> text file, it does not mean the map should not be displayed on the map view. the map
> view is always there. just that when project does not contain the necessary file to be
> displayed, we simply automically swtich them there."

Two rules: switching views must be complete, not a blend; and the Map view always exists —
it is the *default choice* that follows the data, not the view's existence.

**Half of this is fixed: the tab and the view could disagree.** The strip toggled its own
`.on` class in JS while `wsview()` lived on the server, so anything that changed the view
server-side — opening a map tool, the canvas following the data — left the old tab lit.
That is what "the data view was kinda showing there" described. The strip is now rendered
from `wsview()`, so there is one source of truth. Verified: a server-driven switch to the
data view moved the lit tab with it.

**Still open:** the map view must exist regardless of what the project holds, with the
default choice following the data.

### D17. Opening a tool must not change the view  **LIKELY REGRESSION**
> "download spatial data switches the tab if we are in map view we click it. should not be
> like that. the map view should remain since only the tool box gets displayed."

Picking a tool should load its settings panel and leave the current view alone.

### D18. Spatial & LiDAR screens still carry their own views  **LIKELY REGRESSION**
> "the point cloud or 3d view opens two views. i thought we dixed that. everything if not
> all under spatial and lidar still carries their own view. that needs to be fixed. we
> have the map view and the data view of that."

Round-1 item 4 fixed the **3D view** only; the LiDAR *screens* still render their own
map+viewer canvases. The rule wanted: modules never bring their own view — the workspace
map view and data view are the only ones.

---

## E. Model screens

### E19. Variable selection differs per screen
> "the selection of variables should follow the same pipeline. right now xgboost is
> different. same for decision tree, and others under machine learning."

### E20. Reuse the existing predictor picker
> "we had a easier way ... selecting multiple predictors was a drop down with selection
> shown with checkmark."

E19 and E20 are the same job: one shared variable-selection component, reused everywhere,
matching the multi-select-with-checkmarks that already exists.

### E21. Move "Select Diagnostics to View:"
> "change the position of this: Select Diagnostics to View:"

### E22. Separate linear regression from the other regression types
> "separate linear regression from the other types of regression in there."

The screen currently mixes plain `lm` with glmnet/poisson paths.

---

## F. Tables, reports, chrome

### F23. Table view is unreadable
> "the scroller for the table view is at the bottom and the header is not sticky. can put
> the scroller up for left to right to see the other columns or make the header sticky?
> also, reduce the size of the table, columns are too big and text size is big too."

Sticky header, reachable horizontal scroll, smaller type and tighter columns.

### F24. Replace the placeholder text with the tour
> "I dont understand this text: Pick a tool above. Its settings load here; spatial ops add
> a layer, models drop a result (Step 4). remove it and replace it with the tour guide
> button. but of course it will removed when the tool box gets loaded. and make sure the
> tour works. show at least 8 parts of the screens in the tour."

Remove the developer-speak placeholder, put the tour button there instead, hide it once a
tool loads, and **extend the tour to at least 8 steps**.

### F25. Export report as PDF
> "can export report support pdf too?"

Needs checking what the current export produces and whether a PDF path exists without
adding a LaTeX dependency (which would break the no-toolchain install).

### F26. Plot appearance appears on every screen — FIXED 2026-07-29
> "the plot appearance looks sticky on all the pages"

From round-1 item 13: it was moved into the result header, which every tool shows —
including ones with no plot.

**Decision taken:** show it only on genuinely plot-bearing screens, and **in the plot
section** rather than the screen header.

Counting `plotOutput` per module made the first half almost moot: **every screen except
SEM has plots**, so a screen-level whitelist would filter nothing. The real fix was
placement — it now appears beside the plot, only while a plot view is on screen.

`ea_plot_appearance()` (helpers.R) is markup any module can drop next to its plot; it
writes straight to the workspace-level `po_*` inputs, so there is still ONE store behind
it and no per-module server wiring.

Wired into Linear regression and the six select-and-split screens. Verified on LM: with
"Model summary" selected the control is absent from both the screen header and the view
tools; adding "Diagnostic plots" makes it appear in the view tools.

#### Completing it across the remaining screens — DONE 2026-07-29

The twelve screens that still had their own layouts showed no control at all. Now:

- **Time series, GAM, Wind, Bayesian** — were plain `navset_card_tab`, so they were
  converted to select-and-split and pick the control up the same way the other six do.
- **Data, Descriptive, Tests, Logistic, LME, RF, Clustering, Classification, ANOVA, DA,
  LiDAR (3 canvases)** — keep their layouts; the control sits in the header of the card
  holding the plot.

**`ea_is_plot_view()` is gone.** It decided "is this view a plot?" from the view KEY, and
was wrong on most screens — it missed `posterior`, `performance`, `wind_rose`,
`cox_ph_model`, `cp`/`imp`/`perf` and every timeseries plot. No name rule could work:
`predictions` is a plot on XGBoost and a table on the neural-net screen. Each screen now
declares `.<TAG>_VIEWS_PLOT`, derived from the bodies it actually renders, and
**`check_plot_views.R`** re-derives it from the parse tree and fails on drift.

`ea_plot_appearance(fields = ...)` now offers only what a plot honours. Raster previews
pass `fields = "title"`: they draw a map with a data-driven palette, so axis labels and
colour would do nothing.

Also wired plots that were half-connected — hydrology and land classification read the
title override on export but not in the preview; the LiDAR snapshot, CHM and evaluation
plots read none of it.

**Still dormant:** terrain, hydrology, suitability, land classification and night-time
lights are `map_based` in the workspace registry (mod_workspace.R:1480-1488), so their
canvas is never mounted — they draw on the map instead. Their control is in place but
unreachable until D18.

---

## Suggested order

1. **The likely regressions** — B5, D17, D18, F26. My changes, so mine to check first.
2. **D15** (active dataset not switching) — a core interaction, and other things depend on it.
3. **The colour sweep** — A1, A2 together, as in round 1.
4. **F23** (table readability) and **B8** (table editing) — same surface.
5. **E19 + E20** — one shared variable picker, then E21, E22.
6. **The console group** — C11, C13, C12, C10, then C9 once its rule is decided.
7. **Decisions needed before building:** A3, B6, C9, C14, plus round-1 items 5 and 6.
