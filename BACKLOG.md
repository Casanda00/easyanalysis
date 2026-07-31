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

### 12. GeoLibre Cloud GIS Platform Integration & Map Canvas Bridge
> "there should be a way to call geolibre tools into the app."
- **Diagnosis & Integration Architecture:**
  - **GeoLibre Overview:** GeoLibre is an open-source, cloud-native web GIS platform and Python/Jupyter-compatible spatial application for web, desktop, and mobile.
  - **Integration Architecture Options for EasyAnalysis:**
    1. *Embedded GeoLibre View Panel:* Add an interactive GeoLibre map canvas viewer panel (`iframe` / web component modal) into the unified workspace view to view cloud-hosted spatial layers.
    2. *GeoLibre REST & Layer Sync Connector:* Build R helpers to export/stream active `sf` vector layers and `terra` rasters to GeoLibre cloud endpoints.
    3. *Python Subprocess / reticulate Bridge:* Invoke GeoLibre's Python client package (`geolibre`) via R `reticulate` or background system commands to trigger cloud geoprocessing workflows.

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







