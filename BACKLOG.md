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

## 5. One button on the map housing its controls — DONE 2026-07-30

> "on the map, I think we can have that button that houses many controls like the zoom
> controls, clip function"
>
> scoped later: "plus other basic map functions"

A `.ea-pop` button at the right of the map strip, before the 3D toggle: **Zoom to all layers**,
**Zoom to active layer**, then **Attribute table**, **Layers panel**, **Tool panel**. It
supplements the Controls menu rather than replacing it — the same actions are still up there,
but they no longer require leaving the map to reach them.

Per-layer actions deliberately are NOT in it: those belong to a layer, so they live on the
layer's right-click menu (item 6). Clip is not in it either — the two draw-based clips need a
polygon drawn on the map, and the pool-driven equivalents are searchable algorithms
("Clip raster to vector layer", "Buffer").

Verified: the button opens with all five entries; "Layers panel" toggles `no-left` on the grid
and toggles it back.

## 6. Right-click functionality — DONE 2026-07-30

> "we can add some right click functionalities."
>
> scoped later: "zoom to layer, right clicking on the layer to rename it. plus other basic map
> functions."

Right-clicking a layer row opens a menu at the cursor with **Zoom to layer**, **Rename…**,
**Show/Hide layer** and **Remove from project**. Left-click still selects the layer, so nothing
existing changed. One menu element is reused for every row and closes on outside click or Escape.

**Zoom to layer** also selects the layer, so the legend and attribute dock follow what you just
zoomed to.

**Rename is handled in `server.R`, not in the workspace module**, and that placement matters: a
rename has to move every trace of the name at once, and some of those exist only at app level —
`raw_pool` (what "Reset to upload" restores), `src_paths` (the project's copy of the file) and
`active_ds`. Renaming inside the workspace would leave `raw_pool` keyed by the old name and
quietly break Reset to upload. It refuses an empty name and a name already used in the project.

**Bug found while verifying:** the first version renamed nothing and left the dialog open.
`layer_style` is a `reactiveVal` holding a *list*, not `reactiveValues`, so `layer_style[[old]]`
aborted the whole observer before `removeModal()`. It is read, edited and written back now.

Verified end to end on a real project: right-click gives the four actions; Rename moves the
layer name and the status bar's Active follows it; renaming back restores the project exactly
(`trees`, 180 x 4).

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

### A1 + A2. Black on the packages page, and in the Project dropdown — FIXED 2026-07-30
> "black color on the packages page"
>
> "the share project has the black color thing. check everything in the dropdown under
> project for that black hardcoded color."

**One cause, both reports: `.modal-footer`.** Measured in light mode, the footer strip under
every dialog computed to `rgb(37,41,37)` while `.modal-content` was correctly white. It is
gotcha 22 again — bslib's compiled `bootstrap.min.css` contains a **literal**
`.modal-footer { background-color: rgb(37,41,37) }` from the default (dark) palette, so
`html[data-ea-theme]` can never reach it. Every dialog in the app shares it, which is why the
same bar appeared on the packages page and in Share project.

Set to `transparent`, so the frosted `.modal-content` shows through in either theme.

**Swept rather than spot-fixed.** Scanning the compiled bootstrap for *every* rule whose
background is a literal rgb() dark enough to read as black found **30**. Of those, the ones on
surfaces this app renders were `.modal-footer`, `.input-group-text` (rgb(37,41,37)) and
`.btn-light`/`.btn-outline-light` hover (rgb(33,37,33)) — all three now take tokens. The rest
were `.carousel-indicators` and `.progress-bar-light`, which the app never renders, plus the
`.datepicker` family (~20 rules), which IS reachable via the date inputs in
`mod_rs_search.R` and is **still open** — see A4.

Verified: in light mode the packages dialog now reports `.modal-footer` as `rgba(0,0,0,0)` and
**no** element inside it with a dark opaque background. And an audit of every `showModal()` in
the app (5 in the workspace, including Share this project and Collaborate) found **no**
hardcoded dark hex and no dark Bootstrap colour class anywhere, so the footer really was their
only dark surface.

### A4. Datepicker carried dark literals — FIXED 2026-07-30
Found while sweeping A1/A2. **32** `.datepicker ...` rules have literal dark backgrounds — day
hover, today, highlighted, range, selected, the header arrows, and every focus/active/disabled
variant. bslib compiled `bootstrap-datepicker.css` from the default (dark) palette as well, so
on a light theme the hovered day, the selected day and the range fill all read as dark blobs.
Reachable: `mod_rs_search.R` ("Download spatial data") uses two `dateInput`s.

**Why `!important` here and nowhere else in the sweep:** that stylesheet is injected as a Shiny
*dependency* the first time a `dateInput` renders, which is AFTER the head styles — source order
cannot win. Confirmed it is safe to rely on: none of the four datepicker CSS assets shipped with
shiny contains `!important` at all, so an important declaration wins by spec rather than by
luck with load order.

Verified with the datepicker stylesheet actually loaded, light theme, by measuring a synthetic
calendar (the cascade applies by selector, so this is the real answer):

| state | before | after |
|---|---|---|
| container | — | `rgb(255,255,255)` |
| today / highlighted | `rgb(37,58,39)` | `rgb(238,241,234)` |
| range fill | `rgb(30,34,31)` | `rgb(238,241,234)` |
| selected | dark green | `rgb(46,125,50)` + white text |
| plain day | — | transparent, dark text |

### A3. Card and text colour in light mode — DEFECT PART FIXED 2026-07-30
> "dont like the card color and the color of the text in light mode."
>
> clarified: "i meant the cards that show the data summary. not sure if we are talking abou
> the same card here"

**Identified:** the six `value_box()` tiles across the top of Dataset Overview — Rows,
Columns, Numeric, Categorical, Total NA, Complete rows (`output$overview_stats`, mod_data.R).

**It was not a taste call, it was a defect.** Measured in light mode, all six tiles came out
`rgb(126,212,129)` — one loud mint — because `value_box(theme=)` goes through Bootstrap's
`.bg-*` utilities, which bslib compiled once from the dark palette, and `theme.R:49-51` maps
`secondary`, `success` **and** `info` all to `canopy`. Two consequences: the tiles never
followed the theme, and the semantic distinction was gone — a non-zero NA count looked
identical to the row count.

**Fixed:** neutral raised surface in both themes, with colour kept for the tile that is
actually signalling something (an amber inset edge when NAs are present). Used an inset
box-shadow rather than a tinted background so it needs no `color-mix()` and cannot fall back to
Bootstrap's green. Scoped to `.bslib-value-box` so buttons and badges keep their colours.

Verified: light `rgb(238,241,234)` tiles with `rgb(16,21,15)` text; forest `rgb(19,24,19)`
tiles on a `rgb(15,19,16)` page with `rgb(232,237,228)` text, so they read as raised panels
either way.

**Not verified:** the amber NA edge — the test dataset has 0 NAs, so no `bg-warning` tile was
rendered to measure.

**Still open if wanted:** body text colour app-wide, and card surfaces outside these tiles.
Those are genuine taste calls and were not touched.

---

## B. Data & Exploration

### B4. Dataset information missing from the options
> "in the data & exploration the dataset information is not being seen in the options"

### B5. Tabs do nothing — everything lands on Dataset Overview — FIXED 2026-07-29
> "the tabs in the data & exploration does not working. everything has been placed on
> dataset overview. column distributions and plot reslationships shows nothing."

Two independent bugs that happened to land on the same screen. It was worth diagnosing
rather than assuming: neither cause was the select-and-split rollout.

**1. Every tab rendered at once (`ui.R`).** The workspace fill rule listed
`.html-fill-container` as one of its selectors — and every `tab-pane` carries that class.
It is more specific than Bootstrap's `.tab-content > .tab-pane { display: none }`, so
inactive panes were `display: flex` too. All three tabs were on screen, stacked, and
clicking one did nothing visible because its pane was already showing. Fixed with
`:not(.tab-pane)`; active panes were already covered by `.tab-pane.active`. See gotcha 25.

**2. The pickers were empty, so the two plot tabs had nothing to draw.** This was gotcha
18 (lazy render drops `update*Input`) reaching every screen except this one. Logging
`inputMessages` off the websocket while re-opening a tool showed `lm-y`, `anova-y`,
`rf-target`, `da-*`, `logistic-*`, `lme-*`, `clustering-*` and `classification-*` all
re-arming, and **zero `data-*` messages**. Two compounding reasons: `observeEvent`
isolates its handler, so `active_dataset()` read inside the body is not a dependency; and
the re-arm arrives here as `rv$working_data <- <the same data frame>`, which does not
invalidate. Fixed with a shared `pop_arm()` reactive as the event expression. See
gotcha 26.

Verified in the browser: one pane visible at a time, all four columns in every picker
split correctly into numeric/categorical, Column Distributions renders its plot and
summary, Plot Relationships renders the grid.

**Noticed while testing, not part of B5:** at ~1265px the top bar overflows and the whole
page scrolls sideways (`.app-topbar` / `.topbar-right` extend to 1519px). Unrelated to
the pane CSS.

### B6. Separate the commands, but keep them synced — DONE 2026-07-30
**CORRECTED after testing.** I first moved the commands into the canvas as select-and-split
views. That was wrong, and the reporter said so plainly:

> "that is how the entire app has always been. we select the tool from the analysis tab and the
> settings under that tool goes into the sidebar. the only change was that we had many tools
> under one umbrella which hid other tools. so, the goal was to separate them but the logic
> remained"

So the app's logic is unchanged: **pick a tool, its settings appear in the tools sidebar.** The
only thing B6 changes is *unbundling* — commands that were hidden under an umbrella panel are
now separate, findable tools. The canvas keeps the three dataset views (overview + the two
exploratory plots) with the select-and-split header.

The ETL toolbox was nine accordion panels crammed into the narrow tools column, and several
panels bundled *more than one* command — Column Management held keep / drop / rename / mutate,
Level Management held rename / merge / delete levels. So "each command separate" meant
unbundling too: **14 commands**, plus the 3 exploration views, as **17 pickable entries**.

Pick one and it fills the canvas; pick several and they split with draggable dividers. "Synced"
needs no work — every branch reads and writes the same `rv$working_data`, so two commands open
side by side act on the same dataset.

**Input ids are unchanged**, so all ~15 existing observers drive exactly the same controls. The
tools column now holds the hint and Reset to Raw Data.

**The trap this created, and the fix.** Each command's controls are built the first time its
view is picked, so the population observers had to run *again* afterwards or the pickers would
arrive empty — gotcha 18, now fired by the view picker instead of the tool menu. Bumping on
`input$view_pick` directly is too early: the update would be sent in the same flush that inserts
the UI, and Shiny drops an update aimed at an element that does not exist yet. `session$onFlushed`
fires once that flush is out, so the update follows the insert.

That part is **not testable under `testServer`** (`onFlushed` behaves like `debounce`, gotcha 15),
so it was verified in the browser instead.

Verified: 17 entries in the picker; all 17 views render; a two-command split gives 2 panes and a
divider; the appearance control appears on the 2 plot views and not on commands or Overview.
Picking a command populates its controls — checked 9 of them, with the right types
(`site` for the categorical commands, `dbh_cm` for the numeric ones). End to end, Drop columns
on `age_yr` took the dataset from `180 x 4` to `180 x 3`, and Undo put it back.

**REGRESSION I INTRODUCED, then fixed (same day).** Reported as
*"Could not load 'Column Management'"*, *"Could not load 'Row Filtering'"*, and the tools panel
showing only the hint — "all of the commands are not loading".

Cause: the workspace **already** listed each ETL operation as its own menu entry (`DATA_OPS`,
nine hardcoded titles) and `.data_op_ui()` rendered one by pulling the matching
`.accordion-item` out of `dataToolsUI("data")`. I replaced that accordion with canvas views, so
there was no accordion left to find and every entry failed. B6 was half-built already and I
broke that half instead of extending it.

Reconciled onto one source of truth:

- `DATA_OPS` is now **derived from `.DATA_VIEWS`** (commands only), so the menu and the canvas
  picker cannot drift apart again. It lists 14 commands, not the old 9 bundles.
- A "Prepare data" entry opens the Data screen and selects that command in its picker. The
  workspace cannot move another module's picker across namespaces, so it sets a top-level
  `data_op_request` input which `server.R` passes to `dataServer`. Going through the server
  avoids poking the selectize from JS after a guessed delay for the panel to exist.
- `.data_op_ui()` and the four dead `dataop:` guards are gone.

Verified in the browser: all 14 commands appear under Prepare data; clicking "Filter rows"
opens the screen with the picker on `filter`, `filter_col` populated and its condition UI
rendered (1413 chars); clicking "Merge levels" gives `agg_col` = `site` (categorical only) and
its real levels `Peat, Dry, Mesic` — the deepest dependency chain in the module. No
"Could not load" anywhere.

Also extended `check_plot_views.R`: a view whose plots come from a server-built
`uiOutput(... "plot" ...)` now counts as plot-bearing. Without that it called
"Plot relationships" a text view — the evidence is still read from the code, not guessed from
the view's name.

### B6-original. Separate the commands, but keep them synced
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

### B8. Edit data table does not work — FIXED 2026-07-30
> "edit data table does not work. no editing ability."

Diagnosed rather than rebuilt, and the table was never the problem: **there was no way to open
it.** The menu entry named "Edit data table" called `.setTool("data")`, which just opens the Data
screen. The only control wired to the editable viewer is a button in `.app-left`, and the
workspace sets that rail to `display:none` — so on the app's main screen the editable table was
unreachable. The entry now opens the viewer.

Two further problems found while verifying:

- **Editing rebuilt the whole table.** The render depended on `dataset_pool`, so committing a
  cell re-rendered everything and threw away the page and scroll position mid-edit. The data is
  read with `isolate()` now — DT already updates the edited cell in the browser.
- **That made the viewer show stale data on reopen** — a regression I introduced with the
  isolate: closing and reopening the modal did not invalidate the output, so Shiny re-sent the
  cached render. Fixed by depending on `input$view_data`, so each open re-reads while an edit
  still does not.

Also guarded the handler's indices. `col` counts the rownames column, so column 0 is the row
label rather than data: `df[i, 0]` returns a 0-column data.frame, which makes `coerceValue` warn
("data type is not supported: data.frame") and the assignment fail with "attempt to select less
than one element" — both reproduced directly. Out-of-range indices are now ignored instead of
erroring inside an observer, where the failure is silent, and a value the column cannot take
reports itself instead of vanishing.

Verified end to end on a real project: editing `dbh_cm` row 1 from 44 to 99 persisted, a fresh
open read back 99, and setting it to 44 restored it — so the project is unchanged.

---

## C. R Console / scripting

### C9. Working on a NEW dataset every time is wrong — FIXED 2026-07-30
**Decided: update the existing layer in place.**

`df <- ...` already wrote back to the selected dataset. The new part is honouring that for a
**renamed** result: `vmi9_transformed <- df %>% mutate(...)` now edits the selected dataset
instead of adding a layer called `vmi9_transformed`, which is the case that was reported.

**Guarded to one such output.** With several tables derived from `df`
(`a <- df[1:10,]; b <- df[11:20,]`) there is no single answer to which one *is* the dataset, and
letting the last one win would silently destroy the other — so in that case each keeps its own
name, as before. Derivation is read off the parse tree (does `df` appear in the right-hand
side?), not guessed from the name.

Verified with `testServer` on all four cases:

| script | result |
|---|---|
| `df$logdbh <- log(df$dbh_cm)` | `trees` updated in place, 3 -> 4 cols |
| `vmi9_transformed <- df; ...$logdbh <- ...` | `trees` updated, **no stray layer** |
| `a <- df[1:2,]; b <- df[3,]` | both keep their own names, `trees` untouched |
| `fresh <- data.frame(z = 1:3)` | new layer `fresh`, `trees` untouched |

The console line reports which happened — "(table, updated in place)" versus "(table)".

**Note the trade-off you accepted:** an in-place update replaces the dataset, so the pre-edit
version is gone unless it was saved. Undo in the Data screen still covers edits made there, not
console edits.

### C9-original. Working on a NEW dataset every time is wrong
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

### C14. The result area fills for plots but not other commands — FIXED 2026-07-30
> "the tool bar fills for plots but not for other commands."
>
> clarified: the workspace tab strip / result area above the canvas.

**Measured, and it was worse than reported** — the two cases failed in opposite directions.
On Linear regression, in the same 572px container:

| view | card height | result |
|---|---|---|
| Model summary (text) | 444 | 128px of dead space below it |
| Diagnostic plots | 704 | **overflowed the panel by 132px** |

Cause: a solo plot carries a fixed pixel height from R (`height = if (solo) "560px"`), so the
card grew past its container, while text panes size to their content and left a gap. Nothing
in the chain was flex.

**Fix:** the single-card case is a real flex chain now — the card takes the height it is given
and `.lm-viewport` absorbs the remainder. A solo plot fills the viewport instead of forcing
560px; the plot is a *grandchild* (`.lm-viewport > uiOutput > plotOutput`) so the wrapper needed
a definite height before the plot's `100%` could resolve.

`:only-child` throughout, deliberately: screens that stack SEVERAL cards must keep sizing to
their content. Verified that guard holds — ANOVA's 5 cards still measure 618/398/398/101/101
rather than all being stretched.

Verified: text view card 556 of 572 (16px is the card's own margin); plot view card 556 with the
plot 412 inside a 432 viewport, so it fits with no scroll and no overflow; the two-pane split
still gives 225 + 225 with its divider.

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

### D17. Opening a tool must not change the view — FIXED 2026-07-30
> "download spatial data switches the tab if we are in map view we click it. should not be
> like that. the map view should remain since only the tool box gets displayed."

**Reproduced first**, in a tables-only project: sitting on Map view, clicking "Download spatial
data" flipped to Data view.

**Cause: two of my own mechanisms fighting.** The "canvas follows the data" rule picks the view
from what layers exist, but only while `user_picked_view()` is FALSE. That flag was re-armed by
`observeEvent(active_dataset(), ...)` — and `active_dataset()` deliberately depends on
`ds_refresh`, which server.R bumps on **every tool open** to re-arm selector population
(gotcha 18). So opening any tool threw away the user's view choice and re-derived the view from
the data. In a tables-only project that means Data view, which overrode even that tool's own
`wsview("map")` request, since it is `map_based`.

**Fix:** compare the value before re-arming — a `ds_refresh` bump leaves the dataset name
unchanged, so it is now a no-op. A genuine dataset change (opening a project) still re-arms.

Verified in the browser: project opens on Data view (correct for tables-only), clicking Map
view sticks, and opening "Download spatial data" leaves Map view active.

**Deliberately kept:** a `map_based` tool opened from Data view still switches to the map. Its
results are drawn on the map and its canvas *is* the map, so opening one with the map off screen
would hide the thing it produces. If that turns out to be unwanted too, it is one line
(mod_workspace.R, the `tool_pick` observer).

### D18. Spatial & LiDAR screens still carry their own views — PART 1 DONE 2026-07-29
> "the point cloud or 3d view opens two views. i thought we dixed that. everything if not
> all under spatial and lidar still carries their own view. that needs to be fixed. we
> have the map view and the data view of that."

Round-1 item 4 fixed the **3D view** only; the LiDAR *screens* still render their own
map+viewer canvases. The rule wanted: modules never bring their own view — the workspace
map view and data view are the only ones.

**Diagnosis.** Opening a non-`map_based` tool *replaces* the workspace map with the module's
canvas ([mod_workspace.R:793](mod_workspace.R:793)), and `lidarPointcloudCanvasUI` contained
its own leaflet basemap **and** its own 3D viewer — hence "opens two views". Two further
facts came out of it: the CHM and detected treetops never left the module (never written to
`raster_pool` / `vector_pool`), so the workspace map *could not* draw them, which is why the
screen needed a map of its own; and CHM was implemented twice, identically, here and in
Surface models.

**Decisions taken (user):** results become layers, and the few genuinely non-map outputs move
into the tool panel. Then, mid-build: *"these ITD should be separate. like qgis plugins does.
basically, we treat these as plugins-like"*, *"CHM is separate"*, *"DTM is separate and so on.
if I want to create DTM, I can simply search DTM and run the process and see it on the map"*,
*"the same is true for many other commands"*.

**Part 1 — the processing-algorithm framework (done).** `algorithms.R` + `mod_algo.R`: one
searchable tool per operation, output straight into a pool, map keeps the centre. Registered:
**DTM, DSM, CHM, nDSM, ITD**. Retired: the "Surface models" radio bundle and the
"CHM & tree detection" screen. See the CLAUDE.md section for the spec format.

Verified: all five specs render; against a synthetic classified point cloud the DTM comes out
as exactly the ground plane (100.0–101.2 for a 100 + 0.02x surface), nDSM peaks at 21.7 m
against a planted 22 m tree, and ITD run on the CHM the CHM tool produced finds the 3 planted
trees — i.e. the chaining through the pool works. `testServer` on the runner: empty pool shows
a hint instead of a blank picker, a run writes the layer, a second run makes `DTM_2` rather
than overwriting, an explicit name is honoured.

**Part 2 — the last two LiDAR screens (done).** `pointcloud` and `metrics` are now
`map_based` with `canvas = NULL`, and all three canvas functions are deleted:

- `lidarPointcloudCanvasUI` carried its own leaflet basemap **and** its own copy of the 3D
  viewer, static snapshot and `snap_pts` slider — the same output ids `lidar3DOnlyUI` uses, so
  opening the screen while the 3D view was up would have put duplicate ids in the DOM. The 3D
  view button is now the only home for those.
- Non-layer output moved into the tool panels as collapsed accordions: height/intensity
  histograms + LAS summary under Point cloud / 3D, model evaluation (text + scatter) under
  LiDAR metrics. The CRS fallback UI moved there too — it used to sit under the basemap.
- The extracted metrics table was dropped from the panel: it already goes to `dataset_pool`,
  so it shows up as a table in the **data view**. No reason to render it twice.

Verified with `testServer`: opening `pointcloud`, `metrics` or any `algo_*` tool leaves the map
in the centre and shows the "results are drawn on the workspace map" note, both panels carry
their own outputs, and `lidar3DOnlyUI` is the sole holder of the viewer/snapshot ids.

**Part 3 — the other bundled operations (done).** 28 more entries, ported by reading each
module's own `switch()` rather than reimplementing: 9 terrain, 6 hydrology, 10 raster, 3 vector.
**33 algorithms in five groups.** Also retired "Terrain analysis" and "Hydrology" — every
operation they had is an entry now, so keeping them would mean two ways to compute the same
slope. Nothing visible was lost: both were already `map_based`, so their preview/info/stats
canvas was never mounted, and the Raster tool exports any pool layer as GeoTIFF plus a map
image. `mod_raster.R` **stays** (layer management, symbology, annotation, draw-based ops).

**Two pre-existing bugs surfaced by porting:**

1. **Profile and plan curvature never worked.** `mod_terrain.R` called
   `terra::terrain(dem, "profc"/"planc")`, but terra 1.9.11 has no curvature variable at all —
   only slope, aspect, TPI, TRI, TRIriley, TRIrmsd, roughness, flowdir. Picking either option
   errored with "unknown terrain variable". Rather than drop two options that had been visible
   in the UI, `.ea_curvature()` now computes them properly (Zevenbergen & Thorne 1987) from
   focal weight matrices — one matrix per partial derivative, so nothing depends on the order
   terra hands window values to a callback. Verified analytically: for `z = a(x^2+y^2)` it
   returns exactly -2a (profile) and +2a (plan) with sd ~1e-16, a saddle straddles zero, and a
   plane gives ~0.
2. **`flowacc_wb` failed once and never again.** The first full-suite run showed
   "Error running WhiteboxTools (FillDepressions)" and a missing output file. It did not
   reproduce — not in isolation (twice), not in the same suite afterwards. Recorded as a
   transient temp-file/WBT race on first invocation, **not** as something that was fixed.

**Not ported, deliberately:** "Crop raster to drawn shape" and "Clip vector to drawn shape"
both read `rv$drawn`, a polygon drawn on the map, so they are map interactions with nothing to
pick from a pool — they stay in `mod_raster.R`. `mod_suitability.R` stays too: its criteria list
is variable-length, which the static-parameter spec cannot express.

Verified: all 33 run against real fixtures (synthetic classified point cloud, a 6-band stack, a
2-polygon layer) with sane numbers — DTM = the ground plane, mosaic 20x20+20x20 → 20x40, and the
four spectral indices come out at exactly the values the band multipliers predict (NDVI 0.2174,
NDWI -0.12, NBR 0.333, NDRE 0.1428). All 33 labels appear in the menu, all four retired bundles
are gone, and `testServer` confirms band pickers show real band names with the spec's defaults
preselected, the field picker lists attributes and excludes `geometry`, multi-layer input works,
and a table-output algorithm lands in the data pool rather than the raster pool.

**Next obvious port:** `mod_land_classify.R` (k-means on a raster) is a clean single operation.

---

## E. Model screens

### E19. Variable selection differs per screen
> "the selection of variables should follow the same pipeline. right now xgboost is
> different. same for decision tree, and others under machine learning."

### E20. Reuse the existing predictor picker
> "we had a easier way. one way is to wite the code. the second way is to use the quick
> editor. why not resude these components here. selecting multiple predictors was a drop
> down with selection shown with checkmark."

**Full quote restored 2026-08-04** — the entry previously abbreviated it with an ellipsis and
lost the actual instruction. The ask is **not** "build a picker that looks like that one": it
is **reuse the components that already exist**, naming two of them (writing the code, and the
quick editor). That is a different and cheaper job, and it matters for how E19 is approached.

E19 and E20 are the same job: one shared variable-selection component, reused everywhere,
matching the multi-select-with-checkmarks that already exists.

**Note the app-wide rule this already has behind it:** UX rule 11 in CLAUDE.md — predictor
selectors use `selectizeInput(multiple = TRUE)`, never `checkboxGroupInput`. So the target
component is already specified; E19/E20 are about making every screen actually use it.

### E21. Move "Select Diagnostics to View:"
> "change the position of this: Select Diagnostics to View:"

### E22. Separate linear regression from the other regression types
> "separate linear regression from the other types of regression in there."

The screen currently mixes plain `lm` with glmnet/poisson paths.

---

## F. Tables, reports, chrome

### F23. Table view is unreadable — FIXED 2026-07-30
> "the scroller for the table view is at the bottom and the header is not sticky. can put
> the scroller up for left to right to see the other columns or make the header sticky?
> also, reduce the size of the table, columns are too big and text size is big too."

Sticky header, a scrollbar you can actually grab, and tighter type:

| | before | after |
|---|---|---|
| scroll head position | `relative` | `sticky` |
| header font | 14px | 11.5px |
| cell font | — | 12px |
| cell padding | — | 4px 8px |

The viewer also gets `scrollY = "58vh"`, so the header stays put while the body scrolls rather
than the whole page moving, and the horizontal scrollbar is 12px with a visible thumb instead of
a hairline at the very bottom of a long table. A long text cell is clipped with an ellipsis at
260px so one value cannot stretch a column across the screen.

**`!important` was required, for the same reason as the date picker (A4):** DataTables ships its
stylesheet as an htmlwidget *dependency*, injected when a table first renders — after the head
styles — and it sets both the header font size and `position:relative` on the scroll head.
Source order cannot win. Measured before and after to confirm each override actually landed.

### F24. Replace the placeholder text with the tour
> "I dont understand this text: Pick a tool above. Its settings load here; spatial ops add
> a layer, models drop a result (Step 4). remove it and replace it with the tour guide
> button. but of course it will removed when the tool box gets loaded. and make sure the
> tour works. show at least 8 parts of the screens in the tour."

Remove the developer-speak placeholder, put the tour button there instead, hide it once a
tool loads, and **extend the tour to at least 8 steps**.

**State checked 2026-08-04:** the tour **engine is already built** (`#ea-tour` spotlight, tip
and dots in `ui.R:1623-1638`; `start`/`next`/`stop` at `ui.R:2873-2893`) but carries **only
2 steps** — `[data-tour=menu]` and `[data-tour=copilot]` — and only those two anchors are
placed in the markup. So "extend to 8" is content plus one `data-tour` attribute per target,
not a build.

**Same work as round-3 item 17** (its tour requirement is identical). Do them together and
tick both off; see item 17 for the full verified state of the docs/tour surface.

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

## G. Reported 2026-07-29 — testing the pushed algorithm framework

### G27. An algorithm must not pick its input layer for you — FIXED 2026-07-29
> "ITD now takes a CHM raster from the project: there should be an option to select the
> raster data not automatically forced there."

Correct, and it was worse than cosmetic. `selectInput` **auto-selects its first option**, so
ITD opened already pointing at whatever raster happened to be first in the pool. Press Run
without looking and you are detecting treetops on a DTM, and it will happily produce points.

Every algorithm input now has an empty `"Choose a layer..."` first option and starts
unselected; `isTruthy("")` is `FALSE`, so the existing guard in the Run handler refuses with
"Choose a … first." Multi-layer inputs get a `placeholder` instead. Applies to all 33 tools,
not just ITD.

### G28. Curvature appears to run forever — PARTLY DIAGNOSED 2026-07-29
> "the curvature just keeps going on and on loading running in a loop in the terminal."

**What I could rule out by measuring.** The maths is not the problem and there is no reactive
loop I can find:

| test | result |
|---|---|
| in memory, 4 M cells | 2.37 s |
| disk-backed, 1.44 M cells, with genuinely flat ground | 1.17 s |
| non-finite output (Inf / NaN poisoning the map) | **none** — 0 Inf, 0 NaN |
| map display path (downsample + reproject to WGS84) | 0.38 s |

So on the sizes I can generate it finishes quickly and cleanly. **What I have not reproduced
is the actual symptom**, which means the cause is still open. Most likely candidates, in order:
the real DEM is far larger than anything tested (5 focal passes plus ~8 full-raster
temporaries scale linearly, so 40 M cells is tens of seconds, not forever); or terra's own
progress output redrawing looks like a loop in the terminal; or something in the map rebuild
re-triggers on the new layer.

**Needed to close it:** the DEM's dimensions (`terra::nrow/ncol`) and what the terminal is
actually repeating. Without that I would be guessing at a fix.

**One thing tried and rejected — and a correction.** Collapsing the formula into a single
block-wise `terra::lapp()` pass looks like the obvious fix, since it avoids ~8 full-raster
temporaries. On a first single run it appeared clearly slower (2.22 s vs 1.17 s), and I said
so. Re-measured with 3 reps that was **noise**: median 2.76 s arithmetic vs 3.06 s lapp at
1.4 M cells, and 9.35 s vs 8.74 s at 6.2 M cells — each wins once, ranges overlapping. So the
combination step is not the bottleneck at all; the five `focal()` passes are. Kept as
arithmetic only because it reads closer to the formula.

**Useful scale figure that came out of it:** ~9 s at 6.2 M cells, so a 50 M-cell DEM is over a
minute of real work. That makes "the DEM is simply large" the leading explanation for the
report, and makes **G29 the actual fix** — the user needs to see progress and be able to stop,
not to have curvature made 10% faster.

### G29. No way to stop a heavy process from inside the app — BUILT 2026-07-30
> "i noticed that there are no real way to stop a heavy process in the app wihtout canceling
> it in the terminal-basically using ctrl c."

Real and structural, not specific to curvature. **Shiny is single-threaded**: while
`spec$run()` is executing, the session cannot process a click, so a Cancel button rendered
next to the progress bar could never be reached. `withProgress` only *reports*; it does not
yield. This affects every long operation in the app — model fits and LAS reads too, not just
algorithms.

**Constraints established, not assumed:**

- A `terra` SpatRaster is a **C++ pointer**; it cannot cross a process boundary. So the
  obvious `future`/`ExtendedTask` approach cannot simply be handed the layer.
- `sf` objects and `LAS` are ordinary R objects and *can* be serialised, though a large point
  cloud is expensive to copy.
- The whitebox algorithms already go through files (`writeRaster` → tool → `rast`), so they
  are trivially portable to another process.
- The app currently has **no** async infrastructure at all — no `promises`, `future`, `callr`
  or `ExtendedTask` anywhere.

**Design to build (not started).** Run each algorithm in a background R process with
`callr::r_bg()`, which is killable, and pass **paths, not objects**:

1. For each raster input use `terra::sources()` when the layer is file-backed, else write it
   to a temp `.tif` first. Vector inputs serialise directly; LAS passes its path.
2. Poll the process with `invalidateLater()` while it runs, so the session stays responsive
   and a **Stop** button in the tool panel is actually clickable.
3. On completion the worker returns an output path; the main process does
   `terra::rast(path)` and puts it in the pool exactly as now.
4. On Stop, `p$kill()` and delete the temp output.

The `run(inp, p)` contract in `algorithms.R` stays as it is — the worker calls it. That is the
payoff of having made the operations data: cancellation becomes one change in `mod_algo.R`
rather than 33 changes.

**Built as `compute_worker.R`.** Measurements that shaped it:

| approach | cost |
|---|---|
| fresh `callr::r_bg()` per run | **13–16 s** startup before any work — unusable |
| persistent `callr::r_session` | ~1 s spawn + ~14 s package preload **once**, then 0.6–1.6 s per run |
| `r_session$interrupt()` on a running terra call | **does not work** — poll timed out at 4 s, session stuck busy, next call errored |
| `r_session$kill()` | works: 0.33 s, no partial output file left behind |

So: one persistent preloaded session, `kill()` to cancel, respawn afterwards. The respawn
re-pays the ~14 s preload, which is the right place for that cost since it only happens when
the user actually cancels.

**Gated, not universal.** Only runs whose raster inputs exceed
`getOption("ea.worker_min_cells", 2e6)` go to the worker. Small ones stay in-process because
they finish before a Stop button could be reached, and routing them out would add ~1.6 s each
(plus ~14 s on the first) for nothing. **LAS inputs deliberately stay in-process**: staging a
point cloud means serialising it, which can cost more than the computation, and its file path
cannot be substituted because a cloud in the pool may have been clipped or height-normalised —
the same trap as a raster subset reporting its parent's path.

**A trap worth knowing.** A raster is never handed over by its own `terra::sources()` path.
Verified: `d[[2]]`, a single-band slice, reports the path of the 3-band file it came from, so
the worker would silently read 3 bands instead of 1. Inputs are always written out first.

**Bug found and fixed during UI testing.** The status line rendered its elapsed counter once
and then froze — it read the worker's state from a plain environment, which is not reactive, so
nothing invalidated it. On screen it showed "14s" while the run was 38 s in, which reads
exactly like the app having hung: the opposite of the point. A `tick` reactiveVal bumped on
each poll drives it now.

Verified in the browser against a real 6.25 M-cell DEM: the elapsed counter advances (5s → 12s
→ 21s), the status names what it is doing ("Preparing the background session (first heavy run
only)" then "Running on 6.2M cells in the background — Stop is safe"), the counter is
**server-rendered while the computation runs**, which is itself the proof the session is no
longer blocked. Stop mid-run clears the status, restores the Run button and adds **no** partial
layer; the next heavy run re-warms and completes, adding `ProfCurv`. A 0.16 M-cell input and a
LAS input both stay in-process and never start the worker.

---

## Suggested order

0. **G29** (no way to stop a heavy process) — structural, affects everything, and G28 may
   turn out to be a symptom of having no way to see or stop a long run.
1. **The likely regressions** — B5, D17, D18, F26. My changes, so mine to check first.
2. **D15** (active dataset not switching) — a core interaction, and other things depend on it.
3. **The colour sweep** — A1, A2 together, as in round 1.
4. **F23** (table readability) and **B8** (table editing) — same surface.
5. **E19 + E20** — one shared variable picker, then E21, E22.
6. **The console group** — C11, C13, C12, C10, then C9 once its rule is decided.
7. **Decisions needed before building:** A3, B6, C9, C14, plus round-1 items 5 and 6.

---

## Round 3 — User Feedback (2026-07-30)

Reported by user for immediate implementation and testing ("we build one and I will test").

### 1. Dedicated "Remove Rows" & "Remove Columns" Tools + Table Cell/Row Deletion
> "delete rows from the data. also, maybe also using the table to delete rows and columns. maybe a new tool called remove rows, another called remove columns."
- **Diagnosis & Plan:**
  - Add explicit "Remove Rows" and "Remove Columns" tools under Data Processing tools (`mod_data.R`).
  - Allow row filtering by condition/indices and column removal via selectize tag pickers.
  - Integrate table-based row/column removal directly from the active Data View table.

### 2. Light Mode Visibility Fix for Data & Exploration Viz Options
> "the options in the show in data & exploration viz is bad in light mode. the text is white, same as the background so cant see the options."
- **Diagnosis & Plan:**
  - CSS bug where select dropdown options in Data & Exploration visualization use white text on white/light backgrounds in light theme (`data-ea-theme="light"`).
  - Fix dropdown option text color styling so it adheres to theme CSS variables across light and dark modes.

### 3. Load Points from XY Coordinates & CRS Configuration (QGIS / GeoLibre Data Source Manager)
> "loading data to the map via x and y coordinates. a scenario: I i am working with a file that I am also modeling. so I load the data, I should be able to import the data by selecting which is x and which is y coodinates. important part is setitng the CRS cus some CRS can be off. we need the proper setitngs for this so that the points will show up on the map properly. take a look at qgis data source manager. same is true for geolibre"
- **Diagnosis & Plan:**
  - Add an "XY to Spatial Layer" (Point Data Import) tool under Add Data / Spatial Processing tools.
  - Allows selecting a loaded tabular dataset, picking the X (Longitude/Easting) and Y (Latitude/Northing) columns, specifying the source Coordinate Reference System (CRS) with EPSG lookup (e.g. WGS84 EPSG:4326, ETRS89 / TM35FIN EPSG:3067), and creating a spatial `sf` vector object in `vector_pool` so points display accurately on the Leaflet Map canvas.

### 4. Floated Tool Settings Panel Sync Bug
> "when I click, for eg, keep columns (we have similar search names by the way), the setitngs work fine in the tool side bar, but it does work when floated."
- **Diagnosis & Plan:**
  - Tool controls (e.g. "Keep Columns") function properly in the docked right sidebar panel, but break/desync when the tool settings panel is popped out / floated into a floating window.
  - Inspect input namespace and reactive binding in floated pop-out containers to ensure seamless bidirectional state sync.

### 5. Scoped "Reset to Raw Data" (Active Dataset Only)
> "reset to raw data should only be applied to the selected dataset and not all data (maybe an option to reset all data in the project or loaded and turn on. cus we do turn on and off the data selected)."
- **Diagnosis & Plan:**
  - "Reset to Raw Data" currently resets all loaded datasets globally.
  - Scope the default reset action to **only** the active dataset (`active_dataset()`), with an optional toggle/modal option to "Reset All Datasets in Project".


### 7. Data & Exploration Export (CSV/Excel) & Save Copy to Project — FIXED 2026-07-31
> "the export function should be able to export the data... export format should be excel or csv. the button next to the download 'Save Copy to project' sends a copy to the project."
- **Problem 1 (Downloading):** The old export handler used WebSocket string concatenation (`sendCustomMessage("ea-download")`), which corrupts binary files and failed on multi-line text. Downloading lacked native Excel support.
- **Fix 1 (Downloading Works):** Replaced with native `downloadHandler` supplying **CSV (`.csv`)** and **Excel (`.xlsx`)** via `writexl::write_xlsx()`. Verified working.
- **Problem 2 (Save Copy Error):** Clicking "Save Copy to Project" raised `Warning: Error in active_ds: could not find function "active_ds"` because `dataServer` in `mod_data.R` received `active_dataset` (a reactive) instead of the `active_ds` `reactiveVal` from `server.R`.
- **Fix 2 (Save Copy Fixed):** Passed `active_ds = active_ds` from `server.R` to `dataServer` and safely guarded the `active_ds(new_name)` invocation inside `mod_data.R`.

### 8. Session Resiliency & Error Recovery (Avoid Forced Terminal Restart)
> "when something does not work, the app breaks and kinda forces the user to restart from the terminal by killing everything. only document this part in backlog."
- **Diagnosis & Plan:**
  - Unhandled exceptions inside Shiny observers halt reactive execution or hang the session, forcing users to kill the R process in the terminal and restart.
  - **Plan:** Wrap observer handlers in structured `tryCatch` error handlers that log the error trace silently and display a user-friendly notification (`showNotification(err, type = "error")`), preserving session state so users never need to restart the terminal on an error.

### 9. Light Mode Selectize Dropdown Text Visibility Bug ("Show" Picker in Data & Exploration) — FIXED 2026-07-31
> "in light screen mode, 'show' on the data and exploration page gives ptions to see dataset overview and more by selecting. in light mode we cannot see the options because the text color is light. search and identify it. dont fix yet. document too"
- **Location & Component:**
  - UI Header: `helpers.R` (lines 605–615, `ea_view_header()`) renders `selectizeInput(ns("view_pick"), ...)` inside `mod_data.R` (line 175).
  - Stylesheet: `ui.R` (lines 394–397 and 1425–1435) contains global `.selectize-input` and `.selectize-dropdown` rules.
- **Diagnosis / Root Cause:**
  - In Light Theme (`html[data-ea-theme="light"]`), `var(--panel)` evaluates to pure white (`#FFFFFF`), making `.selectize-dropdown` white.
  - However, `.selectize-dropdown .option`, `.selectize-dropdown-content`, and `.selectize-input .item` lacked explicit `color: var(--ink) !important` rules.
  - Selectize JS's default CSS / bslib's base theme compilation retained a light/white text color (`#ffffff` / `#E8EDE4`) on option items, resulting in invisible white text on a white dropdown background in light mode.
- **Fix Applied:**
  - Added explicit CSS rules in `ui.R` forcing `.selectize-dropdown .option`, `.selectize-dropdown-content`, and `.selectize-input .item` to dynamically bind to `color: var(--ink) !important` and `background: var(--panel) !important`, with `:hover` and `.active` using `background: var(--sunk) !important; color: var(--ink) !important`. Tested & verified.

### 10. Dynamic GDAL / PROJ Authority CRS Database Query & Search Functionality — FIXED 2026-07-31
> "the coordinates in the software right now does not really source from gdal or so? similar to how we get rpackages from the source, I want the same for the crs search in the app. and I wan that search sunction too."
- **Location & Implementation:**
  - `algorithms.R` (lines 50–110, `ea_search_crs()`): Queries GDAL/PROJ's official `proj.db` database (`sf::system.file("proj", package="sf")`/`crs_view`) containing 7,000+ official EPSG Coordinate Reference Systems.
  - Spatial Modules (`mod_algo.R`, `mod_raster.R`, `mod_lidar.R`): Updated target CRS selectors to use `selectizeInput` backed by `ea_search_crs()`, allowing users to type and search by EPSG numeric code (e.g. `3067`), country/region name (e.g. `Finland`, `Oregon`), or projection authority. Tested & verified.

### 11. Comprehensive Raster & Vector Layer Symbology Toolbox
> "building a symbology tool for the raster and vector layers. document the tools needed in symbology"
- **Diagnosis & Proposed Tool Specifications:**
  - **Vector Symbology Tools (`sf` Layers: Points, Lines, Polygons):**
    1. *Single Symbol (Uniform Styling):* Custom fill color, stroke color, line weight, point radius, and marker shape (circle, square, triangle).
    2. *Categorized / Unique Values (Qualitative Classification):* Color-code geometries by a categorical attribute field (e.g. land use, soil class, state) with curated color palettes (Viridis, ColorBrewer, HSL gradients).
    3. *Graduated / Choropleth (Quantitative Classification):* Bin numeric attributes into statistical classes:
       - Equal Interval
       - Quantiles (Quartiles / Deciles)
       - Natural Breaks (Jenks)
       - Standard Deviation
    4. *Proportional Symbols (Bubble Map):* Scale point radius continuously based on a numeric column (e.g. population, biomass).
    5. *Layer Opacity & Stroke Controls:* Sliders for fill transparency (0%–100%), stroke weight, and stroke opacity.
    6. *Dynamic Map Legend:* Auto-generate Leaflet map legend keys with editable class labels and decimal formatting.

  - **Raster Symbology Tools (`terra` Layers: Continuous & Discrete):**
    1. *Singleband Pseudocolor (Continuous Elevation / NDVI / Climate):*
       - Color Ramps: Viridis, Magma, Plasma, Inferno, YlOrRd, Spectral, RdYlBu, Greys, Terrain, Rainbow.
       - Contrast Stretch Methods: Min/Max clipping, Percentile Stretch (2%–98%), Standard Deviation stretch (1.5σ / 2σ).
    2. *RGB / Multi-Band Composite (Satellite Imagery):*
       - Band assignment pickers: Red Channel, Green Channel, Blue Channel (e.g. Sentinel-2 / Landsat True Color R=4,G=3,B=2; False Color NIR R=8,G=4,B=3).
       - Per-band histogram contrast enhancement.
    3. *Paletted / Discrete Raster Symbology (Land Cover / Classifications):* Assign distinct colors and labels to discrete integer class values (e.g. 1 = Water, 2 = Forest, 3 = Urban, 4 = Agriculture).
    4. *Hillshade / 3D Relief Blend:* Blend DEM rasters with hillshade relief shading or slope aspect for 3D terrain representation.
    5. *NoData / NA Cell Masking:* Transparent color for NA/NoData cells and per-layer opacity sliders.

### 12. GeoLibre Open GIS & GeoAI Toolset Integration
> "there should be a way to call geolibre tools into the app... i think geolibre has tools from geoai and others, right?"
- **Diagnosis & Integration Architecture:**
  - **GeoLibre & OpenGeos Ecosystem Overview:** GeoLibre is an open-source, local-first, cloud-native GIS platform (part of the `opengeos` ecosystem created by Qiusheng Wu & collaborators) featuring spatial SQL, Whitebox integration, Python `leafmap` SDK (`geolibre`), and **GeoAI deep learning tools**.
  - **GeoLibre & GeoAI Toolsets to Call/Integrate into EasyAnalysis:**
    1. *GeoAI Deep Learning Suite (`geoai` / `samgeo` / YOLO):*
       - **Segment Anything Model (SAM / SamGeo):** AI-powered zero-shot image segmentation for automated extraction of building footprints, tree canopies, water bodies, and roads from satellite/aerial imagery via point or text prompts.
       - **YOLO & ONNX Object Detection:** Real-time bounding-box object detection (detecting vehicles, solar panels, buildings, ships) in imagery tiles.
       - **Hybrid YOLO+SAM Feature Extraction:** Pipeline combining YOLO fast detection with SAM boundary refinement, outputting georeferenced GeoJSON/Shapefile polygons.
    2. *DuckDB Spatial SQL Engine:* High-speed Spatial SQL processing (`ST_Buffer`, `ST_Intersects`, `ST_Contains`, `ST_Within`, `ST_Difference`, `ST_Union`, `ST_Area`, `ST_Centroid`, `ST_Length`) operating directly on Parquet, GeoPackage, and Shapefile layers via R's `duckdb` spatial extension.
    3. *Vector Processing Tools (Turf.js / GeoPandas Bridge):* Client & server tools for Convex Hull, Voronoi Diagram, Polygon Dissolve, Geometry Simplify, Spatial Join, Point-in-Polygon Overlay, and Feature Centroid Extraction.
    4. *Raster Processing & Spectral Tools:* Raster Reprojection, Resampling, Extent Clipping, Raster Calculator (Band Math: NDVI, NDWI, NBR), Hillshade, Slope, and Zonal Statistics.
    5. *Python `geolibre` SDK & `reticulate` Sidecar Bridge:* Call GeoLibre's Python package (`geolibre`), `samgeo`, and FastAPI sidecar via R `reticulate` or CLI subprocesses to execute GeoLibre & GeoAI automated processing workflows.
    6. *Embedded Interactive Map Panel:* Add an embedded GeoLibre web canvas viewer (`iframe` or web component window) into EasyAnalysis's workspace view for interactive cloud GIS projects.

### 13. WhiteboxTools (`whitebox` R Package) 700+ Advanced Spatial Processing Suite
> "do the sme for whitebox tools"
- **Diagnosis & Integration Architecture:**
  - **WhiteboxTools Overview:** WhiteboxTools (developed by Prof. John Lindsay) is a Rust-based, high-performance geospatial analysis engine with over 700 algorithms spanning hydrology, terrain analysis, LiDAR processing, and remote sensing. The official `whitebox` R package provides direct R function wrappers (`whitebox::wbt_*`).
  - **Integration Architecture for EasyAnalysis:**
    1. *Backend Installation:* Add automatic package loading (`library(whitebox)`) and auto-binary installation via `whitebox::install_whitebox()` in `global.R` / system setup.
    2. *Algorithm Catalog Expansion (`algorithms.R`):* Wrap key `wbt_*` tools into EasyAnalysis algorithm definitions:
       - **Terrain & Surface Analysis:** Slope (`wbt_slope`), Aspect (`wbt_aspect`), Curvature (`wbt_profile_curvature`), Hillshade (`wbt_hillshade`), Topographic Position Index (`wbt_tpi`).
       - **Hydrological Modeling:** D8 Flow Accumulation (`wbt_d8_flow_accumulation`), Watershed Delineation (`wbt_watershed`), Topographic Wetness Index (`wbt_wetness_index`), Stream Network Extraction (`wbt_extract_streams`).
       - **LiDAR & DEM Processing:** LiDAR Ground Filter (`wbt_lidar_ground_point_filter`), DEM Generation (`wbt_lidar_digital_elevation_model`), Canopy Height Model (`wbt_lidar_to_chm`).
    3. *Seamless Layer Interop:* `whitebox` outputs GeoTIFF and Shapefile files on disk, which are automatically read into `raster_pool` and `vector_pool` for instant Leaflet map display and stats calculation.

### 14. Installation Failure Diagnosis & Fix (`lidR` Missing Binary on R 4.5.1) — FIXED 2026-07-31
> "deps: binary install warning: package 'lidR' is not available as a binary package for this version of R... deps: ERROR — missing CORE packages: lidR"
- **Location & Component:** `launcher/deps.R` (lines 19–21, repository configuration) & `install.ps1`.
- **Root Cause Diagnosis:**
  - The user attempted installation using R version `R-4.5.1` (`C:\Users\khanish\AppData\Local\Programs\R\R-4.5.1`).
  - Primary CRAN (`cloud.r-project.org`) periodically lacks pre-compiled Windows binary packages (`.zip`) for development/patch builds of R 4.5.x.
  - When `type = "binary"` failed, `launcher/deps.R` attempted fallback source compilation (`type = "source"`), which failed because standard user environments lack the C++ Rtools compiler toolchain.
- **Fix Applied / Documented:**
  - Added `lidar = "https://r-lidar.r-universe.dev"` to `options(repos = ...)` in `launcher/deps.R`. R-Universe maintains pre-compiled Windows binaries for `lidR` across all R versions (including R 4.5.x).
  - Now `install.ps1` automatically downloads the pre-built `lidR` binary from R-Universe whenever primary CRAN binary builds are missing, preventing core package installation failures.

### 15. Peer-Host Live Collaboration Engine (Decentralized Local-Host Collaboration)
> "live collaboration. i am thinking instead of a cloud for collaboaration, can we use one of the users computer as the host or something?"
- **Diagnosis & Architecture Specifications:**
  - **Decentralized Host Concept:** Instead of requiring third-party cloud infrastructure or external SaaS servers, a single user's computer acts as the **Host Server / Session Leader** for real-time multiplayer spatial analysis.
  - **Proposed Implementation Architecture:**
    1. *Host Session Initialization:* When a user clicks "Start Host Session", EasyAnalysis binds its local server instance to network interfaces (`host = "0.0.0.0"`) and generates:
       - **Local LAN Link:** For team members on the same Wi-Fi / local network (`http://192.168.x.x:7788`).
       - **Zero-Config Remote Tunnel Link:** A secure encrypted URL (via Cloudflare Tunnel, Ngrok, or Tailscale sidecar) for remote collaborators outside the local network.
    2. *Real-Time State & Map Canvas Synchronization:*
       - Utilizes WebSocket event broadcasting / CRDT state sync to mirror active map layer selections, Leaflet pan/zoom extents, raster color ramps, and spatial algorithm parameters live across all connected guest browsers.
       - Heavy computations (e.g. LiDAR filtering, Whitebox terrain processing, raster classification) run on the Host machine's hardware, streaming updated results instantly to guest clients.
    3. *Access Control & Security:*
       - **Data Privacy:** Raw spatial files and project assets remain securely stored on the Host computer's local storage.
       - **Permission Modes:** Host user can toggle guest roles (**Spectator / Read-Only** vs **Co-Editor / Contributor**) and disconnect guests at any time.

### 16. Custom Domain Migration (`easyanalysis.dev`) & Name.com / Vercel DNS Setup
> "we have bought the domain: easyanalysis.dev. we need to change the vercel url to it and point name.com to vercel."
- **Diagnosis & DNS Migration Steps:**
  - **Overview:** Migration from default Vercel staging URL (`easyanalysis.vercel.app`) to custom branded domain `easyanalysis.dev` registered on Name.com.
  - **Required Setup & DNS Configuration:**
    1. *Name.com DNS Records:*
       - **A Record:** Host `@` -> Points to Vercel IPv4 `76.76.21.21`.
       - **CNAME Record:** Host `www` -> Points to `cname.vercel-dns.com`.
       - *(Alternative Nameserver Delegation):* Update Name.com custom nameservers to `ns1.vercel-dns.com` and `ns2.vercel-dns.com`.
    2. *Vercel Custom Domain Assignment:*
       - Open Vercel Dashboard -> EasyAnalysis Project Settings -> **Domains**.
       - Add `easyanalysis.dev` and `www.easyanalysis.dev` with automatic SSL certificate provisioning.
       - **CRITICAL:** Set `easyanalysis.dev` as the **Primary Domain** (no redirect). Setting `www` as primary causes Vercel to issue HTTP `308 Permanent Redirect` for `easyanalysis.dev`, which breaks Windows PowerShell 5.1 (`iwr`).
    3. *Repository Installer URL Updates:*
       - Update one-line terminal installer commands across `README.md`, `DEPLOY.md`, `install.ps1`, and `install.sh`:
         - **Windows (PowerShell):** `iwr -useb https://easyanalysis.dev/install.ps1 | iex`
         - **macOS / Linux (Bash):** `curl -fsSL https://easyanalysis.dev/install.sh | bash`

- **Terminal Installer (308 Permanent Redirect & 404 Resolution):**
  - **Symptom:** Running `iwr -useb https://easyanalysis.dev/install.ps1 | iex` in PowerShell returned `(308) Permanent Redirect` error.
  - **Root Cause Analysis:**
    1. *HTTP 308 Redirect in Windows PowerShell 5.1:* Vercel issued HTTP 308 redirects from `easyanalysis.dev` to `www.easyanalysis.dev`. Standard Windows PowerShell 5.1 `Invoke-WebRequest` uses .NET Framework's `HttpWebRequest` which automatically handles 301, 302, 303, and 307, but throws `WebException` on HTTP 308 (RFC 7538).
    2. *Missing Static Assets on Landing Project:* The landing page project (`landing/`) lacked static copies of `install.ps1` and `install.sh`, returning `404 Not Found` when following installer paths directly.
  - **Fix Applied & Verified:**
    1. *Static Assets:* Added `landing/install.ps1` and `landing/install.sh` to the landing deployment folder.
    2. *MIME Headers:* Updated `landing/vercel.json` with static headers (`text/plain; charset=utf-8` for `.ps1` and `text/x-shellscript` for `.sh`).
    3. *Domain Configuration:* Documented requirement to set `easyanalysis.dev` as Primary Domain on Vercel so requests return `200 OK` directly without triggering a 308 redirect.
    4. *Pushed to GitHub:* Commit `4949579` pushed to `main`.


### 17. Detailed User Documentation & Interactive Tours
> "we need a very detailed, clear and practical and intuitive documentation for users. so far, users try the app and have no idea what it does. so the goal is to have a proper documentation in the landing page and a button what points to it on the first page the app loads and this button goes on the projects and analysis area pages too. detailed tour with more information. tour 1 on the first page, tour 2 on the project page, tour 3 on the analysis area page both for map view and for data view."
- **Diagnosis & Requirements:**
  - Users are struggling to understand the app's capabilities upon first use.
  - **Comprehensive Documentation:** Create detailed, clear, practical, and intuitive documentation explaining what the app does and how to use it.
  - **Documentation Access:** Add a prominent button linking to the documentation on:
    - The landing page (first page the app loads).
    - The projects page.
    - The analysis area pages.
  - **Interactive Onboarding Tours:** Implement guided tours for different sections of the app:
    - **Tour 1:** On the first page/landing page.
    - **Tour 2:** On the project page.
    - **Tour 3:** On the analysis area page, covering both the **map view** and the **data view**.

#### Verified state 2026-08-04 — PARTLY BUILT (more done than this entry said)

Checked against the repo after reviewing the last 5 pushes. Commit `19bbbd3` (2026-08-01)
rewrote the landing site substantially — `index.html` +1079 lines, plus two new pages — so
this item was **further along than the entry recorded**:

| piece | state |
|---|---|
| Landing documentation page | **BUILT** — `landing/documentation.html`, 403 lines |
| "How to use" page | **BUILT** — `landing/how-to-use.html`, 297 lines |
| Linked from the landing nav | **YES** — both are `href`s in `index.html` |
| Tour engine in the app | **BUILT** — `#ea-tour` spotlight + tip + dots, `ui.R:1623-1638`, `start/next/stop` at `ui.R:2873-2893` |
| Tour content | ~~2 steps~~ → **was 6, now 9** — DONE 2026-08-04. **Correction:** the "2 steps" above was WRONG; that count came from grepping only `[data-tour=…]` anchors and missed four steps targeting CSS classes (`.ea-wsx-left`, `.ea-wsx-tabs`, `.ea-wsx-right`, `.ea-wsx-dock`). It was 6. Added 3 (tool search, Undo/Reset, Docs) → **9**, clearing the ≥8 requirement. |
| Button in the app pointing at the docs | ~~NOT BUILT~~ → **DONE 2026-08-04.** A "Docs" link added to `.topbar-right` in `ui.R`, pointing at `easyanalysis.dev/documentation.html`, `target="_blank"` so a running project is never navigated away from. It carries no `tb-ws`/`tb-coanalyst` class, so unlike Undo/Reset it shows on the **projects screen and the analysis area** — which is what the item asked for. |
| Tour 2 (projects page) / Tour 3 (map + data view) | **NOT BUILT** — one tour exists, not three |

**So what actually remains is smaller and much more specific than "write documentation":**

1. **Add the 6+ missing tour steps and their `data-tour` anchors.** The engine already
   works; this is content plus one attribute per target. Same job as **F24**, which asks for
   ≥8 steps — the two entries are the same work and should be done once.
2. **Link the app to the docs.** This is the explicit ask ("a button which points to it on
   the first page the app loads and this button goes on the projects and analysis area pages
   too") and it is the one piece with nothing in place at all.
3. **Split into Tour 2 / Tour 3** for the projects screen and the analysis area (map view and
   data view), or decide one context-aware tour is enough.

---

## Round 4 — reported 2026-08-04

Recorded before any work started. Reporter's wording first, then what I found in the code,
then what still has to be decided. **Nothing here is done yet.** Numbering continues from
Round 3, so item references stay unique across the file.

Items 20 and 21 are **diagnosed to a specific line** — the cause is confirmed in the code,
not inferred from the symptom. The rest still need a decision before they can be built.

---

### 18. Dropdown options are white-on-white in light mode — and a wider colour sweep
> "The options in the drop downs are white in light mode feels inconsistent (more screen
> background, results, options color sweep."

**This is NOT a repeat of Round 3 items 2 and 9, and it is important not to close it as one.**
Those two fixed **selectize** dropdowns — [ui.R:1428-1434](ui.R#L1428-L1434) forces
`.selectize-dropdown .option`, `.selectize-dropdown-content` and `.selectize-input .item` to
`var(--ink)`. That work is real and still in place.

**What is still broken is the NATIVE `<select>`, which selectize never touches.** The app
styles the closed control only:

| selector | where | what it sets |
|---|---|---|
| `.form-control, .form-select, textarea` | [ui.R:393-396](ui.R#L393-L396) | background + colour |
| `.form-control, .form-select, .selectize-input, textarea` | [ui.R:1425-1427](ui.R#L1425-L1427) | same, with `!important` |

There is **no rule anywhere for `option`** — confirmed by searching `ui.R` for `option`:
the only hits are the selectize ones above. So the `<option>` elements inherit
`color: var(--ink)` from the `<select>`, while the popup list itself is painted by the
browser/OS, not by the page. In light mode that lands light text on a light popup.

**`color-scheme` is never declared** — confirmed absent from `ui.R`, `theme.R` and
`mod_workspace.R`. That is the actual lever for native control popups: the browser paints
them from the declared scheme, so `html[data-ea-theme=light] { color-scheme: light }` (and
`dark` for the dark sets) is likely to fix this properly where an `option { color: … }` rule
can only half-work, since Windows Chrome honours `option` colours but Firefox and Safari
largely do not.

**The wider ask is a third colour sweep** ("screen background, results, options"), the same
family as round-1 items 3/8/10 and round-2 A1-A4. **Decide before starting:** this one is
partly a *taste* call, unlike its predecessors which were all measurable defects (a literal
dark rgb() from the compiled bootstrap). Round-2 A3 already flagged "body text colour
app-wide, and card surfaces outside these tiles" as **still open and deliberately untouched
because they are taste calls**. So this item should be split:

- **defect half** — native `<select>` popups, plus anything else measurably unreadable.
  Verify by measuring contrast, per gotcha 24 (a non-compositing pane lies).
- **taste half** — screen background and results-surface colours. Needs the reporter to say
  what "inconsistent" means concretely, or it will be repainted to a guess.

#### Defect half addressed 2026-08-04 — `color-scheme`, plus `option` colours

**`color-scheme` is now declared per theme**, in `theme.R` beside the colours rather than as
a loose CSS rule, so a new colour set cannot be added without saying which kind it is. Each
palette gains a `scheme` key (`light` for **light** and **paperwhite**, `dark` for
**forest**, **midnight**, **ocean**, **plum**), and `ea_theme_css()` emits it as a real
`color-scheme` declaration — pulled out of the `--name: value` loop, or it would have become
a `--scheme` custom property that nothing reads.

`:root` declares `color-scheme: dark` too, which is **not** redundant: `ui.R` only sets
`data-ea-theme` when localStorage already holds one, so a **first-time visitor has no theme
attribute at all** while the default palette is dark. Without it the browser assumes light
and draws native popups and scrollbars light over the dark default — the same defect, on
first run.

**Complementary `option` rules** added in `ui.R` for `.form-select option` and
`select.form-control option`. These are deliberately *secondary*: Chromium on Windows honours
them, Firefox and Safari largely do not, which is exactly why `color-scheme` has to carry the
fix rather than these.

**Verified:** all 6 sets plus `:root` emit a correct `color-scheme`, colours survive the
change, braces balance, no `--scheme` variable leaks, and every palette declares a scheme
(so adding one without it fails the check). Confirmed in the **served page**: 7
`color-scheme:` declarations, both `light` and `dark` present, `.form-select option` present,
no stray variable.

**NOT verified — and this matters before it is called done.** I could not reproduce the
reporter's exact symptom. Working through it in the code, the *native `<select>`* path in
light mode should already have produced dark text on a light popup
(`.form-select` sets `color: var(--ink)`, which is near-black in the light set), so
**"the options are white in light mode" is not fully explained by the diagnosis above.**
`color-scheme` is a genuine, low-risk correctness fix regardless — it is the right way to
handle native popups and scrollbars — but it may not be the thing the reporter saw.

**To close this properly, needed from the reporter:** *which* dropdown (a screenshot, or the
screen and control name). Candidates not yet excluded: the app's own `.dropdown-menu` items,
a selectize instance the round-3 fix does not reach, or a native select whose theme variables
are not resolving. Guessing further without that risks repainting the wrong surface.

**Side effect to watch:** `color-scheme` also changes native **scrollbars** and other
OS-drawn controls. On the dark sets that is the intended correction, but it is a visible
app-wide change and should be eyeballed once.

#### Scope agreed 2026-08-04 — sweep EVERY mode, and sweep for hardcoded colour

> "i think we need to do a sweep in each mode. dark mode, sweep for the inconsistency. a good
> thing will be to sweep for hardcoded colors."

This settles the "taste half" question above: the sweep is **per mode**, not light-only, and
it is driven by **finding hardcoded colour** rather than by opinion. That makes it a
measurable job again, which is what the earlier entry said it needed.

**Two passes, and they find different things:**

1. **Static pass — hunt raw colour in the source.** `theme.R` states the rule outright:
   *"Nothing else in the app should contain a raw hex value. If you find one, it belongs in
   this palette."* So any `#rrggbb`, `rgb(`, or bare colour keyword outside `theme.R` is a
   candidate by definition, and this can be scripted and re-run — the same shape as
   `check_plot_views.R`, which already re-derives a fact from the parse tree and fails on
   drift. A hardcoded colour is invisible in whichever mode it happens to suit, which is
   exactly why rounds 1 and 2 kept rediscovering it (items 3, 8, 10, A1-A4).

   **Known legitimate exceptions that must NOT be "fixed"** — record them in the checker or
   it will keep flagging them:
   - `abline(col = "#2e7d32")` and other **base-graphics** colours (round-1 item 8): base
     plots render on their own white device regardless of app theme, so a themed colour there
     would be wrong.
   - `mod_rconsole.R` plots (round-1 item 13): in the console **your code is the source of
     truth**; the app repainting your `geom_point(colour = "red")` would be the app lying.
   - The Co-Pilot header gradient and similar deliberate brand fills.

2. **Runtime pass — measure each mode.** The static pass cannot catch the *other* cause,
   which has bitten this project repeatedly: **bslib compiles Bootstrap once from the default
   (dark) palette and bakes literal `rgb()` values into component rules** (gotcha 22). Those
   contain no variable to override, so they are invisible to a source grep and only show up
   by measuring a rendered page. That is how `.bg-light` (51 card headers), `.modal-footer`,
   `.input-group-text`, `.btn-light` and ~32 datepicker rules were each found.

   Now that there are **6 colour sets** (soon 7 with item 25), measure all of them, not just
   light — the reporter explicitly asked for dark too.

**Method note, or the measurement will lie:** see gotcha 24 — in a non-compositing browser
pane `requestAnimationFrame` does not fire, tiles read `opacity: 0`, and computed styles are
stale after `eaSetTheme()` unless a reflow is forced. Contrast has to be measured on a real
rendered page, per theme.

**Do this after item 25** so the new black & white set is swept in the same pass rather than
becoming the next thing that needs one.

#### REPRODUCED 2026-08-04 — two screenshots, both modes, on Mixed effects

At last, the concrete symptom the earlier entry could not reproduce. **Both are the same root
cause — a colour fixed for one mode — but they fail on opposite surfaces**, which is why one
sweep per mode is necessary and a light-only pass would have missed half.

**Light mode — result text is unreadable.**
> "I am in light mode, in mixed effects, the texts in the model summary and others are grey
> and the background is white. I cant read anything. this is true for many of the views for
> other analyses."

The `verbatimTextOutput` / `<pre>` blocks (Model Summary, Performance Metrics, Cross-Validation)
render very light grey on white. Card headers and titles are fine, so this is **the `pre`
block specifically**, not the card. Reported as affecting **many analysis views**, not just
LME — consistent with a shared rule rather than one screen's CSS.

**Dark mode — sidebar labels and a fixed light panel.**
> "when I change to dark mode, the quick builder and other hardcoded white texts are bad"

In the tools sidebar: "Quick Builder", "Grouping Variable:", "Random Slope (optional):" are
dark-on-dark and barely legible, while the **"Convergence Options" panel keeps a light cream
background** (`#fff8e1`-family) with its heading and checkbox label unreadable on it. That
panel is a hardcoded light surface that never follows the theme — the same class of bug as
`.bg-light` (round-1 item 3) and `.modal-footer` (A1/A2), just not yet swept.

**What this pins down for the sweep:**

1. `pre` / `verbatimTextOutput` colour is the **highest-value single fix** — it is where every
   model's actual numbers live, it is reported across many screens, and one rule should fix
   all of them.
2. Fixed **light** panels (`#fff8e1`, `#fce4ec`, and friends) must become theme tokens or a
   translucent tint. Round-1 item 10 already solved this shape once for the assumption rows —
   `color-mix(in srgb, var(--warn) 14%, transparent)` takes its lightness from whatever is
   behind it, so it works in every set. Reuse that, do not invent a second approach.
3. Sidebar **section labels and helper text** need checking in the dark sets specifically.

Both screenshots are on the **Mixed effects** screen, so start there and use it as the
reference while sweeping the rest.

#### FIXED 2026-08-04 — both reported symptoms, traced to two distinct causes

**1. Light mode / unreadable result text — one variable, app-wide.** Bootstrap colours
`<pre>` from **`--bs-emphasis-color-rgb`**, an `R,G,B` *triplet* — **not** from
`--bs-emphasis-color`, which is the one `ui.R` was overriding. bslib compiles the triplet once
from the default (dark) palette, so it stayed `232,237,228` on every theme: light text, which
on a light page is exactly the reported grey-on-white. Confirmed by compiling the real theme
and reading the rule:

```css
pre { color: RGB(var(--bs-emphasis-color-rgb, 0,0,0)); … }
```

It was never only `pre` — the same triplet colours **`code`, `.well`, `.navbar` and
`.link-body-emphasis`**, which is why the reporter saw it "for many of the views".

**Fixed in `theme.R`, derived rather than written out:** `.ea_rgb()` converts the set's own
`ink` with `grDevices::col2rgb()`, and both `ea_css_vars()` and `ea_theme_css()` emit
`--bs-emphasis-color-rgb`. It cannot drift from `ink` because it is computed from it. `pre` and
`.well` are also restated explicitly, because bootstrap derives their *background* from the
same triplet at 4% alpha — a barely-visible wash rather than a panel.

**2. Dark mode / fixed light panels — 12 sites across 6 modules.** Inline
`background-color: #f8f9fa` / `#fff8e1` / `#e9ecef` blocks: fixed **light** surfaces that keep
their colour on a dark theme while the app's light text runs across them. Replaced with three
reusable classes in `ui.R`:

| class | replaces | used by |
|---|---|---|
| `.ea-subpanel` | `#f8f9fa` sidebar blocks | lme (×2), logistic, classification, da (×2), recommend |
| `.ea-subpanel-warn` | `#fff8e1` Convergence Options | lme |
| `.formula-box` | inline `#e9ecef` (the class existed but was styled inline) | lme, logistic, classification, da |
| `.ea-row-warn` / `.ea-row-flat` | `#fff8e1` / `#fce4ec` table row flags | data, recommend |

The warn variants are **translucent tints** (`color-mix(… var(--warn) 14%, transparent)`), so
they take their lightness from whatever is behind them and work on every set — the approach
round-1 item 10 already proved, reused rather than reinvented.

**Deliberately NOT changed:** the two `strip.background = "#e9ecef"` values in `mod_da.R`
(lines 365, 381). Those are *inside a ggplot*, and `ea_style_gg()` (helpers.R:506-526) only
touches titles, labels and fixed-layer colours — it never re-themes the plot background. So
plots render on their own light canvas regardless of the app theme, exactly like base graphics
(round-1 item 8). A themed colour there would be wrong, not right. **Checked, not assumed.**

**Verified:** `:root` emits `232,237,228`, the light set `16,21,15` and paperwhite `26,23,18`,
each matching its palette's `ink`; all six new rules present in the served markup; and **no
fixed-light panel hex remains in any module** outside the two ggplot strips.

**Still open in this item:** the wider taste half (screen background, results-surface colours),
and a per-mode contrast measurement across all 6 sets — which wants a real browser, so it is
flagged for the reporter rather than claimed. Item 25's black & white set should land before
that pass.

---

### 25. A black & white theme
> "I think we need a black and white theme too."

**Straightforward** — the theme system was built for exactly this. A set is a list of colour
keys in `ea_palettes` (`theme.R`); `ea_theme_css()` emits it as
`html[data-ea-theme="<name>"]`, and the switcher picks it up from `label`. Nothing else in
the app changes. There are 6 sets today: forest (default), light, midnight, ocean, plum,
paperwhite.

**Decide which of the two this means** — the wording fits both, and they are different:

- **Monochrome / greyscale** — a set where the *brand* hue is neutral too, so the whole UI is
  black, white and greys with no green. This is the bigger change of the two: `--forest` and
  `--canopy` are used for emphasis, active states and semantic tints all over the app, so a
  neutral brand removes the app's main signal colour and buttons/active rows will need to
  distinguish themselves by weight or border instead of hue.
- **Maximum-contrast black-on-white** (a light counterpart to **midnight**, which is already
  true-black) — pure `#FFFFFF` paper with `#000000` ink, for projectors, printing and low
  vision. Smaller change, and arguably the more useful one since midnight has no light twin.

**Recommend the second**, named to pair with midnight, and it can reuse the light set's
structure with the contrast pushed to the ends.

**Two things it must get right, both already known:**

1. **`scheme = "light"`** (or `dark`) in the palette — added 2026-08-04 for item 18. Miss it
   and the native `<select>` popups and scrollbars go wrong for that set specifically. The
   verification script for item 18 already fails on a palette with no `scheme`, so this is
   caught rather than trusted.
2. **The semantic keys.** `warn` and `danger` must stay distinguishable. In a strict
   greyscale set they cannot be — which is a real argument for the high-contrast reading
   above, or for allowing those two keys to keep their hue as the only colour in the set.

**Also check** the `bar` key: the top menubar is dark green in every existing set, so a black
& white set is the first one where that would look out of place.

---

### 19. Save analyses to a project as Steps, with Checkpoints — FEATURE
> "To save analyses to Project. Can call it steps (basically remembers the steps that led to
> the save)."
>
> "Checkpoint: a part in the analyses where you can stop and save files, plots and others.
> Appears as a card in project flow where you can continue from directly. Saves everything
> including codes, scripts, and everything in that session."

**Two related things, and they should be built in this order — Steps first, Checkpoints on
top of Steps.** A checkpoint without a step history has nothing to name itself after.

**What exists today (checked, not assumed).** A project is `project.json` + `datasets.rds`
([project_store.R:10-11](project_store.R#L10-L11)). The metadata is
`{id, name, created, last_view, active_dataset, spatial[]}`
([project_store.R:149-156](project_store.R#L149-L156)) — it stores the *current state* and
nothing about how that state was reached. Searching `server.R`, `project_store.R` and
`mod_project.R` for a history/log/steps concept returns **nothing**. So this is greenfield,
not an extension.

**Steps — what has to be decided first.** A "step" is only useful if it is *replayable*, and
the app has two very different kinds of action:

- **Algorithm runs** are already data — `algorithms.R` specs are `id + inputs + params`, so a
  step is a small record and `mod_algo.R` is the single choke point that could write it. This
  part is genuinely cheap, and it is cheap *because* the operations were made data (the same
  payoff G29 got for cancellation).
- **Everything else is not.** Model fits, ETL commands in `mod_data.R`, and console scripts
  each have their own input sets with no shared shape.

**So: does a step record the whole app, or only what is replayable?** Recommend scoping v1 to
algorithm runs + ETL commands, both of which have a declared parameter list, and leaving model
fits for later — rather than a vague "remembers everything" that cannot actually replay.

**Checkpoints — the hard part is "saves everything".** Taken literally that includes rasters
and point clouds, and the project format deliberately stores spatial layers as **path
references, never copies**, precisely so a multi-GB `.laz` is not duplicated
(CLAUDE.md, Projects section). A checkpoint that copies everything would reintroduce exactly
what that rule avoids. **Decide:** does a checkpoint copy spatial layers, or reference them
like the project does and accept that an edited source invalidates it? Same question the
Round-1 item-1 cache had to answer, and it answered it with path + mtime + size.

Plots and scripts are cheap and can genuinely be saved in full. `mod_rconsole.R` already
tracks what a script produces (`.script_outputs`, [mod_rconsole.R:222](mod_rconsole.R#L222)),
so console history is the most tractable piece.

**UI:** "appears as a card in project flow where you can continue from directly" — the
Projects screen already renders project cards (`mod_projects.R`), so checkpoint cards should
reuse that idiom rather than invent a second one.

---

### 20. App fails to start on a fresh machine — `plotly` is not installed by the installer — FIXED 2026-08-04
> "Error running easyanalysis on a uni computer. It loaded but failed: … there is no package
> called 'plotly' … The fix to use it was to manually install plotly using
> install.packages("plotly") in Rstudio."

**Diagnosed to the line. Two separate bugs, and the second one is why a missing optional
package took the whole app down.**

**Bug 1 — `plotly` is in no dependency list.** `launcher/deps.R` declares `core`
([deps.R:25-32](launcher/deps.R#L25-L32)) and `extras`
([deps.R:36-40](launcher/deps.R#L36-L40)); **`plotly` appears in neither**. But
`mod_workspace.R` uses it. So the installer completes successfully, reports `deps: OK`, and
the app then dies at boot on any machine that does not happen to have plotly already. Every
fresh install is affected — the reporter's own machine only worked because plotly was already
in its library.

**Bug 2 — the guard is on the UI but not on the server.** The plotly output is guarded where
it is *displayed*:

```r
# mod_workspace.R:771-773
if (identical(input$cmode %||% "static", "interactive") &&
    requireNamespace("plotly", quietly = TRUE))
  plotly::plotlyOutput(ns("chart_i"), height = "100%")
else plotOutput(ns("chart"), height = "100%")
```

…and then unguarded where it is *bound*:

```r
# mod_workspace.R:1478
output$chart_i <- plotly::renderPlotly({ ... })
```

That line runs unconditionally as soon as `workspaceServer` is created, so `::` triggers
`loadNamespace("plotly")` and throws — which matches the reported trace exactly
(`workspaceServer` → `moduleServer` → `callModule` → `loadNamespace` → stop). The graceful
degradation the `requireNamespace()` guard was written to provide **never gets a chance to
happen**, because the failure is at server-construction time, not at render time.

**Bug 3 — the cascade, which is also why the error message was confusing.** The second
reported error, `object 'workspace_ctx' not found` at
`observeEvent(workspace_ctx$tool_open())`, is **not independent**. In `server.R` that
observer is registered at **line 1105** while `workspace_ctx` is assigned at **line 1109** —
a forward reference that normally resolves fine, because the event expression is not
evaluated until the first flush, by which time the assignment has run. When
`workspaceServer()` throws, the assignment never completes, so the name is never bound and
the observer fails on every flush forever. Fixing bug 1 or 2 makes this go away, **but the
ordering is fragile on its own** and worth swapping regardless.

**Fix, all three parts:**
1. Add `plotly` to `extras` in `launcher/deps.R` (extras, not core — the static `plotOutput`
   fallback already exists and is the default mode, so the screen degrades correctly once
   bug 2 is fixed).
2. Guard the server binding the same way the UI is guarded, so a missing optional package
   downgrades the chart instead of killing the workspace.
3. Move the `observeEvent` in `server.R` to after the `workspace_ctx` assignment.

**This is a strong argument for Round 3 item 8** (session resiliency): one absent optional
package should never be able to take down the entire analysis workspace.

**Worth auditing while in there:** whether any other `pkg::fn` call sits outside a
`requireNamespace()` guard for a package that is in `extras` rather than `core`. The same
shape would fail the same way.

#### Fixed 2026-08-04 — all three parts, plus the audit

1. `plotly` added to `extras` in [launcher/deps.R:39](launcher/deps.R#L39). Extras, not core:
   the static `plotOutput` fallback is the default mode, so the screen degrades correctly.
2. [mod_workspace.R:1478](mod_workspace.R#L1478) wrapped in `requireNamespace("plotly")`,
   matching the guard the UI already had.
3. The observer in `server.R` moved **after** the `workspace_ctx` assignment.

**The audit found nothing else.** Searching every `output$… <- pkg::render*` binding in the
repo returns 14 in the live app, and all the rest use `DT`, `leaflet`, `rhandsontable` or
`shiny` — **all four are `core`**, so they cannot produce this failure. `plotly` was the only
extras package sitting in an eager binding.

**Verified against a genuinely plotly-free library.** Shadowing `requireNamespace()` was
tried first and **rejected as unfaithful** — it does not affect how `::` resolves, so the
control case reported "no error" and proved nothing. The real test builds a shadow library of
346 directory junctions omitting only `plotly` (the real library is never modified) and runs
against that:

| check | result |
|---|---|
| `requireNamespace("plotly")` | `FALSE` — genuinely absent |
| CONTROL: old unguarded `plotly::renderPlotly` | **`there is no package called 'plotly'`** — the reported error, reproduced |
| `workspaceServer` constructs (`cmode = "interactive"`, i.e. plotly explicitly requested) | **TRUE** |
| `ui.R` + `server.R` source | **TRUE** |

So the control still crashes on the old shape while the guarded app boots — which is the
only thing that proves the fix rather than the environment.

---

### 21. Semi-supervised LFDA / LLDA, and Capped Norm Threshold — DA methods
> "Semi-supervised LFDA/LLDA"
>
> "**Capped Norm Threshold**"

**Current state, confirmed.** `mod_da.R` offers **7 methods, all fully supervised**
([mod_da.R:58-60](mod_da.R#L58-L60)): LDA, WLDA, QDA, RLDA, KDA, LLDA (`klaR::loclda`), MMC.
There is **no LFDA at all** — searching the repo for `lfda` returns only this backlog entry.
So two of the three asks are new methods, not modifications:

- **LFDA (Local Fisher Discriminant Analysis)** — not present. Distinct from the existing
  LLDA: LFDA is Sugiyama's local-Fisher criterion, whereas `loclda` is locally-weighted LDA.
  Naming them clearly matters or the two will be confused in the picker.
- **Semi-supervised variants** (SELF / SELF-LFDA) — use unlabelled rows alongside labelled
  ones. **This does not fit the current data contract:** every DA path assumes a complete
  labelled target column. Semi-supervised means rows with `NA` in the target are *training
  input*, not rows to drop. **Decide:** does the app treat target-`NA` rows as the unlabelled
  set, or does the user nominate them explicitly?
- **Capped Norm Threshold** — the reporter gave no context beyond the name. My reading is the
  capped-ℓ₂,₁-norm robust variant, where a threshold caps each sample's residual so outliers
  stop dominating the projection. **Needs confirmation before building** — it is a parameter
  on a specific formulation, and guessing which one wastes the work.

**Package check needed before any of this:** the `lfda` CRAN package covers LFDA/SELF, but
`deps.R` would need it added to `extras` and the screen path `requireNamespace()`-guarded —
**and item 20 above shows the guard has to be on the server binding, not just the UI.**

**Related, already recorded:** the Phase-4 note in CLAUDE.md flags the hidden rare-class
`min_n` guard in `mod_da.R` as undesirable hidden preprocessing that should be removed so
users manage class filtering themselves. Worth doing in the same pass, since semi-supervised
input makes an automatic row-dropping guard even more surprising.

---

### 22. Editing existing data
> "editing existing data."

**Recorded as reported, but this overlaps work already done and needs one clarification
before it can be built.** Three plausible readings, and they are very different jobs:

1. **Tabular cell editing** — already fixed in Round 2 B8 (the editable viewer was
   unreachable from the menu; the entry now opens it, edits persist, and reopening re-reads).
   If the reporter is still hitting a problem here it is a **new defect on top of that fix**
   and needs its own reproduction.
2. **Structural edits** — add/remove rows and columns. This is **Round 3 item 1**, still open.
3. **Editing spatial layer attributes or geometry** — QGIS-style edit mode on a vector layer.
   This is genuinely new; nothing in `mod_raster.R` or the vector path supports it.

**Recommend asking which one before starting**, rather than building the intersection.
Reading 3 is by far the largest and would not be discharged by finishing Round 3 item 1.

---

### 23. Show that something is running, everywhere — GLOBAL SIGNAL BUILT 2026-08-04
> "some way to show that something is running so that the user does not think the system does
> not work."

**Confirmed as a real gap, and measured.** Only **12 of the 42** `mod_*.R` files use
`withProgress` or `Progress$new`: `mod_algo`, `mod_chat`, `mod_classification`,
`mod_climate_trend`, `mod_gam`, `mod_lidar`, `mod_lme`, `mod_ntl`, `mod_rf`, `mod_rs_search`,
`mod_surface`, `mod_workspace`.

**Every remaining model screen shows nothing at all while it computes** — including
`mod_da`, `mod_svm`, `mod_dtree`, `mod_xgboost`, `mod_clustering`, `mod_linear_regression`,
`mod_anova`, `mod_logistic`, `mod_pca`, `mod_sem`, `mod_bayesian`, `mod_survival`,
`mod_timeseries` and `mod_tests`. On a slow fit the app looks frozen, which is exactly the
report.

**This is the same underlying problem as G28**, where curvature "running in a loop" turned out
most likely to be a large DEM with no visible progress — and the conclusion there was
explicit: *"the user needs to see progress and be able to stop, not to have curvature made
10% faster."*

**Do not solve this per module.** Two constraints make a global approach the right one:

- **Shiny is single-threaded** (established in G29), so an in-process fit blocks the session
  and a server-rendered spinner cannot animate during it. A **client-side** indicator driven
  by Shiny's own busy state is the only thing that works during a blocking computation.
- Shiny already emits `shiny-busy` on `<html>` and `recalculating` on each output. A global
  CSS/JS overlay keyed off those needs **zero per-module wiring** and covers all 42 screens at
  once — the same "fix it once in CSS rather than 51 times in R" reasoning that settled
  round-1 item 3, and the same pattern as the existing global plot-download hover overlay.

**Then, on top of that**, add real `withProgress` to the heavy screens where the work has
nameable stages — but "real info and not assumed info", the constraint the reporter set in
round-1 item 1: the step must advance on work actually finished, never on a timer.

**Relationship to G29:** heavy algorithm runs already have both a status line and a working
Stop button via `compute_worker.R`. This item is about everything that never got routed
through the worker — in-process fits, which is most of the app.

#### Built 2026-08-04 — the global "Running…" pill

**A promise the code had already made and not kept.** `ui.R` sets
`--shiny-fade-opacity: 1` and `.recalculating { opacity: 1 !important }`, deliberately
turning OFF Shiny's own dimming — because at startup ~40 modules recalculate at once and the
whole page greyed out. The comment justifying that trade says feedback comes instead from
"the boot overlay + Running pill". **The Running pill did not exist** — searching the repo
for it returns only that comment. So the app had *less* running-feedback than stock Shiny on
the 30 screens with no `withProgress()`, which is precisely the reported symptom.

**Built as `#ea-busy`** ([ui.R](ui.R)): a small pill, bottom-left, driven entirely by the
`shiny-busy` class. Bottom-**left** because the Co-Pilot panel occupies the right
(`position: fixed; right: 0; width: 460px`).

**Why client-side CSS and not a Shiny output.** Shiny is single-threaded (established in
G29), so while an in-process fit runs, the server cannot render, send, or animate anything —
a server-driven spinner is exactly the thing that cannot work here. The browser is a separate
process and keeps painting, so a CSS animation toggled by a class is the only mechanism that
moves while R is blocked. It also needs no per-module wiring, which is what makes one change
reach all 42 screens.

**Verified the mechanism rather than assuming it:** `shiny.min.js` contains
`$(document.documentElement).addClass("shiny-busy")` — so the class really does land on
`<html>`, which is what the selector keys off.

**Honest by construction:** it is shown by Shiny's real request state, never a timer, so it
cannot report work that is not happening — the "real info and not assumed info" constraint
from round-1 item 1. The 400ms delay applies only on the way in (it sits on the
`.shiny-busy` rule, so it stops applying the instant the class is removed), meaning fast
round-trips never flash it and hiding is immediate.

**Also extended the existing skeleton shimmer to `.ea-wsx-modcanvas`**, which is where the
model screens render — without it, the screens this item is about showed nothing at all.

Reduced-motion is handled without losing the signal: the pill still appears, only the spin
and the fade stop.

**Verified in the actually-served page** (app running, `curl` of the real response, 207 KB):
`id="ea-busy"`, the `html.shiny-busy #ea-busy` rule, and the new modcanvas shimmer selector
are all present, and the pill sits after `#ea-boot` in the DOM so the boot-overlay
suppression selector resolves.

**NOT verified, and worth stating plainly:** no browser automation is available in this
environment, so I have **not watched the pill appear during a real slow fit**. The class
mechanism, the markup, the CSS and the DOM order are all confirmed; the visual result is not.
Note also gotcha 24 — measuring this in a non-compositing pane would lie, so a real browser
is the only honest check.

**Still open (the second half of this item):** real `withProgress()` on the heavy screens
that have nameable stages. The pill says *something* is running; it cannot say *what*, and on
a genuinely long fit that is not enough.

---

### 24. Release notes on the site, updating automatically
> "to add a release notes on out site that updates automatically"

**The content already exists and is good.** `CHANGELOG.md` holds **29 versioned entries**
with a consistent structure (`## vMAJOR.MINOR.PATCH — date`, then `### Fixed` / `### Added`
sections), and the version is single-sourced in
[global.R:12](global.R#L12) (`APP_VERSION <- "0.8.1"`), shown in the app's status bar and
About panel. So this is a **publishing** problem, not a writing one.

**What is missing, checked:**

- `landing/index.html` contains **no** reference to a release, a changelog, or a version —
  the site never tells a visitor what changed or even which version is current.
- There is **no `.github/workflows` directory at all** — the repo has no CI, so there is
  currently nothing that could run on push.
- `landing/vercel.json` is a pure static deploy: `"buildCommand": null`,
  `"outputDirectory": "."`. Nothing transforms anything at deploy time today.
- `CHANGELOG.md` lives in the **repo root**, not in `landing/`, so Vercel does not deploy it.

**The uncomfortable finding this surfaced, which matters more than the plumbing.** The newest
changelog entry is **v0.8.1 — 2026-07-29**, but Round 3 and Round 4 landed fixes dated
**07-30, 07-31 and 08-04** (items B6, B8, C9, C14, D17, round-3 7/9/10/14, round-4 20/23 and
the 18 defect half). **None of them are in the changelog, and `APP_VERSION` is still 0.8.1.**
So "updates automatically" would currently publish a page that is already several days and
roughly a dozen fixes behind.

**Decide this first, because it determines whether the feature is worth building:** is
`CHANGELOG.md` going to be kept current as part of finishing work? Automating publication of
a stale source just makes the staleness public and puts it on the front page. The
release-notes page and the "bump `APP_VERSION` + add a changelog entry" habit have to ship
together, or this is worse than no page at all.

**Three ways to do the publishing, with the real trade-off stated:**

| approach | needs | cost |
|---|---|---|
| **A. Build step** — convert `CHANGELOG.md` → `landing/release-notes.html` at deploy | a `buildCommand` in `landing/vercel.json` | gives up the zero-toolchain static deploy; fully static output, fastest page |
| **B. Client-side fetch** — page fetches raw `CHANGELOG.md` from GitHub and renders it | nothing in the repo | no build step at all, but the page breaks if GitHub is unreachable, and needs a Markdown renderer inlined (the site has no bundler) |
| **C. GitHub Action** — regenerate the HTML on push to `main` and commit it | a first `.github/workflows` | keeps the deploy static AND the page always current; adds CI to a repo that has none |

**Recommend C**, with A as the fallback. C keeps `landing/` a plain static directory (which
is what makes the installer one-liners work today, see item 16) while guaranteeing the page
matches `main`. B is tempting because it needs nothing, but a release-notes page that fails
when GitHub hiccups is exactly the kind of thing nobody notices is broken.

**DECIDED 2026-08-04 — approach C, but DEFERRED to a later session.**

> "did you add the change log and github actions so that the page is automatically updated?"
> … "we can keep that for another session."

So the blocking question above is answered — **`CHANGELOG.md` will be kept current**, and the
page is to be generated and published automatically via a **GitHub Action**. The work itself
is deliberately held for a separate session.

**State when picking this up:** the `CHANGELOG.md` entry side has started (v0.8.2 added
2026-08-04, and it names the v0.8.1→v0.8.2 gap rather than hiding it). **Not built:**
`landing/release-notes.html`, the generator, the workflow, and the nav link. Note the repo
still has **no `.github/workflows` directory at all**, so this would be its first — and
`landing/vercel.json` is a pure static deploy (`buildCommand: null`), which approach C
deliberately preserves.

**Also worth doing once the page exists:**

- Link it from the app — a "What's new" entry near the version already shown in the status
  bar / About panel, so users who never visit the site still see it.
- An anchor per version (`#v0-8-1`) so a support answer can point at one release.
- Pairs with **item 17** (documentation + tours), which is the other "users do not know what
  this app does" gap and wants the same nav slot on the landing page.

---

### 26. A "Code editors" menu — mini R terminal, full RStudio, Python, Jupyter
> "improving the rconsole. if we can, we should rename the current r terminal as mini R
> terminal. and if possible, we can have the full R studio view (no need to redesign, we just
> get it. so we can have a top menu option for only code editors, Python, Jupyter Notebook,
> R Code"

**Four asks of very different size.** They are listed here smallest first, because the first
one is worth doing on its own and the last two may not be doable at all under this app's
install promise.

**Grounding facts, checked:**

- `mod_rconsole.R` is 469 lines and its editor is a plain **`textAreaInput`** — not Ace, not
  CodeMirror, not Monaco. There is no code editor in this app today.
- The label "R Console" appears in **`ui.R` (5 places)** and **`mod_workspace.R` (2)**.
- **No Python integration exists.** The only `reticulate`/Python references are in
  `mod_gee.R`, which is **deliberately un-wired** precisely because "rgee needs Python + a
  GEE account" (CLAUDE.md).

**1. Rename to "mini R terminal" — trivial, and do it.** ~7 label sites. It also sets the
right expectation, which is the real value: the current screen is a small scratchpad, and
calling it that stops it being judged as a failed IDE.

**2. Make it a real editor — the actual prerequisite.** Three already-open console items
(**C11** run line-by-line, **C12** script tabs, **C13** environment pane) are all blocked on
the same thing: a `textAreaInput` has no notion of a current line, a selection, or a gutter.
`shinyAce` or a Monaco/CodeMirror binding would unblock C11-C13 **and** be the "R Code"
editor this item asks for. **This is the highest-value piece in the whole item** and should
be settled before anything below it.

**3. "Full RStudio view … we just get it" — the honest constraint.** This cannot be embedded:

- **RStudio Desktop** is a native app. It cannot be put in an iframe. The most that is
  possible is *launching* it as a separate process pointed at the project folder — which is
  not a view inside the app, though it may be exactly what is wanted.
- **RStudio Server** *can* be iframed, but there is **no Windows build** — it is Linux-only,
  so on the primary target platform it would mean WSL or Docker. That breaks the install
  promise this app is built on ("no toolchain, no admin"; `deps.R` goes out of its way to use
  CRAN binaries so no compiler is ever needed). Shipping Docker to get an editor would be the
  single biggest regression to the product's main advantage.
- **Positron / VS Code Server** are the realistic middle ground if a full IDE in the browser
  is genuinely wanted, but that is adopting a second large dependency, not "just getting it".

**Recommend:** a **"Open in RStudio"** button that launches the user's own installed RStudio
on the project folder, plus doing (2) properly so the in-app editor is good enough for most
work. State plainly that an embedded RStudio is not on the table.

**4. Python and Jupyter — decide the product question first, not the technical one.** Both
require a **Python toolchain on the user's machine**, which the app currently guarantees is
not needed. Jupyter additionally needs a local server running and its framing headers relaxed
before it could be shown in a panel. This is the same wall `mod_gee.R` hit and was shelved
for. It is *possible* (item 12 already sketches a `reticulate` sidecar), but it changes what
EasyAnalysis promises at install time — from "one installer, no toolchain" to "install Python
too". **That is a positioning decision, and it should be made deliberately rather than
arrived at by adding a menu.**

**Suggested split:** ship 1 + 2 as one piece of work (rename + real editor, which also closes
C11-C13); treat 3 as a launcher button; and hold 4 until the toolchain question is answered.

---

### 27. Remove the Co-Analyst suggestion chips — FIXED 2026-08-04
> "to remove that suggestions."

**Read as: the clickable suggestion chips in the Co-Analyst panel.**
`mod_chat.R` renders `uiOutput(ns("suggestions"))` ([mod_chat.R:337](mod_chat.R#L337)),
builds the chips in `output$suggestions` ([:422-428](mod_chat.R#L422-L428)) and sends the
chosen prompt via `observeEvent(input$suggest, ...)` ([:480](mod_chat.R#L480)). Removing them
is those four sites plus the `.chip` CSS ([:279-280](mod_chat.R#L279-L280)).

**This is consistent with a rule the system prompt already enforces**, which is why the
reading is probably right: the prompt at [mod_chat.R:175](mod_chat.R#L175) already says
*"Do NOT volunteer 'best next step' suggestions, recommend switching variables, or propose
alternative…"*. The chips are the last place the app still volunteers a next step, so
removing them makes the UI agree with the instructions the model is given.

**RESOLVED 2026-08-04 — it is the chips, and Recommend STAYS.** Asked which of the two was
meant; the answer was explicit:

> "keep the recommend feature. for now, only how the table is styled in the recommend should
> be used. keep it for now."

So `mod_recommend.R` is **not** touched by this item, and is in fact now a *reference* for
item 28. Scope is exactly the four chip sites above.

---

### 28. "dbl" means nothing to users — spell the column types out — FIXED 2026-08-04
> "in the dataset summary area, users do not understand what dbl is. i think we should go
> with the regular style. same as the table in the Co-analyst view."

**Located.** `.tlbl()` in [mod_data.R:1119-1127](mod_data.R#L1119-L1127) is the only place
these come from, and it is a small closed set — so this is a one-function change:

| current | proposed |
|---|---|
| `dbl` | number / numeric |
| `int` | whole number / integer |
| `fct` | category / factor |
| `chr` | text |
| `lgl` | true/false / logical |
| `date` | date (already fine) |

These are **tibble/pillar abbreviations**. They are conventional to R users and opaque to
everyone else — and this app's whole point is that the user does not have to write code, so
the audience is exactly the group that has never seen `<dbl>`.

**Decide:** plain-English words ("number", "text", "category") or the full R class names
("numeric", "character", "factor")? The former suits the stated audience; the latter keeps
the label the same word the rest of the app and the docs use. **Recommend plain English with
the R name as the tooltip**, so nothing is lost for users who do know R.

**RESOLVED 2026-08-04 — the reference is the Recommend screen's "Data Profile" table.**

> "only how the table is styled in the recommend should be used."

That is [mod_recommend.R:646-667](mod_recommend.R#L646-L667) — a plain
`tags$table(class = "table table-sm table-hover mb-0")` with a `thead`, four columns
(**Column · Type · N/A · Profile**), 11-12px type, `3-4px 8px` cell padding and a
`max-height:260px` scroll box. `mod_recommend.R` is **kept** (see item 27), so it stays
available as the model.

**SCOPE CORRECTED 2026-08-04 — keep this small.** An earlier draft of this entry proposed
also rewriting Recommend's own `num`/`cat` labels and extracting a shared labeller for both
screens. The reporter rejected that:

> "I dont like that you did that … only type needs to be be changed or simplified."

**So the job is exactly two things and nothing else:**

1. **Simplify the Type label** in the dataset summary — `.tlbl()`,
   [mod_data.R:1119-1127](mod_data.R#L1119-L1127).
2. **Style that table like Recommend's** — layout and density only.

**Explicitly NOT in scope:** changing `mod_recommend.R`'s own labels, and any shared-labeller
refactor. Recommend is the *style* reference, not a second thing to fix. Leave it alone.

**Noted for the item 18 sweep, not for this item:** the Recommend table also carries
hardcoded hex (`#fff8e1`, `#4caf50`, `#e65100`, `#888`, `#555`) and
`thead(class = "table-light")`, which is overridden nowhere in `ui.R`/`theme.R` and so keeps
bslib's dark-compiled literal (the `.bg-light` problem from round-1 item 3). Worth knowing if
its markup is copied, but it is a colour-sweep item and does not belong in this change.

**Sweep note:** `.tcol()` immediately below ([mod_data.R:1128-1130](mod_data.R#L1128-L1130))
assigns each type a **hardcoded hex** (`#1565c0`, `#2e7d32`, `#33691e`, `#6a1b9a`, `#e65100`,
`#555`) — a direct hit for the item 18 hardcoded-colour sweep, and one that will not follow
any theme. Fix both in the same visit.

---

### 29. The Co-Analyst panel must expand, dock, shrink
> "one key thing is make the co-analystt to expand, dock shrink, and so on."

**Currently a fixed slab.** `.copilot-panel` is
`position: fixed; top: 46px; right: 0; bottom: 30px; width: 460px`
([mod_chat.R:244-247](mod_chat.R#L244-L247)) — one size, one place, open or closed. It cannot
be widened for a long answer or shrunk out of the way, and while open it covers the right
side of the workspace.

**The app already has both mechanisms this needs — reuse them, do not invent a third:**

- **Drag-to-resize** exists on the workspace side panels (round-1 item 9), and the lesson
  from that work applies directly: put the width in a **CSS variable**, not an inline width,
  or the collapse/expand states will throw away whatever size the user chose.
- **Dock / float / minimize** exists for tool panels — `tool_mode` is already
  `"dock" | "float" | "min"` with buttons wired at
  [mod_workspace.R:1615-1617](mod_workspace.R#L1615-L1617). The Co-Analyst should take the
  same three states and the same control cluster so it behaves like everything else.

**Ties directly to item 30:** if the Co-Analyst becomes a dockable panel, it is one more
thing competing for the same sidebar — so the two should be designed together rather than the
Co-Analyst getting a private docking scheme.

---

### 30. The dock holds only one tool — it should hold several
> "another thing is the side bar for docking only holds one tool then replaces it when we
> dock another. the goal is for many tools to be docked."

**Root cause found, and it is structural rather than a bug.** The workspace stores exactly
one tool:

- `current_tool <- reactiveVal(NULL)` — **a single value**
  ([mod_workspace.R:1513](mod_workspace.R#L1513)), reassigned on every pick
  ([:1595-1598](mod_workspace.R#L1595-L1598)).
- `tool_mode <- reactiveVal("dock")` — **one mode shared by that one tool**
  ([:1607](mod_workspace.R#L1607)).

So docking a second tool cannot add to the dock; it can only overwrite the variable. Nothing
is going wrong — the state simply has no room for more than one.

**What the change actually is:** `current_tool` becomes an ordered collection of docked
tools, each carrying its own mode, with one marked active. That is a contained change to the
state, but it has three consequences worth deciding before touching code:

1. **Several module UIs would be mounted at once.** Module *servers* are bound once at
   startup and are unaffected, so this is safe in principle — but it must not produce
   **duplicate output ids** in the DOM. That exact trap already bit this project: the LiDAR
   screen and the 3D view shared output ids, which is why `lidarPointcloudCanvasUI` was
   deleted rather than left mountable alongside `lidar3DOnlyUI` (D18 part 2). Any tool that
   can appear twice, or whose ids overlap another's, breaks.
2. **The selector re-arm fires per tool open** (`ds_refresh`, gotchas 18 and 26). Opening a
   second tool bumps it, which re-populates selectors in the tool **already** docked — that
   could wipe a selection the user has made. This needs testing explicitly; it is the most
   likely source of a subtle regression.
3. **Space.** Several docked tools in one column means an accordion, tabs, or a stack with
   collapse. Given round-1 item 12 established the principle — *clutter you chose is fine,
   clutter by default is wrong* — docked tools should probably collapse to their titles with
   one expanded.

**Do this with item 29**, since both change what the right-hand column can hold.

---

### 31. Languages in sync — do step 1 in one language, step 2 in another
> "languages should kinda be in sync where users can simply use one language to say, step 1,
> then use another language to do step 2, for example. cus i think the data is saved while we
> work."

**This is the point of item 26's Python/Jupyter half**, and it is a much better statement of
it: the value is not "we also have Python", it is **one dataset, several languages, in
sequence**. Clean in R, model in Python, plot back in R — without exporting and re-importing
between each step. Read them together; 26 is the surface, this is the requirement.

**"the data is saved while we work" is correct, and it is why this is feasible at all.**
Datasets live in `dataset_pool` and are persisted to the project (`datasets.rds`), so there
already **is** a single shared store for tabular data. A second language does not need a
parallel world — it needs read/write access to that same pool. The R console already works
exactly this way: it reads the pool, and `df <- ...` writes back to the selected dataset
(C9).

**Where it is genuinely hard, stated honestly:**

- **Tabular data crosses cleanly.** `reticulate` converts data.frame ↔ pandas, so the
  R-console contract ("your result goes back to the pool") extends to Python almost directly.
- **Spatial objects do NOT.** A `terra` SpatRaster is a **C++ pointer** — this is already
  established in G29, which is why the compute worker passes *paths, not objects*. The same
  applies here, and the same solution works: hand Python a **file path**, not the object.
  `sf` and tabular data serialise; LAS is expensive to copy. So the sync boundary is
  "tabular in memory, spatial by path".
- **Model objects do not cross at all.** An `lm` fitted in R is not usable in Python and vice
  versa. So "step 2 in another language" means the **data** carries over, not the fitted
  state. Say that plainly in the UI or users will expect otherwise.

**The prerequisite is unchanged and is the real decision:** Python has to exist on the
machine, which today's installer deliberately does not require (item 26 part 4). **Nothing
here should be built until that positioning question is answered** — the sync design is the
easy half.

**Sequencing note:** item 19 (Steps/Checkpoints) is the natural home for this. If a step
already records "what was run, on what data", then "which language ran it" is one more field
on a step, and the two features reinforce each other instead of being built twice.

---

### 32. Multi-step undo — up to 5 — FIXED 2026-08-04
> "multi step undo. could be undo up to 5 times."

**Currently exactly one step**, and the code says so itself —
[mod_data.R:268](mod_data.R#L268):

```r
prev_state <- reactiveVal(NULL)  # one-step undo snapshot
```

`snap()` ([:271](mod_data.R#L271)) overwrites that single slot, and it is called at the top
of **~14 mutating handlers**. The undo handler ([:292-299](mod_data.R#L292-L299)) restores it
and then sets it back to `NULL`, so a second undo reports "Nothing to undo."

**The change is small and well-shaped**, precisely because `snap()` is already the one choke
point every mutation goes through:

- `prev_state` becomes a **bounded stack** (a list, newest last, capped at 5).
- `snap()` pushes and trims to the cap; undo pops.
- The button should say how many steps remain, or it will look broken at the sixth press —
  which is the same complaint as item 23 (the app must not look dead).

**Cap it, and cap it deliberately.** 5 snapshots of a data frame is 5 full copies in memory.
This project has been bitten by exactly this before — the project-load cache was **bounded at
4 entries** specifically because an unbounded cache of large objects is how the app OOM-ed
previously (round-1 item 1, CLAUDE.md `.read_las_capped`). So 5 is a sensible number, but the
bound must be enforced rather than assumed, and it should be a named constant next to the
stack.

**Decide:** does undo cover **only the Data screen**, or the R console too? Today it covers
Data only, and C9 already flagged the gap — *"Undo in the Data screen still covers edits made
there, not console edits"* — which matters more now that a console assignment can overwrite a
dataset in place. A shared undo stack on `dataset_pool` would cover both, but is a bigger
change than extending `mod_data.R`'s.

**Related:** "Reset to Raw Data" (round-3 item 5, still open) is the unbounded version of the
same idea and should be scoped to the active dataset. Worth doing in one visit.

---

### 33. More statistical analyses, and more inside each one — REGISTRY BUILT 2026-08-04
> "more and more functionalities in the statistical analyses."
> "more and more statistical analyses."

**Two asks — deeper existing screens, and more screens — and the second one has an
architectural problem worth settling before adding the next twenty.**

**Where the app stands today (checked, not assumed):**

- **Tests** (`mod_tests.R`): chi-square, Friedman, Kruskal-Wallis, McNemar, one-sample t,
  paired t, runs test.
- **Regression**: `lm`, plus `glm` with **poisson / quasi / binomial** families already
  living inside `mod_linear_regression.R` ([:117](mod_linear_regression.R#L117),
  [:135-136](mod_linear_regression.R#L135-L136), [:540](mod_linear_regression.R#L540)) —
  which is exactly what **E22** wants separated.
- **Mixed models**: `nlme::lme` only — Gaussian, no `family` argument (see item 34).
- **Multivariate / ML**: DA, PCA, clustering, classification, RF, XGBoost, decision tree,
  SVM, neural net.
- **Specialised**: survival, SEM (`lavaan`), Bayesian, GAM (`mgcv`), time series, climate
  trend, wind.

**Visible gaps, as candidates rather than a decision:** ordinal regression (`MASS::polr`),
robust regression (`MASS::rlm`), quantile regression (`quantreg`), GLMM (item 34), GEE,
zero-inflated / negative-binomial counts, repeated-measures ANOVA and MANOVA, post-hoc
beyond Tukey, effect sizes and power analysis, mediation/moderation, meta-analysis. **Ask
which of these the actual users need** — this list is derived from what is absent, not from
demand, and building all of it would be worse than building the right five.

**The architectural point, and the reason not to just start adding modules.** This project
already learned this lesson once, in D18: spatial operations used to be bundled inside
screens, and were turned into **data** — `algorithms.R` holds one spec per operation
(`id, label, group, inputs, params, run`) and `mod_algo.R` renders and runs any of them. The
payoff was explicit: *"Adding an operation is a list in `algorithms.R` and nothing else"*,
and cancellation (G29) then became one change instead of 33.

**Statistical analyses have had no equivalent move.** Each is a hand-written module —
~35 of them — so "more and more analyses" means more and more modules, each repeating its own
selectors, its own view switching, its own result panes, and each one a fresh chance to
reintroduce gotchas 18/26 (which have already produced empty dropdowns on *four* screens).

**So decide first: is there a `statistics.R` registry?** A spec per method
(response/predictor roles, family, options, `fit()`, and what to render) would make most new
analyses a list entry and give every screen the same variable picker for free — which is
**E19 + E20** solved structurally rather than screen by screen. Methods that genuinely do not
fit the shape (SEM, survival, time series) stay as modules, exactly as
`mod_suitability.R` stayed out of `algorithms.R` because its criteria list is
variable-length.

**DECIDED 2026-08-04 — build it.**

> "none for now but we can create it. and others too."

So: no registry exists today, and one should be created — **and the same treatment is wanted
for other families of screens, not just statistics.** That makes this the structural item the
rest of Round 4 leans on:

- **E19 + E20** stop being a per-screen job — one picker, declared once by the spec's roles.
- **Item 34 (GLMM)** becomes an entry plus a fit function, not a module (as far as its
  parameters fit the shape — its random-effects builder may not; see item 34).
- **"More and more analyses"** becomes tractable, which is the whole point of the ask.
- **Gotchas 18/26 stop recurring.** Every new hand-written module is a fresh chance to
  reintroduce the empty-dropdown bug; a runner that builds selectors with `renderUI` — the
  way `mod_algo.R` already deliberately does — cannot hit it at all.

**Build it the way `algorithms.R` was built, because that one worked:** a registry of specs
plus ONE generic runner, proven on a few real entries before anything is migrated. Do **not**
convert 35 modules up front. `mod_algo.R` is the working reference for the runner, and
`ea_algorithms()` for the spec shape.

#### BUILT 2026-08-04 — `statistics.R` + `mod_stat.R`, with 5 new analyses

**The registry exists and hosts five methods the app did not have.** Deliberately proven on
NEW methods rather than by porting existing screens: nothing could regress, and the work
delivers "more analyses" immediately.

| method | engine | new dependency |
|---|---|---|
| Ordinal regression | `MASS::polr` | none — `MASS` was already core |
| Robust regression | `MASS::rlm` | none |
| Poisson (counts) | `stats::glm` | none |
| Negative binomial | `MASS::glm.nb` | none |
| **GLMM** (item 34) | `lme4::glmer` | `lme4`, added to `extras` |

**What it settles beyond "more analyses":**

- **E19 + E20 are solved structurally** for everything the registry hosts. The variable picker
  is generated from the spec's declared **roles**, so every method gets the same
  `selectizeInput(multiple = TRUE)` (UX rule 11) without a line of per-screen UI. Role naming
  is normalised too — the survey found the response variously called `y`, `y_var`, `target`,
  `response` and `category` across the hand-written screens.
- **Gotchas 18/26 are made impossible here.** Role pickers are `renderUI`, never
  `update*Input`. The survey found **9 of 17** existing modules use `update*Input` and so
  depend on the `ds_refresh` workaround; the registry needs none of it.
- Runner rules carried over from `mod_algo.R` for reasons already paid for: an empty first
  choice so nothing is auto-selected (G27), the isolate/keep pattern so a re-render does not
  wipe a selection (gotcha 21), and results through `ea_view_header()`/`ea_view_panes()` so
  the select-and-split pattern matches the ten screens already using it.
- Each entry returns `list(context=, plot=)`, so the **Co-Analyst sees a registry method
  exactly as it sees a hand-written screen**.

**Two real bugs the tests caught, both worth recording:**

1. **`glm(offset = ...)` does not see a local variable.** `glm()` deparses that argument and
   evaluates it in the model frame, so `offset = off` failed with `object 'off' not found`.
   The offset goes into the **formula** as `offset(col)` instead, referencing a real column.
2. **The binomial guard only checked non-factors,** so a 4-level *factor* response slipped
   past it into `glmer` and fitted something meaningless. It counts levels for factors too
   now and refuses with a message naming the actual level count.

**Verified:** all 5 fit through the runner against realistic data and render every declared
view; Run with nothing chosen refuses; role type-filtering accepts a count column and rejects
a continuous one; all 5 appear in the workspace menu (with an existing algorithm as the
control that the check is valid); and the tool panel + canvas build with the roles
placeholder, the Run button and the shared view header.

**NOT done, deliberately:** migrating the 9 spec-able existing screens (xgboost, dtree, svm,
nnet_ml, gam, pca, survival, anova, rf). That is a separate decision now that the pattern is
proven, and it carries regression risk that none of this work did. The 5 genuinely irregular
ones (`mod_tests`, `mod_da`, `mod_descriptive`, `mod_clustering`) should stay modules — see
the survey notes above.

#### MIGRATION STARTED 2026-08-04 — one screen at a time

**8 of 9 done.** Progress: **xgboost ✅** · **svm ✅** · **dtree ✅** · **nnet_ml ✅** ·
**pca ✅** · **gam ✅** · **rf ✅** · **survival ✅** · anova.

**Running score: 8 screens migrated, 9 latent bugs.**

**My prediction for survival was WRONG, and the correction matters.** I predicted it would be
clean because it has no validation path — the thing that had explained every previous bug. It
had no validation bug. It had a **worse** one: the Cox proportional-hazards model never fitted
at all, because the formula could not be parsed.

**So the real common thread is not cross-validation — it is
`tryCatch(..., error = function(e) NULL)`.** Look at where the bugs actually hid:

| screen | what swallowed the failure |
|---|---|
| SVM | per-fold `tryCatch(… , error = function(e) NULL)` → empty CV forever |
| GAM | `tryCatch(…, error = showNotification)` around the only fit |
| Survival | `tryCatch(…, error = function(e) NULL)` around `coxph` |

In each case the code *did* fail, loudly, and the failure was discarded. **That is the pattern
to carry forward**, and it is a stronger predictor than "has a CV loop": a silent `NULL`
fallback is where a permanently-broken feature can live indefinitely without anyone noticing.
Cross-validation loops were simply where that idiom happened to cluster.

Every port has been bit-for-bit faithful, and four of the five turned up something broken
that nobody had noticed. That remains the strongest argument for finishing: these screens are
not being exercised, and porting is what exercises them.

| screen | latent bug found | had a hand-rolled CV loop? |
|---|---|---|
| XGBoost | two `xgboost` 3.x API breaks — the screen errored on Run | no (a package API moved) |
| SVM | cross-validation never produced a result, ever (silent per-fold failure) | yes |
| Decision tree | validation scored rpart's DEFAULT tree, not the configured one | yes |
| Neural network | both CV loops hardcoded `maxit = 200`, ignoring the user's setting | yes |
| **PCA** | **none — clean** | **no** |
| GAM | **could never fit a model at all** (`mgcv::s()` unparseable), plus CV dropped basis AND method | yes |
| Random forest | `rfcv()` ignored `ntree` and used the classification `mtry` rule on regression models | not hand-rolled — a package call, and it still lost the settings |
| Survival | **the Cox model never fitted** — its formula was unparseable (`__t__`) | no validation path at all; a silent `tryCatch` hid it |

**The per-fold-refit pattern is confirmed in every screen that has one** — three for three —
and should be the default suspicion rather than a surprise. SVM's refits ignored cost, gamma
and scaling; decision tree's ignored every `rpart.control` setting; neural network's ignored
`maxit`. In each case the validation measured a *different model than the one on screen*, and
only SVM's failed visibly. **Check this first in `gam` and `rf`**, the two remaining screens
with their own CV loops. `anova` and `survival` have none and may well be clean, like PCA.

**Why it keeps happening:** every one of these loops re-derives its settings from the FITTED
object (`res$fit$kernel`, `res$fit$decay`) or hardcodes them, instead of using the parameters
the user supplied. The registry avoids it structurally — `fit(df, r, p)` has `p` in scope, so
the fold refits use the same values the displayed model did.

**The first migration paid for itself twice over, in ways worth recording:**

**a) It exposed a real gap in the registry: it could not render PLOTS.** The five launch
methods emit text and tables only, and both return fine as UI from `renderUI` — a DT widget
is just markup. A plot is not: it needs a device, so it must be a `renderPlot` binding
created when the module server is built. Every one of the 9 screens has plots, so this
blocked the whole migration and was invisible until a real screen was attempted. Added:
`plots` (named drawing functions, one output bound per entry), `ea_stat_plot()` for specs to
emit the tag, `views_plot` so the plot-appearance control appears only where there is a plot
(F26), plus `ea_chk()` for booleans and `show_if` for a setting that only applies sometimes.

**b) It found that the XGBoost screen was already BROKEN and nobody knew.** Not a regression
from this work — `xgboost` changed its API in 3.x (installed here: 3.2.1.1) and the screen was
never updated. **Two** independent breakages, either of which kills it on Run:

| what the module called | what 3.x does |
|---|---|
| `xgboost(data =, params =, verbose =)` | `params` removed, `data` renamed to `x` — the call errors |
| `cv$best_iteration` | now `NULL`; the value moved to `cv$early_stop$best_iteration`, so `nrounds = NULL` reached the trainer |

Fixed in the port with `xgb.train()` and a tolerant lookup that checks both locations and
falls back to the minimum of the test metric, so the next API move degrades instead of
erroring.

**This is an argument for continuing the migration**, beyond tidiness: a screen nobody had
run recently was silently dead, and porting it is what surfaced that. Worth assuming the
other 8 may hold similar rot.

**Parity is the standard for each migration** — the port must reproduce the module, not
reimplement it. For XGBoost: **identical predictions (max abs difference 0)**, same
`best_nrounds`, same importance ranking, on both regression and binary classification.
Verified against the module's own computation, read out of its `observeEvent` rather than
rewritten.

**Retirement pattern** (following D18's retired spatial bundles): the module file stays
sourced so nothing referencing its UI functions breaks, but the hardcoded `MODUI` line and
the `server.R` binding are removed — otherwise the screen appears in the menu **twice**, from
two different implementations. Verified: XGBoost appears exactly once, as `stat_xgboost`.

##### Migration 2 — SVM (2026-08-04)

**Third latent bug, and the worst of the three: SVM's cross-validation had NEVER produced a
result.** The screen showed "Awaiting SVM CV results…" indefinitely. Cause: the refit inside
each fold passed the fitted model's `kernel` back into `svm()`
(`mod_svm.R:210`, `:267`) — but an e1071 model stores the kernel as an integer **code**
(`radial` = 2), and `svm(kernel = 2)` fails with `wrong kernel specification!`. That error was
swallowed by `tryCatch(..., error = function(e) NULL)`, so every fold failed silently, the
prediction vector stayed empty, and the CV reactive returned `NULL` forever.

Verified directly: `fit$kernel` is `2` (numeric), and refitting with it errors while refitting
with `"radial"` succeeds. The port passes the kernel NAME, and also passes the cost, gamma and
scaling the user actually set — the old fold refits silently used defaults for all three, so
even had it worked it would have been validating a different model than the one on screen.

**Two structural improvements the port brought:**

1. **Validation is computed ONCE, in `fit`.** The module ran the whole k-fold loop inside its
   render outputs, so every redraw of the metrics table refitted k SVMs. It now runs under the
   Run progress bar, which is where a slow job belongs.
2. **The two cross-validation controls are labelled.** SVM had a "5-fold" checkbox wired to
   e1071's own `cross=` AND the shared `.cv_ui` block driving the manual loop, with nothing to
   distinguish them. Both are kept; both now say what they are.

**Parity verified:** identical predictions and identical support-vector counts against the
module's own `svm()` call, for eps-regression, C-classification, and a non-default
(polynomial, cost = 4) kernel; the gamma default (`1/n predictors`) matches; LOOCV is
honoured; predictor-equals-response is refused; all 3 views render for both task types.
Conditional visibility (gamma hidden for a linear kernel, degree only for polynomial, epsilon
only for eps-regression) is preserved via the new `show_if`.

##### Migration 3 — Decision tree (2026-08-04)

**Fourth latent bug, and the same shape as SVM's.** `mod_dtree.R`'s per-fold refits
(`:242`, `:295`) called `rpart(fml, data = tr, method = …)` with **no `control` argument at
all**, so every fold was built with rpart's defaults — not the max depth, cp, min-split and
min-bucket the user had set. The validation numbers therefore described a tree that was not
the one on screen.

Unlike SVM's, this one did not fail loudly or quietly — it produced *plausible* numbers for
the wrong model, which is worse. **Measured:** on the test data the default tree has **8
leaves** where the configured one has **2**. Fixed by passing the same `rpart.control` the
displayed tree uses.

Also moved the validation into `fit` (computed once instead of per redraw), added a clear
refusal when a regression tree is asked for a categorical response, and labelled the pruning
checkbox so it is distinguishable from the separate hold-out validation.

**Parity verified:** identical predictions AND an identical `cptable` against the module's own
`rpart()` + prune sequence, for both regression and classification, including a non-default
`maxdepth = 2, cp = 0.001, minsplit = 5, minbucket = 2`; all 4 views render for both types.

##### Migration 4 — Neural network (2026-08-04)

**Fifth latent bug — the fold pattern again, third screen running.** Both CV loops in
`mod_nnet_ml.R` (`:197`, `:255`) hardcoded **`maxit = 200`** regardless of the user's Max
iterations. A network trained for 1000 iterations was validated against one trained for 200.
The loops did at least recover `size` and `decay` from the fitted object, so this is milder
than dtree's — but it is the same failure: the validation described a different model.

**Measured:** on the test data the objective is `12.6269` at `maxit = 200` versus `12.5393`
at `maxit = 2000` — genuinely different fits, so the numbers were not interchangeable. The
port passes the user's value, and also applies the correct `linout` per task type.

**Parity verified:** identical predictions AND an identical final objective value against the
module's own best-of-`n_init` restart loop, for regression and classification, including a
non-default architecture (`size = 9, decay = 0.2, maxit = 150, n_init = 2, scale_x = FALSE`
all changed together). A regression network now refuses a categorical response with a clear
message rather than failing inside `nnet`; all 3 views render for both task types.

##### Migration 5 — PCA / FA / MDS (2026-08-04)

**Taken fifth on purpose: the first UNSUPERVISED entry.** No response role at all, just a set
of variables plus an optional grouping column — the one spec shape the registry had not been
proven on. Better to find a gap here, with four screens still ahead, than after four more
same-shaped ports. **No gap was found in the role model**, but the port did force one runner
change (below).

**No latent bug — the first clean port.** Worth recording as evidence rather than treating the
earlier four as proof the codebase is uniformly rotten: PCA has **no hand-rolled CV loop**,
which is the thing all four buggy screens shared.

**The runner change it forced: live display parameters.** `pc_x`, `pc_y` and "colour by" are
*display* options — the module read them inside `renderPlot`, so changing an axis redrew
instantly. `render(fit, key, solo, ns)` has no access to inputs, so a naive port would have
required pressing Run again to look at PC3 instead of PC2 — a real regression on an
exploratory screen. A plot function that declares a **third argument** now receives the live
parameter values. Existing two-argument plots are untouched (same tolerant dispatch as `ns`).

**Also added `show_if` to roles**, not just parameters, so "Colour points by" appears only for
PCA and not for FA or MDS.

**Parity verified against the underlying functions directly** rather than a re-implementation:
identical `sdev`, `rotation` and scores versus `prcomp`; identical points versus `cmdscale`;
identical uniquenesses versus `factanal`. The scale flag is honoured (scaled and unscaled
verified to differ). The NA row in the fixture is dropped, and the colour column is subset by
the same complete-case filter so it stays aligned with the points.

**One improvement:** factor analysis with more factors than the variables support used to
surface R's bare `2 factors are too many for 4 variables`. It now names the failure and says
what to try (fewer factors, or Principal axis) — verified by the guard test.

##### Migration 6 — GAM (2026-08-05)

**The prediction made after PCA held exactly.** GAM had a hand-rolled CV loop, so it was
flagged as suspect before it was opened — and it turned out to be the worst screen yet, with
**two** bugs, one of them total.

**Bug 7 — the GAM screen could never fit a model. At all.** `mod_gam.R:154` built its smooth
terms as `mgcv::s(...)`. mgcv identifies a smooth by the term LABEL starting with `s(`, so a
namespaced call does not match: `gam()` treats it as an ordinary variable, `model.frame`
evaluates it, gets the smooth-spec list back and dies with
`invalid type (list) for variable 'mgcv::s(...)'`. The call was wrapped in
`tryCatch(..., error = function(e) showNotification(...))`, so pressing "Fit GAM" produced an
error toast and nothing else — every single time.

Verified both forms directly: `mgcv::s(...)` errors, plain `s(...)` fits with R² 0.949 on the
same data. The port uses plain `s()` and attaches `s` to the formula's environment, so it
works whether or not mgcv happens to be attached (it is an optional package, so it may not
be).

**Bug 8 — its CV dropped TWO settings.** `mod_gam.R:319-321` rebuilt the fold formula without
the chosen basis (always the `tp` default) and hardcoded `method = "REML"`. A cubic-regression
GAM selected by GCV.Cp was validated as a thin-plate REML fit. This is the fold pattern for
the fourth time, and the first instance where *two* settings were lost at once.

**New capability this port forced: `actions`.** GAM has a second button ("Predictions to data
pool") that operates on an existing fit rather than producing one. The spec now takes an
`actions` list; `ea_action(id, label, run)` gets the fit and the app's pools, and the buttons
appear only once a fit exists. **Random forest's partial-dependence button needs the same
slot**, so this was not a one-off.

**Parity verified against `mgcv::gam` directly:** identical coefficients, fitted values and
R², including a non-default `k = 6, bs = "cr", method = "GCV.Cp"` (confirmed to be a genuinely
different fit from the default). The per-predictor comparison table still flags a sine
relationship as non-linear (gain 0.26). The action writes an `observed/lm_pred/gam_pred` table
into the pool, one row per fitted row.

##### Migration 7 — Random forest (2026-08-05)

**Bug 9, and it REFINES the pattern rather than repeating it.** RF was flagged as suspect
because it had validation — but its validation is not a hand-rolled loop at all: it calls
`randomForest::rfcv()`. It still lost the model's settings, in two ways
(`mod_rf.R:101`):

- **`ntree` was never passed**, so the CV curve came from 500-tree forests no matter where the
  slider was. Verified that `ntree` *does* reach `rfcv()` through `...` and *does* change
  `error.cv`, so this was a passthrough that was simply omitted.
- **`rfcv()`'s default `mtry` is `function(p) max(1, floor(sqrt(p)))`** — the *classification*
  rule — and it was left at the default even for regression models, whose displayed fit used
  `floor(p/3)`.

**So the rule to carry into the last two ports is broader than "hand-written loops are
risky":** it is **any validation path that does not inherit the fitted model's parameters**,
whether you wrote the loop or a package did. Delegating to a package function does not make
the settings travel with it.

**Second `actions` use, and it needed one more capability.** GAM's action just had a side
effect (write a table); RF's partial-dependence button must **produce something a view then
renders**. `ea_action`'s `run()` may now return `list(message =, store =)`, and `store` is
merged into the fit record as `extra`, which plots can read. That is what keeps a slow
computation behind a button instead of recomputing every time its view is shown — the reason
the module used a button in the first place.

**Parity verified:** identical out-of-bag predictions and identical importance matrices
against `randomForest::randomForest()` directly, for both regression (`mtry = p/3`) and
classification (`mtry = sqrt(p)`), with `ntree` honoured. The PDP view shows guidance before
the button is pressed rather than erroring, and reports clearly when the chosen variable is
not one of the model's predictors.

##### Migration 8 — Survival (2026-08-05)

**Bug 10, and it disproved my own prediction — which is the useful part.** Survival has no
validation path, and on the pattern established through seven screens I expected it to be
clean like PCA. It was not. It had a **worse** bug than any validation issue:

**The Cox proportional-hazards model never fitted.** `mod_survival.R:152` built

```r
as.formula("survival::Surv(__t__, __e__) ~ age + dose")
```

and `__t__` is not a parseable R symbol — an identifier cannot begin with an underscore. So
`as.formula()` threw *before* `coxph()` was ever called, `tryCatch(error = function(e) NULL)`
at `:155` discarded the error, and `cox_fit` was `NULL` every single time. Adding covariates
produced an empty Cox view and no message. Verified directly: the string fails to `parse()`,
while the same model with valid names fits fine.

**The corrected pattern, which is the finding worth keeping:** the common thread across these
screens is **not** cross-validation. It is `tryCatch(..., error = function(e) NULL)`. SVM's
folds, GAM's only fit and survival's Cox model each failed loudly and had the failure thrown
away. CV loops were merely where that idiom clustered. A silent `NULL` fallback is where a
permanently-broken feature can live for months without anyone noticing — that is what to grep
for, and it is worth doing across the whole app rather than only in the screens migrated here.

**Parity verified against `survival::` directly:** identical KM survival curve, identical risk
sets, identical log-rank chi-square, and identical Cox coefficients under both Efron and
Breslow tie handling. Kaplan-Meier and the log-rank test were always fine — only the Cox half
was broken.

**Also improved:** an event indicator that is not 0/1 is refused with a message naming the
offending values (previously it produced a meaningless model), and the Cox and log-rank views
say what to choose when covariates or a grouping variable have not been selected instead of
rendering an empty panel.

**"More inside each one" is cheaper and can start immediately** — two concrete items are
already recorded and unbuilt:

- ~~**`uef_evaluation()` is defined, sourced, and called by nothing**~~ — **WRONG, corrected
  2026-08-04.** I repeated a stale claim from CLAUDE.md gotcha 9 without checking. It *is*
  called, by `mod_lme.R:188`, `mod_rf.R:127`/`:147` and
  `mod_linear_regression.R:630`/`:769`. Gotcha 9 has been rewritten. The registry's shared
  `.ea_v_metrics()` calls it too, so registry-hosted methods report the same numbers as the
  hand-written screens.
- **Plain-English interpretations** — the "Future Work Queue" in CLAUDE.md already specifies
  this with a worked `.interp_ttest()` template. It is the single highest-value addition for
  the stated audience, who can run a model but not read one.

---

### 34. A very detailed GLMM — BUILT 2026-08-04
> "a very detailed GLMM analyses."

**Not an extension of the existing screen — the engine cannot do it.** `mod_lme.R` uses
**`nlme::lme` only** ([mod_lme.R:4](mod_lme.R#L4),
[:149-150](mod_lme.R#L149-L150), [:213-214](mod_lme.R#L213-L214)), and there is **no `family`
argument anywhere in the file**. `nlme::lme` fits Gaussian LMMs; it cannot fit binomial,
Poisson or negative-binomial responses at all. The Co-Analyst's `lme` tool has the same
limit ([agent_tools.R:272-273](agent_tools.R#L272-L273)).

**Neither `lme4` nor `glmmTMB` is in `launcher/deps.R`** — confirmed against both the `core`
and `extras` lists. So this needs a dependency added, and **the guard must go on the server
binding, not just the UI** (CLAUDE.md gotcha 27 — this is exactly how the `plotly` crash took
down the whole workspace on a fresh machine).

**Engine choice matters and should be made deliberately:**

| engine | strengths | cost |
|---|---|---|
| **`lme4::glmer`** | the standard; binomial/Poisson/Gamma; huge literature; `MuMIn` (already a dependency) computes Nakagawa R² from it | no negative-binomial without `glmer.nb`; no zero-inflation; harder crossed-random-effect diagnostics |
| **`glmmTMB`** | negative-binomial, zero-inflation, dispersion models, spatial/temporal correlation structures | heavier dependency; smaller user base; different summary object to parse |

**Recommend `lme4::glmer` first** — it covers the common cases, pairs with `MuMIn` which the
app already installs, and matches what the reference workflows (VMI/NFI) would use. Add
`glmmTMB` later if counts with excess zeros turn up.

**"Very detailed" — what that has to mean here, given what already exists:**

- **Family + link pickers**, and a random-effects builder that can express random intercepts
  **and** random slopes, nested and crossed — the current screen only offers what `lme`'s
  `random =` syntax covers.
- **Convergence handling is not optional.** CLAUDE.md gotcha 7 already records that
  `nlme::lme` *"frequently fails to converge"* when predictors are on different scales, and
  `glmer` is worse in this respect. The screen must surface the singular-fit and
  convergence warnings in plain language and offer the standard remedies (scale predictors,
  change optimiser) rather than printing a raw error — otherwise this becomes the next
  "screen that cannot be run".
- **Diagnostics that suit GLMMs**: `DHARMa` residuals (quantile residuals — ordinary residual
  plots are misleading for non-Gaussian GLMMs), overdispersion and zero-inflation checks,
  random-effect caterpillar plots, ICC, and marginal/conditional R² via `MuMIn`.
- **`uef_evaluation()`** for the metric card, closing part of gotcha 9 on a new screen rather
  than retrofitting an old one.

**Scope check before building:** this is the most detailed single analysis in the backlog. It
is worth confirming whether it should be its own screen or a mode of a combined
"Mixed models" screen alongside the existing LMM — two screens that differ only by `family`
would be the same duplication E22 is complaining about on the regression side.

#### BUILT 2026-08-04 — as a registry entry, not a module

**The open question is answered: the random-effects part DOES fit a static spec.** A grouping
role (`multiple = TRUE`, for crossed effects) plus an optional random-slope role is enough to
build `(1 | g)`, `(slope | g)`, `(1|a) + (1|b)` and `(1|a/b)`. So GLMM is an entry in
`statistics.R`, not a new module — and it did not force the registry to model something it
could not express.

**Built LAST on purpose, and that ordering paid off:** the four `MASS`/base methods proved the
spec, runner and wiring against zero install risk first, so when GLMM was attempted any
failure would clearly have been GLMM-specific rather than a registry problem.

- `lme4` added to `extras` in `launcher/deps.R`. The `lme4::` call sits **inside `fit`**,
  which only runs on Run, so it cannot break server construction (gotcha 27) — and it is
  still `requireNamespace`-guarded with a message naming the package, because the workspace
  has a package installer that can fetch it.
- **Convergence is treated as a first-class result, not a footnote** (gotcha 7 warns that
  `nlme::lme` frequently fails to converge and `glmer` is worse). The "Convergence & fit" view
  reports singular fits in plain language with the standard remedies, plus Nakagawa R² via
  `MuMIn` — which the app already installs.
- Views: Model summary, Fixed effects, Random effects (variance components), Convergence & fit.

**Verified** against simulated grouped data: binomial and Poisson random-intercept fits,
a random slope, crossed `(1|site)+(1|blk)`, nested `(1|site/blk)`, all rendering every view;
a 3+-level response is refused with a message naming the level count; and a deliberately
singular fit still returns a usable model whose Convergence view renders rather than crashing.

**Not done:** `glmmTMB` (zero-inflation, negative-binomial mixed models) — add later if counts
with excess zeros turn up, per the engine comparison above.

---

### 35. UNRESOLVED FRAGMENT — "the views for the analyses"
> "the views for the analyses: I dont like that you did that"

Recorded rather than guessed at. The sentence that followed the colon turned out to be a
**scope objection about item 28's table** (now applied — see item 28), so the words *"the
views for the analyses"* were left without a statement of their own.

**It may mean nothing, or it may be a real objection to the select-and-split view pattern**
(round-1 item 12, rolled out across PCA, decision tree, SVM, XGBoost, neural network,
survival, time series, GAM, wind and Bayesian). That pattern was built to a specific
principle — *the default is deliberately ONE view; clutter you chose is fine, clutter by
default is what was wrong* — so if it is now unwanted, that is a significant reversal
affecting ~10 screens and should not be inferred from a fragment.

**Ask before acting.**

1. **Item 20 (`plotly`)** — first, and not close. It is a **fresh-install blocker**: every
   new user hits it, the installer reports success, and the failure only appears at boot.
   Small, fully diagnosed, three concrete edits.
2. **Item 23 (busy indicator)** — global, cheap via `shiny-busy`, and it makes every other
   slow thing in the app stop looking broken. Also partly closes G28.
3. **Item 18 defect half** (native `<select>` popups via `color-scheme`) — measurable, small.
   Hold the taste half until the reporter says what "inconsistent" means.
4. **Item 22** — ask which of the three readings is meant; it may already be Round 3 item 1.
5. **Item 21** — confirm what "Capped Norm Threshold" refers to, and decide how unlabelled
   rows are nominated, before writing any DA code.
6. **Item 19 (Steps + Checkpoints)** — largest, greenfield, and needs the copy-vs-reference
   decision settled first. Steps before Checkpoints.
7. **Item 24 (release notes)** — small once the approach is chosen, but do **not** start it
   before deciding whether `CHANGELOG.md` will be kept current. It is already ~12 fixes
   behind, and publishing that automatically would put the gap on the front page.
8. **Item 25 (black & white theme)** — small and self-contained once the greyscale-vs-
   high-contrast question is answered. Do it **before** the item 18 sweep, so the new set is
   swept in the same pass instead of becoming the next thing that needs one.
9. **Item 18 full sweep** — the static hardcoded-colour pass (scriptable, like
   `check_plot_views.R`) and the per-mode runtime measurement, across all 6 sets (7 with
   item 25). Last, because it should only be done once.

10. **Item 26 parts 1+2** — rename to "mini R terminal" and give it a real code editor. Worth
    pulling forward: the editor is the thing blocking **C11, C12 and C13**, so one piece of
    work closes four entries. Parts 3 and 4 (embedded RStudio, Python/Jupyter) are blocked on
    a positioning decision, not effort.

**Round 4 additions from 2026-08-04 (items 27-30):**

- **Item 28 (spell out `dbl`)** — smallest useful change in the whole backlog: one function,
  `.tlbl()`. Do it with the item 18 sweep, because `.tcol()` right beneath it is hardcoded
  hex. Pin down the reference table first.
- **Item 27 (remove suggestion chips)** — four sites, but **confirm which "suggestions"** is
  meant before deleting; `mod_recommend.R` is the other candidate and is a far bigger removal.
- **Items 29 + 30 together (Co-Analyst expand/dock/shrink, multi-tool dock)** — both change
  what the right-hand column holds, so designing them separately would mean two competing
  docking schemes. 30 is the deeper one: `current_tool` is a single `reactiveVal`, so the
  state has no room for a second tool. Watch the duplicate-output-id trap (D18 part 2) and
  the `ds_refresh` re-arm (gotchas 18/26) wiping selections in an already-docked tool.
- **Item 32 (5-step undo)** — small and well-shaped: `snap()` is already the single choke
  point all ~14 mutations pass through, so it is one stack plus a cap. Do it with round-3
  item 5 (scope "Reset to Raw Data" to the active dataset) — same surface, one visit.
- **Item 31 (multi-language sync)** — do **not** treat as separate from item 26 part 4. It is
  the *requirement* that Python half exists to serve, and both are blocked on the same
  toolchain decision. If it goes ahead, build it on item 19's steps rather than beside them.

**Round 4 additions from 2026-08-04 (items 33-35):**

- **Item 33 (more statistics)** — the "more inside each screen" half can start today:
  `uef_evaluation()` is written and called by nothing (gotcha 9), and the plain-English
  interpretation templates are already specified in CLAUDE.md's Future Work Queue. The "more
  screens" half should **not** start until the registry question is settled, or every new
  analysis is another hand-written module.
- **Item 34 (GLMM)** — needs a new engine (`lme4`) and a new dependency before any UI work.
  Decide first whether it is its own screen or a family mode of the existing Mixed models
  screen; two screens differing only by `family` is the duplication E22 already objects to.
- **Item 35** — a fragment, not an item. **Ask what "the views for the analyses" meant**
  before touching the select-and-split pattern; reversing it would affect ~10 screens.

**Three questions answered 2026-08-04, recorded so they are not re-asked:** the "suggestions"
to remove are the **Co-Analyst chips**, not `mod_recommend.R` (which is **kept**); the table
to copy is Recommend's **Data Profile** table, **styling only**; and item 28 is scoped to
**the Type label alone** — no shared-labeller refactor, and Recommend's own labels stay as
they are.

**Cheap and high value, from the round-5 check:** the tour engine already exists and carries
**2 of the 8+** steps asked for, so **F24 + item 17's tour** are content plus one `data-tour`
attribute per target — not a build. Linking the app to the already-published docs pages is
the other small piece with nothing in place at all.

**Status after 2026-08-04:** items **20** and **23** (global signal) are done and verified;
**18**'s defect half is in but its reported symptom is not reproduced. Items **19**, **21**,
**22** and **24** are all blocked on a decision, not on effort — see each item for the
specific question.

---

## Round 5 — reconciliation of a re-sent list (2026-08-04)

The reporter re-sent a batch of items with *"i guess some are not documented in backlog…
it might overlap but we can filter"*. **Filtered: all 24 are already documented, and every
one of them is a Round 2 entry.** Nothing in that batch is new, so nothing was added from
it — this table exists so the same list can be checked off next time instead of re-triaged.

**10 fixed · 2 partly fixed · 12 still open.**

| # | Re-sent item (abbreviated) | Entry | Status |
|---|---|---|---|
| 1 | black colour on the packages page | A1+A2 | **FIXED** 07-30 |
| 2 | dataset information not visible in the options | B4 | open |
| 3 | separate each data & exploration command, keep synced | B6 | **DONE** 07-30 |
| 4 | card colour and text colour in light mode | A3 | **defect FIXED** 07-30; taste call open |
| 5 | active dataset does not change when another is clicked | D15 | **FIXED** 07-29 |
| 6 | `vmi9_transformed <- df %>% mutate(...)` made a new dataset | C9 | **FIXED** 07-30 |
| 7 | rename how the data is called (`df` for everything) | C10 | open |
| 8 | result area fills for plots but not other commands | C14 | **FIXED** 07-30 |
| 9 | run the console line by line, not the whole buffer | C11 | open |
| 10 | load an R script, terminal-only; editor tabs | C12 | open |
| 11 | environment view as an adjustable third column | C13 | open |
| 12 | table scroller / sticky header / smaller type | F23 | **FIXED** 07-30 |
| 13 | replace "Pick a tool above…" with the tour button, 8+ steps | F24 | open |
| 14 | export report as PDF | F25 | open |
| 15 | black colour in Share project / the Project dropdown | A2 | **FIXED** 07-30 |
| 16 | edit data table does not work | B8 | **FIXED** 07-30 |
| 17 | complete tab switch; map view should always exist | D16 | **partly** — desync fixed, "map always there" open |
| 18 | Download spatial data switches away from map view | D17 | **FIXED** 07-30 |
| 19 | batch apply, positioned on each data-processing tool | B7 | open |
| 20 | 3D/point cloud opens two views; spatial & LiDAR carry their own | D18 | **DONE** (parts 1-3) 07-29/30 |
| 21 | variable selection differs per screen (XGBoost, decision tree) | E19 | open |
| 22 | reuse the existing predictor picker / quick editor | E20 | open |
| 23 | move "Select Diagnostics to View:" | E21 | open |
| 24 | separate linear regression from the other regression types | E22 | open |

**Detail recovered from the re-sent wording.** The original E20 entry abbreviated the quote
with an ellipsis and lost the actual instruction — see E20, now corrected: the ask is to
**reuse the components that already exist** (the code path and the quick editor), not merely
to match their appearance.

**The 12 still open cluster into four jobs**, which is the useful way to read the table:

- **Console** (C10, C11, C12, C13) — four separate asks about one screen; worth doing as one
  piece of work rather than four visits.
- **Model screens** (E19, E20, E21, E22) — E19+E20 are one shared variable picker; E21 and
  E22 are small once that exists.
- **Data** (B4, B7) — dataset info in the options, and batch apply.
- **Chrome** (F24, F25) — the tour button and PDF export.
