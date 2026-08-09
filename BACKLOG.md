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

### 10. Dynamic GDAL / PROJ Authority CRS Database Query & Search Functionality — claimed FIXED 2026-07-31, **REOPENED and genuinely fixed 2026-08-05 (v0.10.5)**
> "the coordinates in the software right now does not really source from gdal or so? similar to how we get rpackages from the source, I want the same for the crs search in the app. and I wan that search sunction too."

**The 2026-07-31 entry below was wrong in practice and is kept verbatim so the mistake stays visible:**
> - `algorithms.R` (lines 50–110, `ea_search_crs()`): Queries GDAL/PROJ's official `proj.db` database (`sf::system.file("proj", package="sf")`/`crs_view`) containing 7,000+ official EPSG Coordinate Reference Systems.
> - Spatial Modules (`mod_algo.R`, `mod_raster.R`, `mod_lidar.R`): Updated target CRS selectors to use `selectizeInput` backed by `ea_search_crs()`, allowing users to type and search by EPSG numeric code (e.g. `3067`), country/region name (e.g. `Finland`, `Oregon`), or projection authority. Tested & verified.

**Reopened 2026-08-05:**
> "searching for the coordinates feels hardcoded. and I cant find some coordinates. lets fix this"

`ea_search_crs()` was written and did work when called — but **nothing ever called it with a
query**. All three pickers used `.ea_crs_choices()`, i.e. `ea_search_crs("", limit = 500)`: a
**static 500-row list** built once at UI-construction time, which selectize then filtered
client-side. The user's typed query never reached `proj.db`, so the entire query half of the
function was dead code. "Tested & verified" evidently tested the function, not the screen.

**Three independent causes, each measured before changing anything:**

| # | Cause | Evidence |
|---|---|---|
| 1 | Only **500 of 7,199** entries offered, ordered by numeric code, so the list stopped at EPSG:32632. British National Grid (27700), UTM 35N (32635), Belgian Lambert 72 (31370), Czech Krovak (5514) and Dutch RD New (28992) were all **absent** — exactly "I can't find some coordinates". | enumerated the offered list and tested membership |
| 2 | Search was a **single SQL `LIKE '%<whole query>%'`**, so any multi-word query failed: `"utm 35n"` → **0 hits** (the real name is "WGS 84 / UTM zone 35N"), `"amersfoort rd"` → **0 hits**. | ran both shapes over the catalogue |
| 3 | **`RSQLite` was in neither `core` nor `extras`** in `launcher/deps.R`, and it is the only way to read `proj.db`. On a fresh install every picker silently degraded to `.ea_crs_choices_fallback()` — **8 hardcoded codes**. That is the literal source of "feels hardcoded". | grepped deps.R |

**Fix (v0.10.5):**
- **`ea_crs_all()`** (`algorithms.R`) — reads the whole catalogue once and caches it:
  **6,886 entries**, excluding only `vertical` and `engineering` types, which cannot serve as a
  horizontal target CRS.
- **`ea_search_crs()`** rewritten to **tokenised conjunctive matching** — every
  whitespace-separated token must appear in `"EPSG:<code> - <name>"`, so a code, a name, or any
  mixture works. `"utm 35n"` **0 → 17 hits**; `"amersfoort rd"` **0 → 3 hits**.
- **`ea_crs_selectize()`** attaches the catalogue **server-side** (`updateSelectizeInput(server = TRUE)`).
  This was not an optimisation but the only workable option: embedding 6,886 entries client-side
  measured **509 KB per picker** and the app builds **five** (reproject, xy_to_sf, vec_reproject,
  plus mod_lidar and mod_raster) — Shiny itself warns against it. Server-side also *buys* the
  token matching, because Shiny's search server splits the query on whitespace and, with
  `searchConjunction = "and"`, requires every token to match.
- **Gotcha 18 applies here and is handled explicitly.** All five pickers live in lazily-rendered
  panels, so an attach sent at construction would be silently dropped. `mod_algo` re-attaches off
  the workspace's `tool_open` signal (which counts *panel renders* and now also reports *which*
  tool rendered, so a picker re-attaches on its own panel and no other); `mod_raster` and
  `mod_lidar` use `deferred = TRUE`, which postpones the attach to `session$onFlushed`.
- **`RSQLite` added to `extras`** with a comment saying what breaks without it.
- `mod_raster.R` no longer claims "Querying 7,000+ official GDAL/PROJ EPSG…" — it said that while
  offering 500.

**Verified:** build OK; catalogue 6,886 (not the 8-entry fallback); all five previously-missing
CRS present; the six failing searches now return hits; **control** — the old single-substring
shape still returns 0 for `"utm 35n"` and `"amersfoort rd"` where the new one returns 17 and 3;
unknown codes still pass through via `create = TRUE`; picker payload **509 KB → 0.9 KB**;
`testServer(algoServer)` clean; app serves HTTP 200 and the page does **not** embed the catalogue.
**Not verified here:** the actual typing experience in a browser (no browser automation in this
environment) — worth a quick eyeball that the dropdown populates as you type.

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

### 13. WhiteboxTools (`whitebox` R Package) 700+ Advanced Spatial Processing Suite — **STEP 1 DONE v0.11.7, step 2 SUPERSEDED by item 74**
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

#### References page FIXED 2026-08-05 — reported, and the worst instance yet

> "in dark mode, the reference page is not fixed. the references, texts and background are
> kinda white -ish. some texts are black but others arent. its true for all modes except white"

**Exactly diagnosed by that description.** `references.R` pinned every reference card to
`background:#fff` (line 35) and gave *some* of its text fixed greys (`#6c757d`, `#495057`,
`#adb5bd`) while leaving the rest uncoloured. On any dark set the card stayed white, the
explicitly-grey text stayed readable — "some texts are black" — and everything without an
explicit colour inherited the app's light `--ink` and vanished into the white card. Light mode
was the only theme where both halves happened to agree, which is why it looked fine there
alone.

12 colour sites, all now theme tokens: the card uses `.ea-subpanel`, body text `var(--ink)`,
secondary text `var(--bark)`, headings and accents `var(--forest)`, links `var(--canopy)`.
The status badges (Implemented / In progress / Cataloged) were a fixed green/amber/grey with
`color:#fff`; they now use `var(--forest)` / `var(--warn)` / `var(--bark)` with
`var(--onbrand)` text, so they shift with the theme instead of being one fixed palette.

**Verified:** zero colour literals in the rendered page.

**This is a reminder that the colour sweep is not finished.** The v0.8.4 pass fixed the
screens that were reported then; `references.R` was never examined. The static scan in the
"scope agreed" section above — hunt every raw hex outside `theme.R` — has still not been run
across the whole app, and this page is proof it would find more.

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

#### BUILT 2026-08-05 — approach C, as decided

**The blocking condition is met.** The decision recorded above was "do it, but only if
`CHANGELOG.md` will actually be kept current" — publishing a stale source would put the gap on
the front page. It has been current for every version since: **v0.8.2 → v0.10.3, eleven
releases, each written as part of finishing the work rather than batched afterwards.**

**Four pieces:**

| piece | what it is |
|---|---|
| `landing/build-release-notes.mjs` | Node generator: `CHANGELOG.md` → `landing/release-notes.html`, using `marked`. Copies the site's own colour tokens rather than linking a stylesheet, because the site's CSP blocks every external host. |
| `.github/workflows/release-notes.yml` | **The repo's first workflow.** Regenerates and commits the page on any push to `main` that touches the changelog or the generator. |
| `landing/release-notes.html` | The committed output — **45 releases**, newest first, one anchor per version so a support answer can link to `#v0-10-3`. |
| Links | Landing nav + footer on all three pages, and a **"What's new in this version"** link beside the version in the app's About panel — the piece item 17 wanted, since a user who never visits the site otherwise cannot find them. |

**Why the output is committed rather than built at deploy time.** `landing/` is a pure static
Vercel deploy, and that is what makes the installer one-liners work (item 16). Adding a
`buildCommand` would trade that away. Generating in CI and committing the result keeps the
site static and the page always current — the whole point of choosing C over A.

**No infinite loop, by construction:** the workflow triggers only on `CHANGELOG.md` and its own
generator, and writes only `release-notes.html` — a path it does not watch. So its own commit
cannot re-trigger it. (GitHub also suppresses runs for pushes made with the default
`GITHUB_TOKEN`; the path filter is the guard being relied on, not that.)

**Verified locally** (the generator runs the same way CI runs it): 45 sections, balanced tags,
no external script/stylesheet/font/image, both colour schemes declared, an anchor id per
release, newest first, the changelog's editing preamble dropped in favour of a real
introduction.

**Not verified:** the workflow has never executed — it runs on the next push that touches
`CHANGELOG.md`, which is this one. Table and code-fence rendering is also untested because the
changelog currently contains neither; the handling is in place for when an entry uses them.

**A regression this caught in passing:** the earlier Co-Analyst rename had turned
"an AI Co-Pilot" into "an Co-Analyst" in the About panel. Fixed.

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

#### 26a. DECIDED 2026-08-05 — the menu is called **"Write code"**, in the top menu
> "create a new menu where R, Python, Jupyter notebook will live and name it as Write code.
> should be in the top menu."

Naming and placement are settled: a **top-level menubar entry named "Write code"**, holding
**R**, **Python** and **Jupyter Notebook**. It is a sibling of the existing groups (Data /
Models / Machine Learning / Spatial & LiDAR), not a submenu buried inside one.

**What can ship immediately vs. what is gated:**

| Entry | State | Gate |
|---|---|---|
| **R** | Shippable now | `mod_rconsole.R` exists; point the menu at it and rename it "mini R terminal" (part 1 above). Part 2 — a real editor instead of `textAreaInput` — is what makes it worth visiting. |
| **Python** | **Gated** | No Python integration exists anywhere in the app. Requires a Python toolchain on the user's machine. |
| **Jupyter Notebook** | **Gated** | Needs Python *plus* a local Jupyter server running *plus* relaxed framing headers before it can be shown in a panel. |

**So the menu can be created now, but two of its three entries cannot yet do anything.** Two
honest ways to handle that, and the choice should be deliberate:
1. **Ship "Write code" with R only**, and add Python/Jupyter to it when the toolchain question
   (part 4 above) is answered. The menu is never misleading.
2. **Ship all three**, with Python and Jupyter opening a short "requires Python on this
   computer — set it up" panel that detects whether Python is present and says what to do.

**Recommendation: option 2**, because it makes the *product direction* visible without pretending
the capability is there, and the detection panel is small. But note it does soften the install
promise in the user's eyes even before any code runs — the menu itself is a statement that
EasyAnalysis is multi-language. That is the positioning decision part 4 flags, and creating the
menu is effectively taking it.

**Cross-reference:** this is the "one dataset, several languages" idea recorded around
BACKLOG:2324 (item 31, multi-language sync) — the menu is where that would surface. Note the
menu-free workspace flow in DESIGN.md: check that adding a top-level group is still consistent
with it before building.

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

### 32. Multi-step undo — up to 5 — FIXED 2026-08-04, VERIFIED + leak fixed 2026-08-06
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

#### OUTCOME — built, and re-verified 2026-08-06 (v0.10.23)

Everything above is the *plan*; the entry carried a FIXED marker but never recorded what was
actually shipped. Checked against the code and driven through `testServer` rather than trusted:

- `undo_stacks` is a **per-dataset** bounded stack, `.UNDO_MAX <- 5L` as a named constant next to
  it. **Confirmed:** 7 mutations retain exactly 5 snapshots; five undos walk backwards through the
  history in order (6→5→4→3→2); the sixth refuses with a message instead of corrupting anything.
- **Keyed by dataset**, which fixes a real bug the single slot had: switching from A to B and
  pressing Undo restored **A's data into B**. **Confirmed** an undo on B uses B's own history and
  leaves A's stack intact.
- The remaining-steps count is reported in the notification, because the Undo control is static
  markup fired from JS in four places and has no server-rendered label to update.

**One real bug found by that verification — gotcha 14 again.** The pruning that drops stacks for
deleted datasets read `names(dataset_pool)`. Removing a dataset sets `dataset_pool[[k]] <- NULL`,
which **leaves the name in place with a NULL value**, so every deleted dataset still looked live
and the pruning dropped nothing — the memory leak it existed to prevent stayed open for the whole
session. Now filtered on the **value**, the same thing `.pool_names()` does in `server.R`.

**Still open on this item:** the decision above — undo covers **the Data screen only**, not the R
console (C9). A console assignment can overwrite a dataset in place with no undo. A shared stack on
`dataset_pool` would cover both and is the natural home for **Step 4's feature deletion** too.

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

**9 of 9 DONE.** **xgboost ✅** · **svm ✅** · **dtree ✅** · **nnet_ml ✅** · **pca ✅** ·
**gam ✅** · **rf ✅** · **survival ✅** · **anova ✅**

**Final score: 9 screens migrated, 10 latent bugs in 7 of them.** Every port was verified
bit-for-bit against the underlying function before the old module was retired. **ANOVA was
clean** — checked, not predicted: it has no silent `tryCatch`, and its unusual
"return a string instead of a model" sentinel is honoured by every consumer including
`plot_aov_diagnostics()`.

**The three screens that could not produce a result at all:** XGBoost (package API moved
underneath it), GAM (smooth terms unparseable), Survival (Cox formula unparseable). **Five
validated a different model than the one displayed:** SVM, Decision tree, Neural network, GAM,
Random forest. **Two were clean:** PCA, ANOVA.

**Not one of these was ever reported by a user**, which is the point: each either failed
silently or produced plausible-looking numbers.

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
| **ANOVA** | **none — clean** | no silent `tryCatch`; every handler reports |

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

##### Migration 9 — ANOVA (2026-08-05) — MIGRATION COMPLETE

**Clean. No bug found — and this time it was checked before being claimed**, on the reporter's
explicit instruction after the survival prediction proved wrong. The facts:
`mod_anova.R` has **no silent `tryCatch`** — every handler returns or `cat`s a message — and
its unusual sentinel (return a *string* where a model is expected) is honoured by every
consumer, including `plot_aov_diagnostics()` in helpers.R, which checks `is.character(model)`
before plotting. Nothing was hiding.

**Parity verified against `aov()` / `TukeyHSD()` directly:** identical ANOVA table, identical
Tukey comparisons, identical eta-squared, Cohen's f and LOOCV (via the same `.loocv_lm()`
hat-matrix shortcut). The plain-English interpretation sentence is preserved and now also
reports how many group pairs Tukey found to differ. The Grid/Single diagnostic toggle became
a live display parameter, so it redraws without refitting.

**One test artifact worth recording** (it is not a code fault, and I nearly logged it as one):
calling a `plots` function directly in a test fails without an open graphics device, because
`renderPlot` normally supplies one. Open a device in the test — the failure is the test's.

---

#### MIGRATION COMPLETE — what it cost and what it bought

**Cost:** 9 ports, each verified bit-for-bit against the underlying function before the old
module was retired. No screen lost a feature; two gained capabilities the registry did not
have when the migration started (`plots`, `actions`, live display parameters, conditional
roles and parameters).

**Bought:**

1. **Ten pre-existing faults found and fixed**, none of which had ever been reported — three
   screens could not produce a result at all.
2. **E19/E20 solved structurally** for every migrated screen: one variable picker, generated
   from declared roles.
3. **Gotchas 18/26 made impossible** for anything the registry hosts.
4. **Adding an analysis is now a list entry.** The registry holds **14 methods** — the 5 it
   launched with plus these 9.

**The finding to carry forward, in priority order:**

- **`tryCatch(..., error = function(e) NULL)` is where broken features hide.** It explains
  SVM, GAM and Survival directly. **This has not been swept app-wide yet** — the remaining
  ~25 modules were not examined, and that is the obvious next investigation.
- **Any validation path that does not inherit the fitted model's parameters is wrong.** Five
  of nine screens had one. It is not specific to hand-written loops: Random forest's went
  through `randomForest::rfcv()` and lost the settings just the same.

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

### 36. App-wide sweep for silent `tryCatch` — DONE 2026-08-05 (investigation)
> "that trycatch sweep seems like a good idea"

The migration established that `tryCatch(..., error = function(e) NULL)` is where broken
features hide — it explained SVM, GAM and Survival directly. This is that sweep, across every
`.R` file in the repo root (excluding `*_legacy.R`).

**Method:** for every silent error handler (`function(e) NULL | invisible() | {} | NA`), look
back 12 lines for a model-fitting call. **Stated limitation:** it can miss a fit more than 12
lines above its handler, and can flag one that is merely nearby — so every hit was read by
hand rather than trusted. (A parse-tree walker was tried first and abandoned: empty arguments
in calls like `df[, cols]` raise "argument is missing" when touched.)

**Result: 77 sites across 17 files; 28 in files not examined during the migration.**

**Two reassuring findings, both checked rather than assumed:**

1. **The SHARED cross-validation helper is correct.** `.kfold_cv()` (`helpers.R:29-56`) takes
   the **formula and family as arguments**, so it necessarily inherits the caller's model
   specification and cannot have the "validates a different model" bug at all. **All five
   validation bugs were in per-module hand-rolled loops, never in the shared helper** — which
   is the same argument the registry rests on, arrived at independently.
2. **The primary-fit sites that looked dangerous are handled properly.** `mod_ntl.R:176`
   wraps its only `lm()` but checks the result on the very next line and reports it;
   `mod_linear_regression.R:53` is an optional VIF helper whose `NULL` means "no VIF", not
   "no model".

**What remains — NOT fixed, recorded in priority order:**

| priority | where | why it matters |
|---|---|---|
| ~~1~~ | `mod_da.R:646`, `:653` | **DONE 2026-08-05 — see below.** Its CV was *not* dead, but it validated a different model. |
| ~~2~~ | `mod_logistic.R:197`, `mod_classification.R:272`, `mod_lme.R:214` | **DONE 2026-08-08 — see below.** Not one shape but two: logistic *omitted* rows, classification *fabricated* predictions. `lme` was already correct. |
| ~~3~~ | `agent_tools.R:243, :255, :274, :275, :304` | **DONE 2026-08-06.** The Co-Analyst now says what it could not compute (`.agent_soft()` / `.agent_why()`) instead of returning a silent `NULL`. |
| ~~4~~ | `mod_timeseries.R:178`, `:219` | **DONE 2026-08-08 — see below.** `decompose()` now reports its error; the ADF test says it failed rather than printing nothing. |

**The rule to apply when fixing any of these** — it is what the ported screens now do: a fold
that fails may be skipped, but **the run as a whole must say so**. Either the result is
produced, or the reason is shown. A `NULL` arriving at the UI as "nothing here" is the exact
failure mode this sweep exists to find.

#### Priority 1 resolved 2026-08-05 — Discriminant Analysis

**My suspicion was wrong in the way that matters, and right in another.** I flagged DA as
SVM-shaped, i.e. possibly producing no CV at all. **Tested every method path — all seven
produce predictions.** DA's cross-validation is not dead.

**But it had the other fault, and badly.** The fold refits used **none** of the method
parameters the tool panel offers. Verified by reading the fold block: `kda_sigma`, `kda_C`,
`mmc_C`, `llda_k` and `wlda_weight_type` were all absent, while the displayed fit
(`mod_da.R:213-264`) uses every one of them. So Kernel DA validated at ksvm's default RBF
width and cost instead of the chosen 0.01 / 0.1, Maximum Margin ignored its cost, and Locally
Linear DA used a hardcoded `k = 5` whatever the Neighbours slider said.

**Measured:** a default-parameter fold agreed with the configured model on **38% of rows**.
The accuracy figure was describing a substantially different classifier.

**A second, subtler fault found while fixing it.** When `loclda` hits a singular local
covariance the fit is relabelled `"Locally Linear DA (PCA-decorrelated)"`. The fold loop tested
`mn == "Locally Linear DA"` — an equality test that variant fails — so those folds fell through
to the final `else` branch and **cross-validated plain `MASS::lda`**. The CV was scoring a
different *method*, not merely different parameters. Now matched with `startsWith()`; if
`loclda` genuinely cannot fit a fold it fails and is skipped, which the existing
"no CV available" path reports honestly.

**Also removed a dead branch I had just written.** I added a WLDA weighting branch to the fold
loop before checking that WLDA never reaches it — `mod_da.R:619` routes both LDA and Weighted
LDA to `MASS::lda(CV = TRUE)` instead. Deleted rather than left as misleading code.

**Left open, recorded rather than half-fixed:** that LOOCV branch calls
`MASS::lda(fml, data, CV = TRUE)` with **no weights**, while the displayed Weighted LDA fit
passes them. So WLDA's LOOCV still describes an unweighted model. Fixing it needs a decision —
either pass weights through `lda(CV = TRUE)` (untested whether it honours them) or move WLDA
onto the k-fold path, which would visibly change its label from LOOCV to k-fold.

#### Priorities 2 and 4 resolved 2026-08-08 — the fold loops

Priority 2 was filed as "same fold-skip shape". **It is not one shape, it is two, and only one
of them merely omits data.**

**`mod_logistic.R` — the omission.** A fold whose fit or prediction failed was `next`-ed, so
its rows left the pooled prediction entirely. Accuracy was then computed over a **subset**
while the caption still read *"5-fold CV"*. Now counted (`bad_folds`, `bad_rows`) and stated.

**`mod_classification.R` — the fabrication, and it is worse.** Each class gets a one-vs-all
`glm`. A sub-model that failed to fit returned `rep(0.5, nrow(te))` — and **that constant still
entered `which.max`**. So whenever every fitted class scored below 0.5 on a row, the class
with *no model at all* won the vote, and that invented label was then counted toward the
reported accuracy as a real prediction. A failed class now yields `NA`, which withdraws it
from the vote; a row where every class failed is `NA` and is not scored at all (it is excluded
from accuracy, not counted as an error).

**Why this is not a cosmetic complaint.** Folds do not fail at random. A fold fails when its
training split is degenerate — a rare class absent, a separable subset — which is precisely
the hard case. Dropping it therefore **biases the metric upward** rather than merely making it
noisier. These were wrong numbers presented with full confidence, not missing ones, which is
why they outrank the rest of the sweep despite being fewer sites.

**`mod_lme.R` was already correct** — it assigns `NA` to failed folds and prints
`%d/%d rows used`. Only the wording was strengthened, so a shortfall is *stated* rather than
left to be inferred by comparing two numbers.

**Priority 4 (`mod_timeseries.R`)** — `decompose()` now reports *why* it failed instead of a
bare "Decomposition failed", and the optional ADF test says it could not be computed instead
of printing nothing at all. Printing nothing made a **failed** test indistinguishable from a
test that was never part of the screen.

**Presentation:** `.cv_note()` (helpers.R) renders the caveat, and `.prf_dt()` gained a `note`
argument so it travels **in the same caption as the accuracy**. A caveat placed anywhere else
is a caveat that does not get read. It returns `NULL` on a clean run, so a good result stays
uncluttered.

**Guarded by `check_cv_folds.R`**, which is control-tested in both directions: it asserts the
old 0.5 rule *does* predict the unfitted class, and it injects a genuine fold failure and
requires the caveat to appear — *"Incomplete: 1 of 5 folds could not be fitted, so 18 row(s)
(20% of the data) are NOT included."* Three attempts were needed to make that injection real,
and the failures are recorded in the file because each is a harness fault this project keeps
repeating (see gotcha 33): targeting by call number hit the main fit rather than a fold;
a one-shot flag was consumed by the module's **first** of two CV evaluations, so the value
returned came from a second, clean pass; only a **stateless** marker-row stub fired on every
pass. A guard that passes because the failure never reached the code proves nothing.

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

---

## Round 6 — reported 2026-08-05

Reported while the CRS search fix (round-3 item 10) was being verified. Numbering continues
from round 4, so these are **items 37–44**. Two of them (41, 43) are not defect reports but
questions about the product's direction, and are recorded as such rather than converted into
tasks — item 41 in particular is the reporter asking whether the platform's founding goal has
actually been met, which is a bigger question than any entry here.

### GIS parity — the map view behaves less like a GIS than users expect (37–40)

The framing throughout is explicit and consistent: **"like arc and qgis"**. These are four
separate asks, but they are one job — they are the interactions any desktop GIS gives you on a
layer, and the workspace map currently gives none of them.

### 37. Turn map layers on and off — **ALREADY BUILT; this entry was wrong, needs clarification**
> "users should be able to turn the map layer on and off."

**Correction (2026-08-05, same day).** The first version of this entry claimed "a layer is either
in the pool and drawn, or not in the pool at all — the only way to hide something is to delete
it". **That is false, and it was written without checking.** Per-layer visibility already exists
and is complete:

| Piece | Where |
|---|---|
| State | `lvis` reactiveValues + `.vis(nm)` accessor, `mod_workspace.R:92-93` |
| Toggle handler | `observeEvent(input$ws_vis, …)`, `:132` |
| UI control | a real switch per layer row (`ea-wsx-sw-toggle`), `:233-237` |
| Right-click menu | `eaLayerMenu(...)` also offers hide, `:227-232` |
| Honoured by the map | `.draw_layers()` filters on `.vis()`, `:1188` |
| Honoured by legend + export | `:795`, `:1279`, `:1323` |

It is also *already* implemented the way the gotcha-23 warning demands — inside the single
`renderLeaflet` pass, not via a proxy.

**CLARIFIED by the reporter 2026-08-05 — and DONE (v0.10.6):**
> "there is a toggle switch there already. but we should one for basemap in the layer panel so
> that user can turn the basemap off."

The data layers were never the problem; the **basemap** was the one thing on the map with no row
and no switch. Turning it off was possible only by hunting for "None" at the bottom of a
14-entry menubar list.

**Fix:** a Basemap row in the Layers panel, pinned to the bottom to match its draw order
(`zIndex = 0`, beneath every data layer). It carries the same toggle switch as a layer row, but
no remove button and no expander — it is tiles, not a project layer. Its type label shows which
basemap is active, so the row doubles as a readout of the menubar choice. It renders even in an
empty project, since there is still a map to turn off.

**The one design decision worth keeping:** the toggle is **the same state** as the menubar's
existing "None" entry, not a second visibility flag. `.draw_layers()` already treated `""` as
off (`if (nzchar(bm))`), so the empty string *is* the off state and nothing downstream changed.
A separate boolean would have let the panel say "on" while the menu said "None" — two controls
for one thing, drifting apart. A `bm_last` reactiveVal remembers the last real basemap so
toggling back on restores what was showing rather than snapping to the default.

**Verified** (`testServer`): off sets `""` and `.draw_layers` skips the tiles; on restores;
choosing Satellite → off → on returns **Satellite**, not the default; the menubar's "None"
followed by the panel toggle restores correctly, proving no drift; the row renders both with and
without data. Build OK, app serves HTTP 200.
**Not verified here:** how the row looks (no browser automation) — worth an eyeball.

### 38. Delete features from the map via the attribute table
> "use the attribute table to delete items in the map view using the attribute table - like arc and qgis."

Select row(s) in the attribute table → delete the corresponding features from the layer, with
the map redrawing. This makes the attribute table an **editing** surface rather than a read-only
view, which is a genuine step up in scope.

**The attribute table already exists** — `output$attr` / `output$attr_dt`, `mod_workspace.R:1396-1441`,
showing the active vector layer's own `st_drop_geometry()` attributes. So this is not "build a
table", it is "make the existing table selectable and give it a write path". Three concrete gaps:

1. **`attr_dt` is capped at `utils::head(df, 200)`** (`:1440`). Any layer with more than 200
   features can only ever expose its first 200 rows, so a delete built on it would silently be
   unable to reach the rest. The cap is also unnecessary — the table is already
   `server = TRUE`, so DT pages server-side and does not need pre-truncating. **Remove the cap
   as a prerequisite**, not as part of the delete work.
2. **No selection is wired.** Nothing reads a `_rows_selected` input, and multi-row selection is
   not enabled.
3. **No row ↔ feature link.** Selecting a row highlights nothing on the map, and there is no map
   click to go the other way (item 40).

- **Open question to settle before building:** does deleting edit the layer in place, or write a
  new derived layer? In-place editing needs undo — and round-4 item 32 already asks for
  multi-step undo on the Data screen, so the two should share one mechanism rather than invent a
  second. **Recommendation: in place, behind an explicit edit-mode toggle** (the QGIS pencil
  idiom the reporter is invoking) — deriving a new layer per delete would flood the Layers panel,
  and an always-live delete on a shared pool is too easy to trigger by accident.

### 39. Symbology
> "symbology (was previously documented)."

**Already specified — do not re-triage.** See round-3 item 11, which lists the vector tools
(single symbol, categorised, graduated, rule-based, labels) and raster tools (stretch, classified,
paletted, hillshade blend, transparency). This is a re-request for prioritisation, not new
information, and it is now the third time symbology has come up.

### 40. Click the map to see feature info
> "clicking on the map shows the info - like arc and q. basically the shape attirbute for shapefile and the same for raster."

Click a vector feature → its attribute row; click a raster → the cell value(s) at that point, per
band. The standard GIS identify tool.
- **Where:** `input$<mapId>_click` already fires; vector needs `sf::st_intersects` against the
  clicked point, raster needs `terra::extract`.
- **Watch out:** the click point is WGS84 (leaflet always is) and must be transformed to the
  layer's CRS first — the same trap already recorded for drawn shapes.
- **Nothing handles map clicks today** — there is no `_map_click` / `_map_shape_click` observer
  anywhere in `mod_workspace.R`, and no popups. This one is genuinely absent.

### How to approach 37–40 (agreed sequencing)

**These are not four independent features.** 38 and 40 are two directions of the *same* missing
primitive: a **selection model** that links a map feature to its attribute row. Build that once
and both become small; build them separately and there will be two selection mechanisms that
disagree. 39 is genuinely independent, and 37 is already done.

**Step 0 — settle 37, and remove the row cap.** Confirm what 37 actually means (it is built);
drop `head(df, 200)` from `attr_dt`. Small, and both unblock what follows.

**Step 1 — the selection model.** One `reactiveVal`: `list(layer = <name>, rows = <integer idx>)`.
Everything reads and writes only this. It is the whole design.

**Step 2 — row → map highlight.** Reordered after the reporter named this exact interaction:
> "you know how we can click on a attribute in the attribute table and it gets highlighted in the map.."

**This is the cheapest step in the whole sequence and should come first**, because it needs *no
spatial hit-testing at all*. Row *i* of `attr_dt` is feature *i* of `vector_pool[[act]]` — the
table is a plain `st_drop_geometry()` of the layer, so the mapping is pure indexing:
`input$attr_dt_rows_selected` → `vector_pool[[act]][idx, ]` → draw as a highlight group. DT
returns indices into the original data even when the table is sorted, filtered or server-paged,
so the 1:1 holds. (It only holds once the `head(df, 200)` cap is gone — Step 0.)

Enable `selection = "multiple"` while here; multi-select is what item 38 needs and it costs
nothing now.

**Step 3 — item 40, identify (map → row).** The harder direction, and the only one needing
geometry: transform the click point out of WGS84 into the layer CRS, then `sf::st_intersects`
for vector / `terra::extract` for raster. Writing the hit into the same selection model makes the
table highlight in response — the mirror image of Step 2, for free.

**Both directions are read-only**, so neither can corrupt a layer, and together they prove the
selection model in both directions before anything destructive is built on it.

**Step 4 — item 38, delete.** Only now add edit mode + delete + undo. By this point the only new
thing is the *write*, because selection is already proven in both directions.

**Step 5 — item 39, symbology.** Independent of the above and touches the same draw pass, so
doing it last avoids two sets of conflicting edits to `.draw_layers()`. Vector styling is
currently hardcoded (`mod_workspace.R:1249`, `:1255`), which is the seam it plugs into.

**The one real design tension — how the highlight is drawn.** The map is deliberately built in a
single `renderLeaflet` pass because proxy calls are lost when the element is re-created
(gotcha 23). But making the highlight part of that pass means **every selection change redraws
the whole map**, which is slow with a large raster underneath. Resolution: **do both, from one
source of truth** — draw the highlight inside the render pass (so a freshly created map is
correct) *and* update it via `leafletProxy` on selection change (so selection alone never forces
a redraw). Both read the selection model, so they cannot drift. This is the part most likely to
be got wrong, and it is the reason the selection model has to exist before either item.

### 41. Data source manager
> "data source manager-"

**CONFIRMED 2026-08-05:** *"41, yes. different data sources."* — the ask is about **sources the
current upload cannot reach**, not about the file upload that already exists. So this is a
connectors job, not a dialog job (though a Data Source Manager dialog is the natural home once
there is more than one connector).

Candidate sources, roughly by expected value for this app:

| Source | Route in R | Notes |
|---|---|---|
| **Path / URL to a file** | existing readers | Cheapest by far, and removes the "I must upload a 3 GB .laz" problem. Projects already store spatial layers as **path references**, so this fits the existing model exactly. |
| **PostGIS / PostgreSQL** | `DBI` + `RPostgres`, `sf::st_read(conn, …)` | The standard GIS database. Needs connection storage — see the credentials question below. |
| **WMS / XYZ tiles** | `leaflet::addWMSTiles` | Basemap-style; display-only, so it never enters a pool and never becomes an analysis input. Easiest of the services. |
| **WFS / OGC API Features** | `sf::st_read("WFS:…")` via GDAL | Returns real vector features, so it *does* enter `vector_pool` and behaves like any other layer. |
| **SQLite / GeoPackage / DuckDB** | `DBI` | GeoPackage is already readable as a file; the database case is about picking a *table* out of one. |
| **Generic tabular DB** | `DBI` | Feeds `dataset_pool`, so it serves the statistics half rather than the map half. |

**Decisions needed before building:**
- **Credentials.** A saved connection means storing a host, user and password. Projects are
  plain JSON on disk (`project_store.R`), so a password would land in cleartext in the project
  folder. Either keep connections session-only, or store them outside the project and reference
  them by name. **This must be decided first** — it constrains everything else.
- **Live or imported?** A database layer can be read once into a pool (simple, consistent with
  everything else) or stay live (re-queried, always current, but every pool consumer must cope
  with a layer that can change or vanish). **Recommendation: import first.** It matches the
  existing pool contract; live connections can come later without breaking it.
- **`DBI` + drivers are new dependencies** — `extras`, guarded at the server binding per gotcha 27.
  Note `RSQLite` is now already present (v0.10.5), so the SQLite/GeoPackage case is free.

**Suggested first slice:** *path/URL* + *WMS*. Neither needs credentials, neither changes the
pool contract, and together they cover a large share of "I can't get my data in" without opening
the database question at all.

### 42. Big question — has the platform actually met its founding goal?
> "big question: one goal was to analyze data and map it in the same platform. has the platform truly solved that goal. we should set a multiobjective multi step process cus it does not look entire fixd and clear that this moment."

**UPDATE 2026-08-09 — phases 1–2 shipped and then failed their first real use.** The chain
works and is tested, but the reporter could not complete it while holding the instructions.
**See item 67.** Phases 3–4 are on hold: there is no point extending a round trip that cannot
be found. The original observation — *"it does not look entirely fixed and clear"* — turned out
to be about discoverability, and it was right.

Not a defect. The reporter is questioning whether "analyse **and** map in one platform" has been
achieved, and observing that the current state "does not look entirely fixed and clear". The ask
is for a **multi-objective, multi-step process** — i.e. an explicit plan with stated objectives
and stages, not another list of fixes.

**This should be answered honestly rather than optimistically.** An initial read of the evidence
already in this backlog, to be checked before it is relied on:
- The two halves are **wired but not integrated**: statistics and spatial each have a registry
  (`statistics.R`, `algorithms.R`) and both drop results into shared pools, but nothing takes a
  *model* and puts it *on the map* — no predict-to-raster, no join of a model result back to the
  features it came from. That is arguably the exact thing "analyse and map in one platform" means.
- Items 37–40 say the map side is still short of basic GIS interaction.
- Round-4 item 33's migration found that **three statistical screens could not produce a result
  at all**, which is a fair indicator that breadth has been outrunning depth.

**Next step:** treat this as its own planning exercise with the reporter, not as a task to
start. It likely reframes the priority order of everything else in this file.

**SEQUENCING DECIDED by the reporter 2026-08-05:**
> "first, we fix the GIS side before even begin working on the intersection where mapping and
> modeling happens under one roof."

So **items 37–40 (and 39's symbology) come first, and item 42's integration work does not start
until they are done.** This is the right call and worth recording *why*, so it is not quietly
reversed later: the analyse-and-map intersection is built *on top of* the map — a
predict-to-raster result or a model joined back to its features is only useful if you can then
style it, click it, and inspect its attributes. Building the intersection on a map that cannot
yet identify a feature would mean producing results no one can interrogate. GIS first is
therefore a dependency order, not a preference.

### 43. A consistent image viewer across every screen with plots
> "screens with multiple image view like cv and other images, perhaps we can add the slider across the screens (I i think it would be more flexible oif it was across all screens. also, a zoom button cus when you open the plot, it re-renders, which is good then overlapping texts gets spaced. more like what zoo button does in rstudio. also, we could add setting dimensions too."

Three related controls, wanted **on every screen that renders a plot**, not per-screen:
1. **Slider** to step through multiple images (cross-validation folds, per-class plots, etc.).
2. **Zoom button** — explicitly "like what the zoom button does in RStudio". The reporter has
   already worked out *why* it helps: re-rendering at a larger size **re-spaces overlapping
   text**, because R redraws rather than scaling a bitmap. So this must trigger a genuine
   re-render at the new size, not a CSS transform — a CSS zoom would enlarge the overlap
   instead of fixing it.
3. **Set dimensions** — explicit width/height for the render.

- **This belongs in the global layer, not in ~35 modules.** The precedent is already established
  and recorded: the PNG download button is injected once by a JavaScript overlay over every
  `.shiny-plot-output` (UX rule 12 exists precisely to stop modules adding their own), and the
  "Running…" pill is one global CSS rule reaching all screens. The same approach applies here.
- **Fits with** `ea_plot_appearance()` (`helpers.R`), which is where plot-level options already
  live, and with round-4 item 26's view work.
- **Watch out:** CLAUDE.md gotcha 21 — a panel must not depend on the store its own controls
  write to, or every keystroke rebuilds the panel and wipes the field mid-edit. A dimensions
  input is exactly that shape.

### 44. Documentation debt from this round
Items 37, 38, 40 all change the map's behaviour, so `spatial_design_reference.md` and
`DESIGN.md`'s layout idiom need updating **with** the work, not after — the discipline round-4
item 24 exists to enforce.

### 45. Theme picker reachable before any analysis — **DONE (v0.10.6)**
> "while at it. can you add the theme to the settings, that way the user can change the theme
> upon the software loading before even going to the analyses."

The theme picker existed only in the **workspace View menu** (`mod_workspace.R:411`), which is
not reachable until a project is open. So the appearance could not be set from the Projects
screen — the app's *first* view — and a user on a bright screen or a dark room had to open a
project first just to fix the contrast.

**Fix:** a **Theme** section in the Settings drawer, placed **first** in the panel. The Settings
gear sits in the topbar with no `tb-ws` / `tb-coanalyst` class, so unlike Undo/Reset/Co-Analyst
it is *not* hidden on the Projects screen — which is exactly what makes the theme changeable
"upon the software loading". Six swatches, one per `ea_palettes` entry, each showing that set's
own `paper` plus a dot in its `forest` brand colour (paper alone made the two light themes
indistinguishable).

**Design notes worth keeping:**
- **One implementation, two entry points.** Both the View menu and the new section call the same
  `eaSetTheme()`. No second mechanism, no server round-trip — it sets `<html data-ea-theme>` and
  writes localStorage, so it applies instantly and survives a restart.
- **The selected marker must be client-side.** `ui.R` only sets `data-ea-theme` when localStorage
  already holds a value, so the **server cannot know** which theme is active at render time. A
  new `eaMarkTheme()` resolves it in the browser and runs on load, on every `openSettings()` (the
  panel is built once and reused, and the View menu can change the theme behind its back), and
  after every `eaSetTheme()`.
- **The default name is injected from R** (`names(ea_palettes)[1]`) rather than hardcoded as
  `'forest'`, so adding or reordering a palette cannot silently break the marker.
- **The picker is fully tokenised** — no hex anywhere in its CSS — so the picker re-themes along
  with everything else (gotcha 31).

**Verified:** build OK (a stray quote inside `HTML()` would have failed the parse — gotcha 1);
all six palettes render a button with the right `data-theme-name` and a working `onclick`; the
gear carries no screen-hiding class, so it is present on Projects; Theme is the first section;
`eaMarkTheme` is defined and called from all three places; no hardcoded hex in the picker CSS;
the View menu still uses the same function. App serves HTTP 200.
**Not verified here:** appearance (no browser automation) — worth an eyeball.

**Note:** a **black & white theme is still open** as round-4 item 25. This item only moves where
the picker lives; it does not add a palette.

### 46. Launching without a terminal — the biggest barrier for non-technical users
> "many non technical users have no idea on how to use the terminal, what is a very simple way
> to allow them to get the app to work without opening the terminal?"

**This is a fair hit, and the problem is worse than "the install needs a terminal".**

**Grounded facts, checked 2026-08-05:**
- The only documented way in is `iwr -useb https://easyanalysis.dev/install.ps1 | iex`
  (`install.ps1:5`), which requires opening PowerShell and pasting a command. `install.sh` is the
  same on macOS/Linux.
- **`install.ps1` creates no shortcut of any kind** — no Desktop, no Start Menu, no `.lnk`.
  Verified by grep: there is no `WScript.Shell`, no `Desktop`, no `StartMenu` anywhere in it.
- **Therefore the terminal is not a one-off cost — it is required on every single launch.** A
  user who installed successfully last week has no way to reopen the app except finding and
  pasting that command again. That is the more damaging half, and it is invisible in the
  install docs because they only describe the first run.
- `install.ps1:141` tells the user "Keep the R window open while you work; close it to stop the
  app", so the console window is currently also the app's only stop control.

**The options, cheapest first:**

| # | Approach | Cost | What it fixes | Honest downside |
|---|---|---|---|---|
| **A** | **Create shortcuts during install** (Desktop + Start Menu `.lnk` → the launcher) | ~15 lines of PowerShell (`WScript.Shell`) | **Every launch after the first** | Does nothing for the first install |
| **B** | **A downloadable `EasyAnalysis-Setup.bat`** the user double-clicks instead of pasting | Small; wraps the existing `install.ps1` with `-ExecutionPolicy Bypass` | The **first** install | Browsers flag `.bat` downloads; SmartScreen warns on unsigned files |
| **C** | **A real `.exe` / `.msi` installer** (Inno Setup or NSIS) | A build pipeline + **code-signing certificate (recurring cost)** | Everything; matches what non-technical users expect | Unsigned, it shows "Windows protected your PC", which is *scarier* than a terminal. Signing is the actual cost, not the packaging |
| **D** | **Electron / Tauri desktop wrapper** | Large | Everything, plus a native feel | A second big toolchain, and R still has to be installed underneath. Overkill for the problem |
| **E** | **Hosted version** (no install at all) | Deployment + running cost | Everything, for users who can use a hosted app | The project deliberately went **LOCAL-FIRST** because the browser build was too slow and shinyapps.io's RAM limits broke LiDAR. Viable only for small tabular work |

**Recommendation: A + B, in that order, and treat C as the real answer later.**

- **A is the highest value per line of code in this entire backlog.** It converts a
  paste-a-command-every-time app into a double-click app for everyone who has already installed,
  and it is a change to a script that already runs. Do it first.
- **B** removes the terminal from the first install too, and reuses `install.ps1` unchanged.
- **C** is what a non-technical audience actually expects, but its cost is the **certificate**,
  not the installer — an unsigned `.exe` produces a security warning that will lose more users
  than the terminal does. Do not start C until signing is settled.
- **D** and **E** are recorded to be dismissed, not pursued: D duplicates the install problem it
  claims to solve, and E contradicts the local-first decision.

**One design consequence to decide with A:** if a shortcut launches the app with the console
window hidden (nicer), the user loses the only way to stop it — `install.ps1` currently relies on
"close the R window". So a hidden-console launch needs a **Quit** control in the app itself, or a
tray icon. **Recommendation: keep the console window visible in the first version** — an ugly but
working stop beats a tidy launch with no way out. Revisit once the app has its own Quit.

**Also worth fixing while in there:** the landing page and `README.md` document only the paste-a-
command route, so even after A and B exist, a first-time visitor would still be sent to the
terminal. The docs are part of this item, not a follow-up.

### 47. A Quit button and a Stop button — and why they unblock the shortcut (item 46)
> "maybe another button to end or close the app. we also dont have a button to stop analyses.
> so maybe we create the shortcut? with buttons in the app?"

**Both observations are correct, and pairing them with item 46 is the right instinct** — the Quit
button is precisely what *unblocks* a clean desktop shortcut. Item 46 recommended keeping the
console window visible because it is the only way to stop the app; a Quit button removes that
constraint, so the shortcut can then launch with the console hidden. **Do 47 before 46's
shortcut, not after.**

**Grounded facts, checked 2026-08-05:**

| Control | State |
|---|---|
| Quit / close the app | **Does not exist.** No `stopApp()` anywhere in the codebase |
| Stop a running job | Exists in **exactly one module** — `mod_algo.R`, via `compute_worker.R` |
| …and only sometimes | `mod_algo.R:233` routes to the worker only when `cells > 2e6` (`ea.worker_min_cells`) and the input is not LAS. Below that it runs in-process and **cannot be stopped** |
| Stop a statistical analysis | **None at all.** `mod_stat.R` never touches the worker, so all **9 migrated screens** plus every hand-written model module run uninterruptibly |

**These are two very different jobs — do not estimate them together.**

#### Quit — genuinely small
`stopApp()` ends the process. Three things it must get right:
1. **Kill the worker too.** `compute_worker.R` holds a `callr` R session. Quitting without
   calling `ea_worker_shutdown()` **leaks an orphan R process** that keeps running with no UI
   attached. This is the one real trap in an otherwise easy change.
2. **Be honest about the browser tab.** The server cannot close it; `window.close()` only works
   for script-opened windows and the launcher opens the browser itself, so it will most likely be
   refused. Show a plain "EasyAnalysis has closed — you can close this tab" state instead of
   pretending.
3. **Confirm first.** Projects autosave, so the risk is low, but quitting mid-fit should still ask.

#### Stop — harder, and the reason is structural
**A Stop button on an in-process fit can never be clicked.** Shiny is single-threaded
(CLAUDE.md gotcha 29): while a fit is running the server cannot receive input, so the click never
arrives. That is *why* `compute_worker.R` exists and why `mod_algo.R` routes heavy work out.
So "add a Stop button" to the analyses is **not a UI change** — it means routing fits through the
worker.

**The good news: statistics are a better fit for the worker than rasters were.** A fit is
essentially a pure function of a data frame, so there is nothing like the "never hand the worker
a raster's `sources()` path" trap. And `ea_worker_run(app_dir, id, inputs, params, ...)` already
takes an **id**, not a closure — so the worker re-sources the registry and looks the spec up,
which is exactly what a `statistics.R` entry needs. The existing design already anticipated this.

**One change in `mod_stat.R` covers all 9 migrated screens at once** — the registry paying off
again, in the same way cancellation was one change instead of 33 for algorithms (item G29).

**Recommended sequencing:**
1. **Quit button** — small, and unblocks the shortcut.
2. **Shortcut with hidden console** (item 46 part A), now safe to do.
3. **Stop for statistical analyses** — route `mod_stat.R` fits through the worker; 9 screens in
   one change.
4. **Hand-written model modules** — leave them. They are being migrated onto the registry
   anyway, and each gains Stop for free when it arrives.

**Design suggestion worth considering — one GLOBAL Stop, not one per screen.** The `#ea-busy`
"Running…" pill already tells the user something is running, app-wide, from a single CSS rule.
Putting Stop **there** gives one control for the whole app instead of a button on ~40 screens,
and it matches how the pill was already solved.
**But it needs one hard rule:** the Stop must appear **only when the running job is actually
cancellable** (i.e. it is in the worker). An always-visible Stop that silently does nothing
during in-process work is worse than no Stop — it reads as broken, and it would be the second
time a control looked dead because Shiny was busy.

### 48. Discoverability — sitemap, robots, llms.txt and structured data — **DONE (v0.10.8)**
> "please create a sitemap and other things for llm and others to find the tool."

**Three gaps, one of them actively misleading:**

1. **No `sitemap.xml` and no `robots.txt`** anywhere in `landing/`. Nothing told a crawler what
   pages existed or that they were welcome.
2. **`llms.txt` existed but was NOT SERVED.** It sat at the repo root; `landing/` is the deploy
   root (`vercel.json` `outputDirectory: "."`), so `easyanalysis.dev/llms.txt` was a 404. The one
   document written specifically so assistants could describe the tool was unreachable.
3. **Worse, its content was wrong.** It described the **deprecated WebAssembly build** as the
   product — "runs entirely in the user's web browser", "R compiled to WebAssembly", "there is no
   analysis backend", "first visit takes 3-5 minutes while the R environment downloads". The app
   has been **local-first** for a long time. It also still said "AI Co-Pilot", renamed to
   Co-Analyst in v0.10.2. So the file most likely to be quoted by an assistant was describing a
   product that no longer exists.

**Fix:**
- **`landing/sitemap.xml`** — the four public URLs, in the **extensionless** form, because
  `cleanUrls` is on and listing `.html` would point every crawler at a 308 (a redirect class that
  has caused trouble here before — round-3 item 16). `lastmod` is deliberately **omitted** rather
  than guessed: a stale or invented date is worse than none.
- **`landing/robots.txt`** — allows everything, points at the sitemap, and names AI crawlers
  **explicitly** (GPTBot, OAI-SearchBot, ClaudeBot, PerplexityBot, Google-Extended, Applebot-
  Extended, CCBot, Meta-ExternalAgent, Amazonbot, …). Several ignore `User-agent: *` for
  training/answering, so an explicit `Allow` is the only unambiguous signal. Being findable by
  assistants is the goal, and there is nothing on the site worth withholding.
- **`landing/llms.txt`** — rewritten from scratch to describe what the app actually is: local
  install, the real one-line commands, `127.0.0.1:7788`, projects on disk, Co-Analyst, the CRS
  catalogue, cancellable jobs — and it states plainly that the browser build is deprecated. The
  **root copy was deleted, not synced**: two copies of a discovery document is exactly how this
  one went stale.
- **Meta + structured data on all four pages** — `canonical` (extensionless), `robots`,
  OpenGraph and Twitter card, plus JSON-LD: `SoftwareApplication` on the home page (so an
  assistant can answer "what is it, what does it cost, what does it run on" without parsing
  prose), `TechArticle` on documentation and release notes, and `HowTo` on the walkthrough — the
  type distinction is what lets an assistant cite the *right* page.
- **`release-notes.html` is generated**, so its tags went into
  `landing/build-release-notes.mjs`, not the output file.
- **`vercel.json`** serves the three new files with explicit content types.

**Deliberately NOT done:** no `og:image`. There is no artwork in `landing/assets/` (only
`site.css`), and a reference to a non-existent image is worse than none — a social card would
render broken instead of plain. **Open follow-up:** make one, then add `og:image`/
`twitter:image` and switch the cards to `summary_large_image`.

**Verified:** files exist where they are *served*; no root duplicate remains; sitemap uses the
correct `sitemaps.org` namespace (the first draft had `sitemap.org`, caught by the check) and has
exactly one entry per real page with no `.html` forms; robots points at the sitemap and has no
`Disallow`; llms.txt no longer makes any of the four wasm-era claims and uses the current name;
every page has a canonical matching its real URL plus OG/Twitter tags; **all five JSON-LD blocks
parse** and carry the intended `@type`; `vercel.json` still parses and serves the sitemap as
`application/xml`.
**Not verified here:** live headers and crawler behaviour after deploy — worth checking
`easyanalysis.dev/llms.txt`, `/robots.txt` and `/sitemap.xml` return 200 with the right
content types once Vercel has picked the commit up.

### 46 (parts A + B) — **DONE (v0.10.10)**: Desktop shortcut and a double-click installer

Item 47's Quit button (v0.10.7) unblocked this, exactly as that entry predicted: the console
window was the only way to stop the app, so it could not be tucked away until Quit existed.

**A — shortcuts created during install (`install.ps1`).**
- Writes a small **local launcher** at `%LOCALAPPDATA%\EasyAnalysis\launch.ps1` and points
  Desktop + Start Menu `.lnk` files at it. It has to be a *generated* script: `install.ps1` is
  normally run via `iwr | iex`, so there is **no file on disk** for a shortcut to target.
- The launcher **skips the download and dependency steps** (both already cached) and just starts
  the app — that is what makes the second launch quick. `$App` and `$LibDir` are baked in at
  install time, but **R is re-resolved at run time**, so installing or upgrading a system R later
  does not break the shortcut.
- **Minimized, NOT Hidden.** Hidden looks tidier, but a failed start would then show the user
  absolutely nothing — and the v0.10.7 regression is a fresh reminder of how bad a silent failure
  is. Minimized keeps the window in the taskbar as an escape hatch.
- Shortcut creation is wrapped in `try/catch`: it **must never fail the install**, since the app
  works fine without one.
- The launcher guards both failure modes it can actually hit (no R, missing app files) and tells
  the user the one command that fixes it, rather than closing instantly.

**B — `landing/EasyAnalysis-Setup.bat`.** Double-click instead of pasting a command; it runs the
same `install.ps1`, so there is no second install path to maintain. `vercel.json` serves it as
`application/octet-stream` with `Content-Disposition: attachment` so browsers download rather
than display it.

**Docs (part of the item, not a follow-up).** The landing page now leads with **Download for
Windows** and keeps the one-liner below under "Prefer the command line?". It warns plainly about
the SmartScreen prompt (**More info → Run anyway**) — an unsigned download *will* trigger it, and
a user who is not warned reads it as "this is malware". It also stops saying "keep the terminal
open while you work", which Quit made untrue.

**Verified** (`verify_shortcut.ps1`): `install.ps1` still parses; the generated `launch.ps1`
parses and bakes in the right paths, re-resolves R, calls `launcher\run.R` and guards both
failure modes; a **real `.lnk` was created and read back** — it targets `powershell.exe`, points
at the launcher, is `-WindowStyle Minimized` and never `Hidden`, bypasses execution policy for
that process only, and quotes the path (needed: `%LOCALAPPDATA%` paths contain spaces); the
`.bat` fetches the real installer, handles failure and pauses; `vercel.json` forces the download.

**Still open on item 46:**
- **No custom icon.** No `.ico` ships, so the shortcut shows the PowerShell icon — functional but
  scruffy. Needs an icon file before it looks like a real app.
- **Windows only.** `install.sh` creates no `.desktop` entry (Linux) or `.app` (macOS).
- **Option C (a signed `.exe`/`.msi`) is untouched and still gated on a code-signing
  certificate.** The `.bat` reduces the terminal problem but does not remove the security prompt;
  only signing does.
- **Not verified end-to-end here**: this machine already has the app, so a genuine
  clean-machine install → shortcut → double-click → app opens run has not been done. Worth doing
  once on a fresh profile.

### 49. The app icon — shortcut, website favicon and browser tab — **DONE (v0.10.11)**
> "we can use the favicon for the custom icon."

Closes item 46's "no custom icon" follow-up — and uncovered that **the favicon was not working
anywhere either.**

**What was actually wrong (checked, not assumed):**
- `favicon.png` (369x369) and `easyanalysis-favicon.png` (677x369, the uncropped original) had
  been in the **repo root** since 2026-07-30. `landing/` — the deploy root — contained **no
  favicon at all**, and **not one page linked to it** (0 matches across all three static pages).
- So `easyanalysis.dev` served no icon and still 404'd `/favicon.ico`, despite a changelog entry
  claiming the favicon was "copied into the site root … and linked from the page `<head>` (also
  stops the `/favicon.ico` 404)". **That claim was false in the deployed site.**
- This is the **same failure as `llms.txt` (item 48)**: an asset added at the repo root, where it
  is never served. Twice now. **When adding a web asset, put it in `landing/` and confirm a page
  references it.**
- The **app itself** had no favicon either, so the tab at `127.0.0.1:7788` showed the browser's
  blank-page glyph.

**Fix — one piece of artwork, four destinations:**
- **`tools/make-icon.ps1`** builds `launcher/easyanalysis.ico` from `favicon.png` using
  `System.Drawing` (ships with Windows), so regenerating needs nothing installed. **Seven sizes**
  (16/24/32/48/64/128/256) because Windows picks per context — 16px in the taskbar, 32px on the
  Desktop, 256px in large-icon view; shipping only 256 makes Windows downscale badly. Output is
  **committed**, so the script only re-runs if the artwork changes.
- **The shortcut** (`install.ps1`) sets `IconLocation`. The `.ico` is **copied into `$AppHome`
  first**: a shortcut stores a *path*, so pointing into `$App` would break the moment a reinstall
  replaces that folder. Guarded — a missing icon must not fail the install.
- **The website**: `landing/favicon.ico` + `landing/favicon.png`, linked from all four pages. The
  release-notes tags went into **`build-release-notes.mjs`**, not the generated HTML, so they
  survive a rebuild.
- **The app**: `www/favicon.ico` + `www/favicon.png` (Shiny serves `www/` at the app root) linked
  from `ui.R` with **relative** paths — an absolute `/favicon.ico` would point at the wrong host
  when the app is served from `127.0.0.1`.

**Verified:** the `.ico` was parsed **byte by byte** rather than trusted — header reserved/type
correct, 7 entries, every one square, contiguous, in-bounds and carrying a valid PNG payload,
file length matching the last entry, with 16/32/256 all present and 256 stored as `0` per spec.
Windows loaded it back via `System.Drawing`. (Requesting 256px returns 128 — a known limitation
of that API with PNG-compressed entries, not a defect: the byte-level parse confirms the 256
entry is present and well-formed.) All four pages link both forms; the generator carries them;
`ui.R` uses relative paths; the shortcut sets `IconLocation`, copies the file out of `$App` and
guards its absence. Build OK, `check_ui_js` PASS, app serves HTTP 200, shortcut checks still pass.
**Not verified here:** how the icon actually looks in Explorer and on a browser tab — no
browser/shell automation. Worth an eyeball after installing.

**Note:** `easyanalysis-favicon.png` (the uncropped 677x369 original) is kept at the repo root as
the source artwork. It is **not** served and should not be linked.

### 46 (docs) — **DONE (v0.10.12)**: both install routes documented everywhere
> "we keep terminal runs for now and add that shortcut. if its done. keep the documentation"

**Decision recorded: the terminal route STAYS.** The download and the shortcut are additions, not
replacements — the one-liner is the only route on macOS and Linux, and it is what CI, developers
and anyone scripting an install will use. Nothing was removed from any page.

**The gap this closed.** v0.10.10 updated `landing/index.html` only. The two pages users are
actually *sent to* were left describing the old world:
- `how-to-use.html` still said **"Keep the terminal window open while you work — closing it stops
  the app. To start it again later, run the same line."** Both halves were untrue by then: Quit
  (v0.10.7) closes the app properly, and the Desktop shortcut (v0.10.10) is how you restart it.
- `documentation.html`'s Installation section never mentioned the shortcut or the download.
- `README.md` — what a GitHub visitor sees first — had **no install path at all**, only
  `shiny::runApp()`. A non-technical reader arriving from the repo had nowhere to go.

**Now, on all four:** the double-click download first (Windows), the terminal one-liner kept
below it for every platform, the shortcut explained for restarting, and Quit for closing. The
SmartScreen prompt is spelled out with the remedy (**More info → Run anyway**) and the reason —
an unsigned installer always triggers it, and an unwarned user reads it as malware. Each page
states plainly that Desktop shortcuts are **Windows-only for now**.

**Verified:** no "keep the terminal open" text survives anywhere; all four docs reference the
installer, the `.bat` and the shortcut; the `install.sh` route is still present on all four
(the "keep terminal runs" instruction); page and icon checks still pass.

**Lesson worth keeping:** the landing page is not the documentation. A change to how the app is
installed or closed has **four** places to update — `index.html`, `documentation.html`,
`how-to-use.html`, `README.md` — and the two most likely to be read are the ones easiest to
forget.

### 46 (part B) — **REVERTED (v0.10.13)**: the downloadable `.bat` is removed
> "remove the bat from the website. windows blocks it and it makes ithe tool look like scam"
> — with https://support.microsoft.com/en-US/Windows/Security/Threat-Malware-Protection/smart-app-control-has-blocked-an-app-with-a-dangerous-file-extension

**My recommendation in item 46 was wrong, and this is the correction.** I costed option B
(a double-click `.bat`) as cheap and safe, and I explicitly flagged **SmartScreen** — the
"Windows protected your PC" prompt that a user can click through via *More info → Run anyway*.

**I missed Smart App Control**, which is a different and stricter mechanism: on Windows 11 it
blocks `.bat` **by file extension**, as a category. There is often **no "run anyway" path at
all**. So the option sold as *"the way to avoid scaring non-technical users"* produced a harder
block than the terminal it replaced, and — worse — one that reads as a malware warning about the
tool itself. Reputational harm, not just friction.

**The lesson, which generalises past this file:** "unsigned installers show a warning the user can
dismiss" was the wrong mental model. Windows has **several** independent gatekeepers
(SmartScreen, Smart App Control, Attachment Manager / Mark-of-the-Web, antivirus), and they differ
in whether they can be overridden at all. Checking one and generalising was the error. **Anything
users download to run must be checked against Smart App Control, not just SmartScreen.**

**Decision, confirmed by the reporter: exactly two supported routes.**
1. **The terminal one-liner** — installs everything; the only route on macOS and Linux.
2. **The Desktop / Start Menu shortcut** — *created by that install*, so it is never downloaded
   and never crosses a security boundary. This is what removes the terminal from daily use, which
   was always the larger half of the problem (the terminal was needed on **every** launch).

Note the shortcut survives this revert untouched: a `.lnk` written locally by a script the user
already chose to run is not subject to download blocking.

**Removed:** `landing/EasyAnalysis-Setup.bat`, its `vercel.json` header rule, and every reference
across `index.html`, `documentation.html`, `how-to-use.html` and `README.md`. All four now lead
with the one-liner and explain the shortcut for restarting.

**Item 46's option C is unaffected and remains the real long-term answer** — a signed `.exe`/
`.msi`. Note this revert *raises* its value: signing is what satisfies these gatekeepers, and it
is now clearer that no unsigned downloadable artefact avoids them.

**Verified:** no `.bat` reference remains in any shipped file; `landing/` contains no `.bat`; all
four docs carry both `install.ps1` and `install.sh` and describe the shortcut; the SmartScreen
"Run anyway" wording is gone (it described a prompt that no longer applies to anything we ship).

### GIS parity Step 0 — **DONE (v0.10.13)**: the attribute table shows every feature

First step of the 37-40 sequence. Small, but a hard prerequisite for items 38 and 40.

**`attr_dt` was capped at `utils::head(df, 200)`** (`mod_workspace.R`). Two problems:
1. **Invisible truncation.** The table simply ended at row 200 with nothing saying more existed,
   so a 5,000-feature shapefile silently looked like a 200-feature one.
2. **It would have broken selection.** Row *i* of this table is feature *i* of the layer, so with
   the cap in place **feature 201 onward could never be selected, highlighted or deleted** — the
   delete in item 38 would have been quietly unable to reach most of a real layer.

The cap was also unnecessary: the table is already `server = TRUE`, so DT pages, sorts and
filters **on the server** and ships only the visible page. The cap was limiting the *data*, not
the *transfer*.

**Changed:** full data frame instead of `head(df, 200)`, and `selection = "multiple"` enabled now
— items 38/40 need it and it costs nothing at this point.

**Verified, including the assumption everything downstream rests on:**
- The cap is gone from the *code* (checked with comments stripped — the new comment mentions
  `head(df, 200)` while explaining the change, and a naive grep matched the prose).
- A 250-feature layer keeps all 250 rows, with a **control** proving the old shape really did drop
  50 and that feature 250 was previously unreachable.
- **Row i IS feature i**: `st_drop_geometry()` preserves both row count and row order, and
  indexing the `sf` object by table positions `1, 7, 199, 200, 201, 250` returns exactly the
  matching features — including the two past the old cap. This is what makes Step 2
  (row → map highlight) pure indexing with no spatial hit-testing.
- `testServer(workspaceServer)` runs with a 250-feature layer bound; build OK; app serves HTTP 200.

**Not verified here:** that DT returns *original-data* indices in `input$attr_dt_rows_selected`
when the table is sorted or filtered. It is DT's documented behaviour and Step 2 depends on it, so
**confirm it with a live click before building the delete** — sorting the table and selecting a
row is the one-minute check.

**Next:** Step 1, the selection model (`reactiveVal(list(layer=, rows=))`), then Step 2.

### 50. Sleeping the computer killed the app with no way back — **DONE (v0.10.14)**
> "when the computer sleeps, the app disconnects and there's no way to restart the app."

**Confirmed: there was no disconnect handling anywhere in the app.** Shiny's default response is
a grey `#shiny-disconnected-overlay` that says the connection was lost and offers **nothing** — no
reload, no explanation, no route back. So a laptop lid closing left the app looking permanently
broken, and the only recovery was to find and re-run the launcher.

**Why it happens:** sleeping suspends the network stack, so the websocket between the browser and
the local R process dies. The **R process itself normally survives** — which is what makes this
fixable, because reloading the page reconnects to a server that is still there.

**Fix:** a replacement panel that says what happened and gives a way back. Shiny's own veil is
hidden, since two overlays would stack and its one is the dead end.

**It probes the server before advising, because the two cases need opposite remedies:**
- **R still running** (the usual case after sleep) → "Reconnect" reloads the page and work
  continues.
- **R has stopped** → reloading can never work; the panel says to start EasyAnalysis again from
  the Desktop shortcut and reopen the project.

The probe uses `cache: 'no-store'` — a cached 200 would make a dead server look alive and send the
user round a loop that cannot succeed.

**One collision worth recording.** Quit also drops the websocket, so the disconnect panel would
have fired on a deliberate close — and since it sits at `z-index` 100001 against the quit veil's
100000, it would have **covered the "has closed" message and told the user to reconnect to
something they had just closed.** `eaQuitApp()` now sets `window.eaQuitting` *before* firing the
quit input, and the disconnect handler returns early on it. The verification checks the z-index
ordering specifically, so the guard is proven load-bearing rather than assumed.

**Nothing is lost on reconnect:** projects autosave to disk, so reopening restores the datasets,
the active layer and the last view. Note the session-end handler still clears the in-RAM pools on
disconnect (by design, ARCHITECTURE §9) — so after a reconnect the user reopens their project
rather than finding it already loaded. That is a deliberate memory trade-off, not a bug.

**Verified:** panel present and hidden until `.on`; fully tokenised (no hex, so it themes);
Shiny's overlay suppressed; wired to `shiny:disconnected` and cleared on `shiny:connected`; the
probe is cache-busting; the quit flag is set *before* the quit input fires; disconnect really does
layer above quit. `check_ui_js` PASS, build OK, app serves HTTP 200.
**Not verified here:** an actual sleep/wake cycle — no way to suspend this machine from a test.
**Worth checking:** sleep the computer, wake it, and confirm the panel appears and Reconnect works.

**Note:** a literal `"` inside the new JS comment broke the R parse on the first run — CLAUDE.md
gotcha 1, caught loudly by the build. Recorded because it is the second escaping trip-up in this
file in two days (gotcha 1b was the silent `\n` variant).

### 51. Tables of the user's own data were limited to 100 rows a page — **DONE (v0.10.15)**
> "i tried to do the DT sorting. so I loaded a data, but I can only see 100 rows max."
> "i was looking at the attribute table. maybe for view datatable, we should have full tabe too"
> "yes, ALL is good"

**A second, independent limit that Step 0 did not remove.** Step 0 took the 200-row cap out of the
*data*; this was a cap on the *page size*. **DT's default `lengthMenu` is 10/25/50/100**, so the
largest page anyone could ask for was 100 rows — which reads as "this table only holds 100",
and there was no way to ask for more.

Three tables show a user's own data, and each had a problem:

| Table | Where | Problem |
|---|---|---|
| Attribute table (`attr_dt`) | `mod_workspace.R` | page size capped at 100 (data cap fixed in Step 0) |
| Data view (`dt`) | `mod_workspace.R` | **still had `head(df, 200)`** — Step 0 missed it — *and* the page cap |
| View Data modal | `server.R` | never row-capped, but the same 100-row page cap |

**Fix:** `ea_dt_len()` in `helpers.R` — one shared page-size menu offering
**10 / 25 / 50 / 100 / 500 / 1000 / All**, used by all three. Put in `helpers.R` rather than
duplicated, since a fourth data table will want it too.

`All` (DT's `-1`) is offered **last on purpose**: these tables are `server = TRUE`, so All really
does ship every row. It should be a deliberate choice on a large layer, not something to stumble
into by picking the biggest number.

**Only for data tables.** Fixed result tables (metrics, coefficients) use `dom = "t"` with no
pager and must not get this — noted in the helper.

**Verified:** neither workspace table calls `head()` any more (checked with comments stripped);
all three use the shared menu; the menu really does offer sizes past 100 and All; a
**control** confirms the old shape capped at 200 rows with DT's default menu; `testServer` runs
with a 1,200-row table and a 1,200-feature layer bound. `check_ui_js` PASS, serves HTTP 200.

---

### GIS parity Step 1 — **the sorting assumption is CONFIRMED (tested by the reporter)**
> "when I select a row, and sort, then sort again, that row stays selected. both sort for up and
> down, the selection remains the same for the selected row… assume its ascending order and i
> clicked row 1, when i sort, i dont see it. so i sort to descending, i select row 1 (which is
> different), when i sort back to ascending order, the original row one is still selected."

**This is the answer Step 2 was waiting on, and it is the good outcome.** The selection is bound
to the **underlying data row**, not to the screen position: a selected row stays selected through
a re-sort, moves with its data, and two rows selected under different sort orders both persist as
distinct selections.

So `input$attr_dt_rows_selected` returns **original-data indices**, and because Step 0 proved row
*i* of the table is feature *i* of the layer, **Step 2 can index the `sf` object directly** —
`vector_pool[[layer]][idx, ]` — with no lookup table and no spatial hit-testing. That is the
cheapest possible form of the feature, and it is now confirmed by observation rather than assumed
from documentation.

**One consequence worth designing for:** selections *accumulate* across sorts. That is correct
behaviour for multi-select, but it means the user can build a selection they cannot see all of at
once, so the UI needs a visible **selected count** and a **Clear selection** control. Fold both
into Step 2.

---

### 52. Make the attribute table dockable, with window controls — **PARTLY DONE v0.11.5**
> "I think we should make the attribute table dockable. and in the header, instead of just
> attribute table, use the state like dock attribute tabe or undock. for the table itself, we can
> have the close, minimize (which docks it), maximize."

The attribute table currently lives in a fixed dock at the bottom of the Map view
(`mod_workspace.R`, "Step 6: attribute-table dock"). Reading a wide table in a short strip is
cramped, which is what prompted this.

**Asked for:**
- **Dock / undock** the panel, with the header naming the *action* (i.e. it reads "Undock" while
  docked), not just the panel.
- **Window controls on the table itself:** close, minimize (which docks it), maximize.

**Notes before building:**
- **Maximize is the highest value and the cheapest** — a full-canvas attribute table solves the
  cramped-strip problem on its own. Worth doing first and possibly on its own.
- **Undock implies a floating, draggable, resizable panel**, which is a genuine step up: it needs
  position/size state, a drag implementation, and it must not fight the workspace CSS grid. The
  `.ea-pop` reusable hover panel already exists (UNIFIED_WORKSPACE.md) — **check whether it can
  carry this** before writing anything new.
- **Interaction with items 38/40:** the table becomes a selection surface, so the same panel must
  stay usable while clicking the map. A floating panel that covers the map would fight
  click-to-identify — so if undocked, it must be movable *and* the map must stay reachable.
- **State belongs in the project**, alongside the last view, or the layout resets on every reopen.
- **Sequencing:** this is UI polish over the same panel Steps 2-4 are about to change. Doing it
  *after* Step 2 avoids rewriting the panel twice — but Maximize alone could land at any time.

### GIS parity Steps 1 + 2 — **DONE (v0.10.16)**: select a row, see it on the map
> "you know how we can click on a attribute in the attribute table and it gets highlighted in the map.."

**Step 1 — the selection model.** One `reactiveVal(list(layer=, rows=))`, read by the map's render
pass, the highlight proxy and the toolbar. Items 38 and 40 are two directions of this same link,
so it exists once; building them separately would produce two mechanisms that disagree about what
is selected.

**Step 2 — row → map highlight**, and it really is pure indexing. The reporter's own test
established that DT reports **original-data indices**, not screen positions (a selected row
survives a re-sort and moves with its data), and Step 0 established that row *i* is feature *i*.
So the layer is subscripted directly — `vector_pool[[layer]][rows, ]` — with **no lookup table and
no spatial hit-testing**. Points, lines and polygons each get an appropriate highlight.

**The design tension, resolved as planned.** The highlight is applied **twice, from one source**:
- by **`leafletProxy`** when the selection changes, so picking a row does **not** rebuild the map
  (slow with a large raster underneath);
- inside **`renderLeaflet`**, `isolate()`d, so a map rebuilt for any other reason comes back with
  the highlight still on it — proxy calls are lost when the element is re-created (gotcha 23).

Both read the same `.sel_sf()`, so they cannot drift, and the highlight has its own `ws_sel`
leaflet group so clearing it never disturbs the data layers.

**Three failure modes handled deliberately:**
- **Deselecting the last row clears the map** — `ignoreNULL = FALSE`, or the highlight would
  stick after the table was emptied.
- **Switching layer drops the selection.** Row numbers belong to one layer; carried across, they
  would highlight arbitrary features of the next one.
- **Stale/out-of-range rows are clamped**, so a selection held while a layer is edited or replaced
  cannot subscript out of bounds and blank the map.

**Selected count + Clear**, in the dock header, shown only while something is selected. Not
cosmetic: selections **accumulate across sorts and pages**, so without a count a user can hold a
selection they cannot see all of at once. Clear works by clearing the *table*, which then drives
the model through the same observer — so the two can never disagree.

**Verified** (`testServer`): selecting rows 3/17/250 highlights **features 3, 17 and 250** —
confirmed by id, including one past the old 200-row cap; output is WGS84 for leaflet; deselecting
empties it; switching layers clears it; out-of-range rows `(1, 99, -4)` on a 3-feature layer yield
exactly feature 1; polygons keep polygon geometry; Clear empties the model; the chip is absent
with nothing selected and shows "2 selected" with Clear when two are. Source checks confirm the
proxy path, the isolated render path, one shared `.sel_sf()`, and the dedicated group.
`check_ui_js` PASS, serves HTTP 200.
**Not verified here:** the highlight's appearance on a real map — worth an eyeball that the amber
reads clearly over both light and satellite basemaps.

**Next:** Step 3 — map click → identify (the direction that needs geometry: transform the click
out of WGS84 into the layer CRS, then `st_intersects` / `terra::extract`), writing into this same
selection model so the table highlights in response.

---

### 53. Citation — **DONE (v0.10.16)**
> "document the citation… my name: first: Tim, Middle: Casanda, Surname: Gibson. So to fix the
> citation properly."

The documentation's *How to cite* section was a **placeholder** — "A formal citation file is being
prepared" — and there was **no `CITATION.cff`** anywhere.

**Added `CITATION.cff`** at the repo root, so GitHub shows a **Cite this repository** button
offering APA and BibTeX, and Zenodo/reference managers can read it.

**Name handling, recorded because it is easy to get wrong:** CFF has **no middle-name field**. The
spec puts *all* given names in `given-names`, so `given-names: "Tim Casanda"` /
`family-names: Gibson` is correct and renders as **Gibson, T. C.** `name-particle` is for
particles like "van"/"de" and must **not** be used for a middle name.

**Also added:** full APA + BibTeX blocks on the documentation page (with copy buttons), the same
citation in `llms.txt` so assistants quote it correctly, and a *How to cite* section in
`README.md`.

Every citation block says to **substitute the version actually used** rather than hardcoding one
silently — the version is in Help ▸ About and the status bar.

**Also states, in all three places, that citing the tool does not replace citing the method** —
several screens implement published methods that are listed on the app's References screen.

**Fixed while here:** `README.md` still called the product **SimpleAnalysis** (3 places) and the
assistant **AI Co-Pilot** — both renamed long ago. A README titled SimpleAnalysis directly
undermines a citation for EasyAnalysis, so it was corrected.

**Open, not invented:**
- **There is no `LICENSE` file** in the repository and no licence stated anywhere. That is an
  owner's decision, not one to guess, so `CITATION.cff` deliberately omits the `license` field.
  Worth settling — without a licence, others technically have no right to use or redistribute the
  code, which sits awkwardly with "free" on the landing page.
- **No DOI or ORCID.** Neither was invented. A Zenodo release would mint a DOI and make the
  citation permanent.
- **The stale name persists in internal docs** (ARCHITECTURE.md, DESIGN.md, MEMORY.md,
  spatial_design_reference.md, SPATIAL_TOOLS_REFERENCE.md, R_COMMANDS_REFERENCE.md,
  shinylive_poc/app.R). Not swept here: some occurrences are historical records where a rename
  would falsify the log.
- **`CITATION.cff`'s `version`/`date-released` are manual** and need bumping with `APP_VERSION`
  when a release is worth citing.

### Step 2 FOLLOW-UP — the highlight never appeared; fixed in v0.10.17
> "i am clicking the attribute in the table but I cant see it being identified on the map with red"
> "selecting shape file should get the make the border red"

**My design error, and it is the trap this very file documents.** Step 2 shipped with the
highlight applied two ways: by `leafletProxy` when the selection changed (for speed), and inside
`renderLeaflet` wrapped in `isolate()` (as a fallback for a rebuilt map).

**That pairing cannot work here**, and gotcha 23 says why *three lines below the code I wrote*:
`leafletProxy` calls are **silently dropped** for this map, which is exactly why every other layer
is built in one atomic pass inside `renderLeaflet`. So the live path was the unreliable one, and
`isolate()` meant the reliable path never re-ran. Net effect: **nothing ever drew.**

The server logic was never wrong — a debug run on a realistic layer (5 polygons in **EPSG:3067**,
as a real shapefile would be) confirmed `.sel_sf()` returned exactly features 2 and 4, correctly
reprojected to 4326 with a sensible Finnish bbox. The fault was purely in **delivery**.

**Fix:** drop the proxy entirely and make the render pass a **real reactive dependency**. Selecting
a row now rebuilds the map, which is the same one-atomic-build rule every other layer here already
follows. It costs a redraw per selection — accepted deliberately: **a highlight that is always
right beats one that is fast and sometimes invisible.** If that redraw ever becomes a problem on a
huge raster, the answer is to make the *map* cheaper to rebuild, not to reintroduce a mechanism
this map is documented to drop.

**Colour changed to red**, as asked, and carried by the **outline** rather than the fill: the layer
palette is green, so red is the strongest contrast, and a heavy border survives satellite imagery
where a translucent fill washes out. Fill is kept light (0.18) so the selected feature is still
visible underneath — selecting a polygon should not hide what you selected. Polygons get a
4px border, lines a 5px stroke, points a red ring. The count chip in the dock header matches.

**Verified:** the isolated render and the proxy observer are both gone (control checks assert the
old shapes are absent); the render pass draws the selection live; red with the outline weights
above; and a regression run still returns features 2 and 4 reprojected 3067→4326, with the map
rendering cleanly while a selection is active. `check_ui_js` PASS, serves HTTP 200.

**Lesson, worth generalising:** when a codebase documents that a mechanism is unreliable in a
place, do not use it there *even as an optimisation* — and never let the reliable path be the
isolated one. A fallback that cannot fire is not a fallback.

---

### 54. Right-click menu on the attribute table — **OPEN, not started**
> "can we add a right click function on the attribute table to zoom to attribute. like how arcgis
> does it. more like some functions. edit attribute, add attribute, zoom to selected attributes"

The ArcGIS/QGIS idiom: right-click in the attribute table for actions on the selection.

| Action | Depends on | Notes |
|---|---|---|
| **Zoom to selected** | Steps 1-2 (**done**) | Cheapest and most useful. `sf::st_bbox()` of `.sel_sf()` → `fitBounds`. Buy: it is the natural completion of selection, and needs no new state. |
| **Edit attribute** | an editing model | The table is currently read-only. DT supports `editable`, but a write-back must go to `vector_pool` and needs undo — same mechanism as item 38's delete and item 32's multi-step undo. **Do not invent a second one.** |
| **Add attribute** | schema editing | Adds a *column* to the layer, not a row. Cheaper than row editing (no geometry involved) but still a write to the pool, so it shares the same undo question. |

**Recommended split:** ship **Zoom to selected** with Step 3 — it is small, read-only, and makes
selection immediately useful. Hold the two editing actions until the write/undo model is decided
with item 38, so all three land on one mechanism.

**Note:** the layers panel already has a right-click menu (`eaLayerMenu`), so there is an existing
pattern and CSS to reuse rather than a new one to invent.

### GIS parity Step 3 + item 54's "Zoom to selected" — **DONE (v0.10.18)**

**Step 3 — click the map to identify a feature.** The other direction of the same selection model
built in Steps 1-2, so there is still **one** mechanism with two entry points: clicking a row
highlights the feature, and clicking the feature highlights the row.

- **Vector.** The click arrives in WGS84 (leaflet always does) and is transformed into the
  **layer's own CRS** before any test — the trap recorded for drawn shapes, and it matters:
  a real shapefile is usually projected, not 4326.
  - **Polygons** use `st_intersects` — a click is either inside a feature or it is not.
  - **Points and lines** cannot work that way: an exact intersection essentially never happens.
    They use `st_nearest_feature` plus a distance test, and the tolerance is **derived from the
    zoom level** (`156543.03 * cos(lat) / 2^zoom`, about 12 pixels of slack). A fixed metre
    tolerance would be uselessly coarse zoomed out and impossible to hit zoomed in — verified
    both ways: a ~1 km miss **hits** at zoom 8 and **misses** at zoom 18.
- **Raster.** `terra::extract` at the clicked point, showing every band's value, with `NA`
  rendered as "no data". No selection is written — a raster cell is not a feature.
- **Clicking empty space clears the selection**, which is what a GIS does.
- The hit is pushed **back into the table** via `DT::selectRows`, so a map click highlights and
  scrolls to the matching row.
- The popup is drawn **in the render pass**, not by proxy — same reason as the highlight
  (gotcha 23). A stale popup is dropped when a row is picked or the layer changes.

**Zoom to selected** (item 54's cheapest action, shipped here as recommended). Reuses the
**existing one-shot `fit_req`** that "Zoom to layer" already uses, so there is no second way to
move the map, and the zoom does not fight the user panning afterwards. A **single point is padded**
before fitting — `fitBounds` on a zero-extent box zooms to maximum, which looks broken. With
nothing selected it says so and does nothing.

**Verified:** clicking inside polygon 2 selects feature 2 and produces a popup naming the layer and
its attributes at the click point; empty space clears both; a point layer selects the clicked
point; the zoom tolerance genuinely scales with zoom (both directions tested); Zoom to selected
requests the **selection's** bbox, tighter than the whole layer's; a single point yields a
non-degenerate box; zooming with nothing selected returns FALSE rather than erroring; a table click
drops a stale popup. Step 2's behaviour re-checked for regressions. `check_ui_js` PASS, HTTP 200.

**A testing note worth keeping.** The first version of this test asserted that `fit_req` still held
a value after the input fired, and reported a failure that did not exist: `fit_req` is a
**one-shot** the render pass consumes and clears. The fix was to test the two halves separately —
the *wiring* through `map_rebuild`, and the *bbox* by calling the function directly before the
render eats it. **Asserting on state the system legitimately consumes produces false failures**;
this is the third time in this session a check has measured the wrong thing (the others matched
comment prose rather than code).

**Still open on item 54:** *edit attribute* and *add attribute*, deliberately held until the
write/undo model is settled with item 38 so all three land on one mechanism. Also still to do:
move these actions onto a **right-click menu** on the table (the layers panel's `eaLayerMenu` is
the pattern to reuse) — they are currently buttons in the dock header.

### Step 3 FOLLOW-UP — the identify popup vanished, and ignored the theme (v0.10.19)
> "the data attributes comes as a pop up and disappears. it should remain until the user closes it.
> also, the background is white. it should follow the theme cus the texts colors does not match
> well too."
>
> Confirmed working in the same session: *"clicks on the map selected layer does show the attribute
> precisely in the attribute table and the pop up"* — so identify itself was right; these are two
> defects in how the popup behaved.

**1. It disappeared.** Leaflet's popup defaults are `closeOnClick` (inherited from the map) and
`autoClose` — so the attributes vanished on the next map click and whenever another popup opened.
For a *readout you are meant to study* that is the wrong default. Now
`closeOnClick = FALSE, autoClose = FALSE, closeButton = TRUE`: it stays until dismissed.

**And closing it has to clear the STATE, not just the bubble.** The popup is drawn from
`identify_at()` on **every** render, so without this it would come back the moment anything
rebuilt the map — press *Zoom to* and the popup you just dismissed reappears. A `popupclose`
listener (bound once per map, guarded in the JS) sets a Shiny input that clears `identify_at`.
Closing a popup does **not** deselect the feature — the red highlight and the table row stay, which
is the GIS behaviour.

**2. It was a fixed white panel** — leaflet ships its own bubble with a white background and dark
text, so it looked right in light mode and was unreadable on every dark set. **This is gotcha 31
exactly** (a fixed *light* panel is as broken as a fixed dark one), and it needed gotcha 22's
remedy: restate the component's own classes (`.leaflet-popup-content-wrapper`, `.leaflet-popup-tip`,
`.leaflet-popup-content`, `.leaflet-popup-close-button`) with tokens, because leaflet's CSS is a
loaded dependency that no `:root` override can reach. The close button is restyled deliberately —
now that the popup is sticky it is the only way out, so it must be visible rather than leaflet's
faint grey on a dark panel.

**A gap in the tooling this exposed.** `.POPUP_JS` goes into the **widget payload**, not a
`<script>` tag, so **`check_ui_js.R` never sees it** — the guard built after v0.10.7 does not cover
JS delivered this way. The verification parses it with `node --check` directly. Worth remembering:
`check_ui_js` covers inline scripts in the UI, *not* JS handed to `htmlwidgets::onRender()`.

**Verified:** sticky options present; `popupclose` wired and clearing state; listener bound once;
`onRender` applied in the render pass; the JS parses under `node --check` with no split string
literals and no double quotes; popup CSS uses `--panel`/`--ink`/`--bark` with **no hardcoded hex**;
and a regression run still identifies feature 2, clears the popup state on close, and **keeps the
selection**. `check_ui_js` PASS, HTTP 200.
**Not verified here:** how it looks — worth confirming the popup is readable on a dark theme and
that the close button dismisses it for good.

---

### Working agreement (2026-08-06)
> "we will close the existing ones before opening new ones. just document new ones because I am
> receiving feedback along the way"

**Close open items before starting new ones. New feedback gets DOCUMENTED, not built**, unless it
is a defect in something just shipped (which is closing, not opening).

Open, in the recommended order — symbology, multi-step undo, delete features, then edit/add
attribute + the right-click menu, then the dockable table. Item 42 (analysis ↔ mapping) waits for
the GIS side, per the reporter's earlier ruling.

### Step 3 FOLLOW-UP 2 — points did not work, and zoom is now manual (v0.10.20)
> "i think the automatic zooming should be removed… we keep zoom to manual instead of automatic."
> "I had to click on the item in the attribute first before the clicking of objects worked… its
> like clicking the attribute table activated the function."
> "seems like it really doesnt work for point layers but works great on polygons."

**Root cause of the point-layer failure — and it explains the polygon/point split exactly.**
Identify used **coordinate hit-testing** on `input$map_click`. But **leaflet swallows the map click
on a marker**: clicking a point fires `map_marker_click` and **no `map_click` at all**, so the
handler never ran. Polygons are paths, which *do* fire a map click alongside, which is why they
"worked great". The zoom-scaled tolerance I built for points was solving a problem the event
model never let it see.

**Fix: features carry their own identity.** Every drawn feature now gets
`layerId = "<layer>##<row>"`, and `map_shape_click` / `map_marker_click` report exactly which
feature was hit. **All coordinate hit-testing is gone** — no `st_nearest_feature`, no
metres-per-pixel tolerance, no guesswork. Identity is drawn onto the map and read straight back.

Three consequences handled:
- **The highlight gets the same id** as the feature beneath it. It sits on top, so without this a
  click on an already-selected feature would hit the highlight and identify nothing.
- **Clicking a feature of a non-active layer switches to that layer**, which is what a GIS does —
  otherwise the click would select a row in a table showing something else.
- **The echoed map click is suppressed.** Paths fire *both* events; without a guard the map click
  would immediately read as "empty space" and undo the selection. Feature handlers run at
  `priority = 10` so the ordering is guaranteed rather than incidental.

`map_click` is now only two things: **raster identify**, and **clear on empty space**.

**"Had to click the attribute table first"** is very likely the same cause — the reporter was
testing a point layer, where the map click never arrived. Recorded honestly: this symptom was
**not reproduced in `testServer`**, so it is inferred, not proven. If it recurs on *polygons*,
it is a different bug and the diagnosis above is incomplete.

**Automatic zooming removed.** The map now moves **only** on an explicit "Zoom to …". Both
automatic paths are gone — the first-fit for a new layer set, and the fallback fit when no saved
view existed. This matters more than it did yesterday: the selection highlight now rebuilds the
map on every click, so an automatic fit would have yanked the view each time.
**Accepted consequence:** adding the first layer no longer frames it; "Zoom to layers" does.

**Verified:** clicking a point marker selects that point and pops its attributes — the reported
failure, now working, with **no table interaction anywhere in the test**; polygons still work and
switch the active layer; the echoed map click does not undo the selection; genuinely empty space
still clears; a malformed id is ignored rather than crashing; manual Zoom to still works; and the
automatic fit branches are gone while the user's own view is still restored. `check_ui_js` PASS,
HTTP 200.
**Not verified:** thin LINE layers. Leaflet's clickable area for a 2px polyline is narrow, so
lines may need a click closer than feels natural. If that proves annoying, the fix is a wider
invisible hit-stroke, **not** a return to coordinate tolerance.

**A recurring testing fault, now four times in this session.** This check reported a false failure
because the comment-stripper cuts at the first `#`, which swallowed the `"##"` inside the string
literal it was testing for. The pattern each time: **asserting against text rather than
behaviour** — matching prose, consumed state, or a mangled source. The behaviour assertions have
been right every time; the source-grep assertions keep being wrong.

### GIS parity Step 5 / item 39 — **VECTOR SYMBOLOGY DONE (v0.10.22)**

Closes the vector half of round-3 item 11. Raster symbology (stretch, classified, hillshade blend)
remains open.

**What it replaced.** The layer expander showed the words "single symbol" and three coloured
swatches that **did nothing** — a mock. Vector styling was hardcoded green in `.draw_layers`.

**Built on the store that already existed.** `layer_style` (a `reactiveVal` holding a list,
persisted into the project by `project_store.R`) already carried the raster band mapping. Vector
settings are nested under a **`vec`** key so they can never collide with the raster `mode` key.
Verified that **renaming a layer carries its styling across** — `server.R:616` moves the entry.

#### What is available

| Mode | Drives | Notes |
|---|---|---|
| **Single symbol** | fill + outline colour | The default. Computes nothing per feature, so the common case stays cheap. |
| **Categorised** | one colour per distinct value | Legend lists every level. |
| **Graduated** | numeric column, 3-9 classes | **Quantile** breaks. Legend lists each range. |

- **Palettes:** viridis, magma, plasma, cividis, turbo — stored **by name**, not as a colour
  vector, so a palette definition changing later does not freeze old projects to stale colours.
- **Outline width** (0-6) and **fill opacity** (0-1) apply in every mode.
- Points, lines and polygons each take an appropriate path; polygons keep a separate outline colour
  so class boundaries stay legible.

#### Decisions worth keeping

- **Quantile breaks, not equal interval.** Most measured attributes are skewed; equal-width bands
  put nearly everything in one class. Falls back to equal-width only when values are too tied for
  quantiles to produce distinct breaks.
- **Field lists are filtered by what the mode can actually use**, and a numeric column is offered as
  a *category* only if its values repeat (`unique * 2 <= n`). **Caught by a test**: with 12 features
  and 12 distinct volumes, every feature became its own class — a legend as long as the layer. The
  rule was wrong, not the test.
- **One resolver.** `.vec_colours()` returns one colour per feature (or NULL for single symbol), and
  both the map and the legend read it, so what you see and what the legend says cannot drift.
- **Selection stays red regardless of symbology** — a selection must stand out from the scheme, not
  blend into it.
- **One observer per control keyed by `{nm, v}`**, following `.band_sel`'s reasoning: the expander
  is rebuilt for every layer on every render, so per-layer Shiny inputs would need per-layer
  observers.

**Verified:** defaults; field typing in both directions including the repeat rule; categorised gives
one colour per level with equal categories sharing a colour; graduated breaks bound the data and
colour tracks magnitude with no feature uncoloured; settings persist into `layer_style` under `vec`;
all appearance controls store; changing palette changes the colours; and four degenerate inputs (no
field, missing column, constant column, blank) fall back to single symbol instead of breaking the
map. Map renders; legend offers all three modes and lists ranges; the dead mock markup is gone.
`check_ui_js` PASS, HTTP 200.
**Not verified:** appearance — worth checking the colour and range inputs are usable inside the
layer expander, and that a long category list scrolls rather than stretching the panel.

**Reaching it (added in the same release, before the reporter had tested any of it).**
> "you also have not made it possible for us to access. right clicking the layer should open
> symbology. also symbology in the menu (not sure where it belongs)"

A fair hit: the controls were built into the layer expander, reachable **only** by finding a small
chevron on the layer row. Built but effectively hidden, which is the same as not shipped.

- **Right-click a layer → "Symbology…"**, listed **first** in the context menu because it is the
  action most often wanted on a layer. Offered for vector and raster only.
- **View ▸ Layer ▸ Symbology…** for the active layer. Placed in **View** rather than Edit
  deliberately: symbology changes how a layer *looks*, not what the data *is*, so it belongs with
  theme, basemap and layout.
- **Opening it does everything needed to make it visible** — selects the layer, switches to the map
  if you were on the data view, and expands the row. Setting only the expand flag would leave the
  panel open behind the Data view, which reads as the menu item doing nothing.
- Refusals are explicit: a table layer says it has no symbology; no selection says to pick a layer.

**TESTED AND WORKING (reporter, 2026-08-06).** Vector symbology and both access routes confirmed in
the browser.

**Improvements deferred deliberately, not forgotten:**

- **Raster symbology** — the open half of round-3 item 11: stretch, classified / paletted,
  hillshade blend, transparency. Only the RGB / single-band toggle exists today.
- **Rule-based styling and labels** — the two remaining vector tools from item 11.
- **More break methods** for graduated: equal interval, natural breaks (Jenks), standard deviation,
  manual. Only quantile exists, with an equal-width fallback.
- **Size by value** — graduated symbol *size* for points, not only colour; and per-class control.
- **Copy a style between layers**, and saving one as a reusable preset.
- **Still not eyeballed:** whether the colour inputs and sliders are usable at that width inside the
  layer expander, and whether a long category list scrolls rather than stretching the panel.

---

### 55. Release-notes page needs a contents sidebar — **OPEN, documented not built**
> "the release notes page is getting long. we need a notebook style with contents on the side to
> help readers"

The page now carries **62+ releases** in one continuous scroll and grows with every push, so it is
already past the point of being readable top-to-bottom.

**Asked for:** a notebook-style layout — the release list in a **sidebar**, content beside it.

**Notes before building:**
- **`landing/release-notes.html` is GENERATED.** The change belongs in
  `landing/build-release-notes.mjs`, not the output file, or the next push overwrites it.
- **The anchors already exist** — every release renders `id="v0-10-21"`, so a contents list is a
  loop over the versions already parsed (`body.match(/^## v/gm)`), not new parsing.
- **`documentation.html` already has this exact layout** (a sticky `<aside>` of anchor links beside
  an `<article>`), and `assets/site.css` carries its styling. **Reuse that** rather than inventing a
  second sidebar idiom — the two pages should look like the same site.
- **The site's CSP allows no external host**, so no scroll-spy library: highlighting the current
  section needs a few lines of inline JS or `:target` styling.
- **Mobile:** a fixed sidebar cannot simply collapse to nothing — 62 versions in a dropdown is also
  unusable. Consider showing only the most recent N with a "show all" toggle.
- Worth pairing with **grouping by minor version** (v0.10.x) so the sidebar is two levels rather
  than one flat list of 62.

### 56. Split the docs: "Getting started" vs a living technical reference — **OPEN, documented not built**
> "I am thinking we have to rename Documentation in the landing page to getting started or similar.
> then create a proper documentation page. thi documentation will be the living source of truth on
> how the app does things. for eg, how it calculates regression analyses."

**The problem is real and getting worse.** `documentation.html` is currently doing two jobs at
once: telling a new user how to install and find things, *and* being the reference for what the app
does. The symbology section added in v0.10.22 made that obvious — it is method documentation sitting
in what is otherwise an orientation guide.

**Proposed split:**

| Page | Audience | Contains |
|---|---|---|
| **Getting started** (the renamed `documentation.html`) | someone who has just installed it | install, requirements, the workspace, menus, file formats, projects, privacy, troubleshooting, how to cite |
| **Reference** (new) | someone who has a result and needs to know what produced it | **per method: the function actually called, its arguments, how inputs are prepared, what the metrics mean, and the assumptions** |

**Why this matters more than tidiness.** A user publishing a result needs to say what was computed.
Right now the only way to know that a regression is `stats::lm` with a particular
handling of factors, or that graduated symbology uses **quantile** breaks, is to read the source.
For a tool aimed at people who do not write code, that is the wrong place to keep it.

**It must be a LIVING source of truth, which is the hard part.** Hand-written method docs drift from
the code — this repo has already produced three examples (`llms.txt` describing a build that no
longer existed, a favicon claimed as done and never served, `uef_evaluation()` documented as unused
while four modules called it). Options, cheapest first:
1. **Generate what can be generated.** `statistics.R` and `algorithms.R` are registries: id, label,
   group, summary, roles, parameters are already structured data. A build script could emit the
   method list, its inputs and its parameters directly from them — the same approach
   `build-release-notes.mjs` uses for the changelog, which has not drifted since.
2. **Hand-write only what the registry cannot express** — the assumptions, the interpretation, the
   caveats — and keep it beside the spec so it is edited in the same place.
3. **A check that fails** when a registry entry has no reference text, the way `check_ui_js.R` fails
   on bad JS.

**Cross-references:** the in-app **References** screen already lists published methods and their
DOIs (`references.R`) — the new page should link to it rather than duplicate it. `papers/METHODS.md`
covers the same ground internally.

**Do not start until items 38/39 land** — per the working agreement, and because a reference page
written now would need rewriting as delete, edit and raster symbology arrive.

### 56 (part 1) — **DONE (v0.10.24)**: docs split, and a GENERATED method reference

The split proposed above is built.

| Page | URL | Role |
|---|---|---|
| **Getting started** | `/documentation` *(URL unchanged)* | install, workspace, menus, formats, projects, privacy, troubleshooting, citing |
| **Reference** | `/reference` *(new)* | what the app actually computes |

**The URL of the existing page was deliberately NOT changed.** `/documentation` is linked from the
app's Docs button, `llms.txt`, the sitemap, the README and both other pages. Renaming the file to
match the new title would have broken every one of them for a cosmetic gain. Only the **title, the
`<h1>` and the nav label** changed.

#### The reference page is generated — `tools/build-reference.R`

**This is the anti-drift decision, and it is the point of the whole item.** Prose that repeats what
code does eventually lies about it, and this repo has three proofs already: `llms.txt` described a
WebAssembly build that no longer existed; the favicon was recorded as "linked from the page
`<head>`" while the site 404'd it; CLAUDE.md called `uef_evaluation()` unused while four modules
called it.

So the page is built **from the registries**: `ea_statistics()` and `ea_algorithms()` already hold
id, label, group, summary, variable roles and parameters as structured data. Currently **14
statistical methods and 50 spatial operations** — note the 50, where CLAUDE.md still says 33; the
generated page is now the accurate count and the prose is the stale one.

**The strongest part: the engine call is extracted from the code.** Each spec's `fit()` / `run()`
is deparsed and its `pkg::fn` calls read out, filtered against a list of plumbing packages. So the
page states `MASS::polr()`, `lme4::glmer()`, `mgcv::gam()`, `randomForest::randomForest()`,
`lidR::rasterize_terrain()` and so on **because the code says so**, not because someone wrote it
down. Change the engine and the page follows on the next build; it cannot quietly become wrong.

**What is deliberately NOT generated:** assumptions, interpretation and caveats — they cannot be
derived from a spec. They live in `REFERENCE_NOTES` inside the build script, so they are edited
next to the thing they describe rather than in a separate file that rots.

Also hand-written, because they are cross-cutting rather than per-method: the **metrics** section
(what RMSE / R² / Bias / RelBias mean, and that they come from one shared `uef_evaluation()` so
they are comparable across screens) and the **symbology** section (quantile breaks and why,
palette choice and colour-blind safety, the repeat rule for categorical numerics).

**Follow-up, not done:** the generator is run by hand. It should run in CI like
`build-release-notes.mjs` does — but it needs the full R app loaded, which is far heavier than the
node build, so that needs its own decision.

---

### 57. Show the script that ran an analysis — **BUILT v0.11.18 for the registry**
> "this should be a feature where the user can click see script ran and the script that was used
> for the analyses gets shown."

A **"See script"** control on a result that shows the R code which produced it.

**This is the highest-value item in this group, and it is close to free**, because the registries
already hold everything: `statistics.R` specs carry a `fit(df, r, p)` whose body IS the script, and
the runner already knows the chosen roles and parameter values. Deparsing the fit body and
substituting the actual column names produces a runnable script rather than a description of one.

**Why it matters beyond convenience:**
- **Reproducibility.** A point-and-click result currently cannot be reproduced by anyone who was
  not sitting at the machine. A visible script makes it citable and checkable.
- **It is the same mechanism as the reference page** (item 56) — one deparses the spec generically,
  the other deparses it with the user's actual arguments filled in. Build them on one helper.
- **Trust.** For an audience told not to write code, showing the code on demand is what makes the
  tool inspectable rather than a black box.

**Notes:** the script must include the library calls and the data-loading line, or it is not
runnable. Where a method does preprocessing the user did not ask for (dropping NA rows, coercing a
factor), **that must appear in the script** — it is exactly the hidden step someone needs to see.

### 58. Download and upload scripts — R, Python, Jupyter — **OPEN, documented not built**
> "document download r scipts and uploading r scripts. same for python and jupyter notebooks."

- **Download** is the natural extension of item 57: once the script exists, save it as `.R`.
- **Upload/run** is a much larger step and a **security boundary**: running an uploaded script is
  arbitrary code execution in the user's session. Locally that is the same trust level as opening
  RStudio, but it must be a deliberate decision, not a side effect of a file picker.
- **Python and Jupyter are gated on the toolchain question in item 26/26a** — no Python
  integration exists anywhere in the app, and Jupyter additionally needs a running server. Exporting
  a `.ipynb` is *not* gated (a notebook is just JSON, and an R-kernel notebook needs no Python at
  all) — worth separating those two, since export is cheap and execution is not.

**Order:** show (57) → download `.R` → export `.ipynb` → upload/run R → Python at all.

### 59. Multi-script tabs and run-a-line — **OPEN, partly a duplicate**
> "document multi script tabs and one line code selector runs."

**Already recorded as C11 (run line/selection, like RStudio's Ctrl+Enter) and C12 (script tabs)**,
both open, and both blocked on the same thing recorded in item 26 part 2: the console's editor is a
plain `textAreaInput`, which **has no notion of a current line, a selection or a gutter**. No amount
of wiring gets Ctrl+Enter out of a textarea.

**So the prerequisite is a real editor** (`shinyAce`, CodeMirror or Monaco). That single change
unblocks C11, C12, C13 *and* is the editor item 26a's "Write code ▸ R" needs. It should be done
once, deliberately, rather than approached three times from three items.

### 60. Switching browser tabs makes the app think it disconnected — **FIXED v0.10.25, corrected v0.10.26**
> "document that when we change tab, the app thinks it went to sleep."

The disconnect panel added in v0.10.14 (item 50) fires when the user switches **browser tabs**, not
only when the machine sleeps. Wrong, and annoying: it interrupts normal use of a browser.

**Likely cause, to confirm before fixing:** the panel is triggered by `shiny:disconnected`, and a
backgrounded tab can have its websocket throttled or dropped by the browser. The handler cannot
currently tell a real disconnect from a tab that was simply hidden.

**Shape of the fix:**
- Use the **Page Visibility API** — if `document.hidden` was true, treat a reconnect as routine and
  do not show the panel at all.
- **Wait before showing it.** A momentary drop should reconnect silently; only a disconnect that
  persists past a short delay is worth a panel.
- The existing **server probe already distinguishes the two real cases** (R alive vs stopped), so
  the missing piece is only "is this worth telling the user about at all".
- Keep the panel for genuine sleep/wake — that was a real complaint and the fix works.

**This is a defect in shipped work, so under the working agreement it counts as closing rather than
opening.** It is the next thing to fix.

---

## Round 7 — scalability direction (2026-08-06)

Not defects. This is **architectural direction**, recorded now so the next build decisions are made
against it rather than around it. The reporter's framing:

> "plugins ecosystem must be built for scability"
> "plugin sdk, plugin repo, make built in tools use the same plugin system and many others. we
> will plan better"
> "scability: workflow automation / model builder (easy drag and drop)"
> "multi language only when it adds value. for advanced deep learning and machine learning tasks,
> use python under the hood. for statistical, use R."

**These four are one architecture, not four features**, and the order they are built in matters
more than any of them individually. Read 61 first — the rest sit on it.

### 61. Plugin ecosystem — SDK, repo, and moving built-ins onto it

**The important thing to say up front: this is half-built already, and it works.**
`algorithms.R` + `mod_algo.R` and `statistics.R` + `mod_stat.R` are a plugin system in embryo —
a declarative spec plus one generic runner. The evidence that the pattern scales is in this repo:
spatial operations went from 33 to **50** and 14 statistical methods exist, every one added as a
**list entry and nothing else**. When cancellation was needed it was **one change instead of 33**.
So "build a plugin system" is really **finish and externalise the one that already exists**.

**What is genuinely missing** — these are the gap, and each is a decision:

| Gap | Why it matters |
|---|---|
| **Specs live inside the repo** and are sourced at boot | A plugin must load from *outside* the installation. This is the single defining change. |
| **No manifest** — no id, version, author, min-app-version, declared dependencies | Without it there is no compatibility story and no way to tell why a plugin failed. |
| **No isolation** | A single missing package (`plotly`) once took down the **entire workspace** — `::` resolved at module construction, `workspaceServer()` threw, and a forward-referenced observer then failed on every flush. A third-party plugin doing the same must degrade to "this plugin is unavailable", never to a dead app. |
| **No trust boundary** | A plugin is **arbitrary R code running in the user's session**. Same boundary as item 58's script upload, and it must be a deliberate, visible decision — not a side effect of clicking Install. |
| **Not every screen is on a registry** | 5 are deliberately irregular: `mod_tests.R` (variable-length roles), `mod_da.R` (two-stage canvas), `mod_descriptive.R` (no run button), `mod_clustering.R` (unsupervised), `mod_suitability.R` (variable-length criteria). `mod_raster.R` stays for layer management and draw-based ops. **These are exactly what "make built-in tools use the same plugin system" means** — and each is a real spec-expressiveness question, not a port. |

**Sequencing that follows from the above:**

1. **Document the spec contract properly.** Partly done — `/reference` now publishes roles,
   parameters and engines *generated from the specs*, which is the beginning of an SDK document.
2. **Make the spec expressive enough for the 5 irregular screens**, or decide each stays a module.
   Doing this *before* opening the format publicly avoids a breaking change later.
3. **External loading + manifest.** Only then is it a plugin system rather than a registry.
4. **Isolation.** `compute_worker.R` already runs work in a **separate killable R process** — that
   is the natural sandbox and it exists.
5. **A repo/distribution story last**, because it is the part that cannot be changed quietly once
   people depend on it.

**Do not start 3-5 until 2 is settled.** Publishing a spec format that then has to change is the
one mistake here that is expensive to undo.

### 62. Workflow automation

Chaining operations into a repeatable pipeline.

**The registries make this unusually tractable**, and that is not a coincidence — every entry
already declares its **inputs (with pools), its parameters and its output pool**. A workflow is a
DAG over registry entries, and the type information needed to validate one is already there: an
operation that takes a raster cannot be wired to a vector output, and the specs already say so.

**Connections worth recording:**

- This is the natural home for item 57's **script generation** — a workflow *is* a script, and both
  should be produced from the same representation rather than two.
- It is also how **item 42** ("has the platform met its goal of analysing and mapping in one
  place?") gets a concrete answer: a workflow that runs a model and then maps its prediction is
  precisely the integration that entry says is missing.
- Cancellation and progress already exist for single operations (`compute_worker.R`); a workflow
  needs them per step.

### 63. Model builder — drag and drop

A visual pipeline editor.

**This is the same engine as 62 with a different front end**, and should be built that way. If the
canvas gets its own execution model there will be two ways to express a pipeline and they will
diverge — the same failure the selection model was built once to avoid (items 38/40).

**Order: 62 before 63.** A drag-and-drop canvas over an execution engine that does not exist yet
would define the engine implicitly, through the UI, which is the wrong way round.

### 64. Multi-language policy — R for statistics, Python for deep learning

> "multi language only when it adds value."

**This is a policy, and a good one, because it answers a question that has been open since item 26
with a criterion rather than a yes/no.** Python earns its place *where R genuinely lacks*, not for
parity:

| Use | Language | Why |
|---|---|---|
| Statistics, mixed models, spatial/LiDAR | **R** | Where the ecosystem is strongest, and where the app already is. |
| Deep learning, modern ML, foundation/segmentation models | **Python** | `torch`, `transformers`, `samgeo` and similar have no R equivalent worth pretending about. |

**The constraint this must respect** — and it is the app's main advantage: *"one installer, no
toolchain, no admin rights"*. So:

- **Python must be OPTIONAL and LAZY.** Installed when a user first asks for a tool that needs it,
  never at install time. A managed virtual environment via `reticulate`, not a documented
  prerequisite.
- **A Python-backed tool must degrade like any other optional dependency** — the screen says what
  is missing and how to get it, per gotcha 27, guarded at the **server binding** and not only in
  the UI.
- **This retires the ambiguity in item 26a**: the "Write code / Python / Jupyter" entries are about
  *the user writing Python*, which is a different question from *the app using Python underneath*.
  This policy answers the second and leaves the first open.

**Note the plugin connection:** if 61 lands, a Python-backed method is just a plugin whose engine
happens to be Python — the manifest declares it, and the toolchain is that plugin's problem rather
than the app's. **That is the strongest argument for doing 61 first**: it turns a platform-wide
commitment into a per-plugin one.

### Recommended order for Round 7

1. **61 step 2** — make the spec expressive enough for the irregular screens (decides the format).
2. **62** — workflow engine over the registries; also delivers 57's script generation.
3. **64** — Python as an optional engine, ideally arriving as a plugin.
4. **63** — drag-and-drop over the proven engine.
5. **61 steps 3-5** — external loading, isolation, distribution.

**None of this should start before the GIS work finishes** (delete features, raster symbology), per
the standing decision that the GIS side is fixed first. Recorded here so it is planned against, not
started.

### DOI — **STILL NOT DONE (reporter, 2026-08-06)**

`.zenodo.json`, `DOI.md` and the commented `identifiers` block in `CITATION.cff` are all in place
and waiting. **The two remaining steps need a Zenodo login and so cannot be automated from here:**
connect Zenodo to the repository, then publish a GitHub release. See [DOI.md](DOI.md).

Until it is done the citation resolves to `https://easyanalysis.dev` rather than a permanent
identifier. Not blocking anything, but it is the difference between a citation that survives the
domain and one that does not.

### Desktop icon on EXISTING installations — answered 2026-08-06
> "the app favicon is there but since i have tested it on a new pc, i havent seen the desktop icon.
> can that work for existing pcs?"

**Yes, and it needs nothing special — just re-run the installer.** Checked in `install.ps1` rather
than assumed:

- **The app is re-downloaded on every run** (`:100-104` fetches the zip and replaces `$AppDir`), so
  `launcher/easyanalysis.ico` arrives on an existing machine.
- **The shortcut block runs unconditionally on every install** (`:217-223`), recreating both the
  Desktop and Start Menu `.lnk`.
- **The icon is copied to `$AppHome` and set as `IconLocation` each time** (`:210-212`) — copied out
  of `$App` deliberately, so a later reinstall replacing the app folder cannot break the shortcut's
  icon path.

So an install predating v0.10.11 gets the icon by running the same one-liner again.

**One caveat worth telling users:** *Windows caches shortcut icons.* Even with a correct `.lnk`,
Explorer can keep showing the old PowerShell icon until the cache refreshes — signing out and back
in, or `ie4uinit.exe -show`, clears it. That is a Windows behaviour, not a defect in the shortcut.

**If the Desktop shortcut is missing entirely** (rather than showing the wrong icon), that is a
different failure: shortcut creation is wrapped in `try/catch` so it can never fail an install, and
it prints `[EasyAnalysis] Could not create shortcuts (...)`. Worth checking the installer output for
that line before assuming the icon is at fault.

### GIS parity Step 4 / item 38 — **DELETE FEATURES DONE (v0.10.26)**

The first destructive map operation, built on the selection model from Steps 1-3.

**Behind an explicit edit mode** (the QGIS pencil idiom), off by default and visibly armed. A
destructive mode that looks passive is the failure to avoid, so `.ea-wsx-selclear.on` uses the warn
token and Delete uses danger.

**Undo, per layer, bounded at 5** — deliberately the same shape as `mod_data.R`'s stack, keyed by
name so an undo cannot restore layer A's geometry into layer B. **Pruning filters on the value, not
`names()`** — gotcha 14 applied *before* it leaked this time, rather than after.

**Five refusals, each for a reason:**

| Refused | Why |
|---|---|
| Not in edit mode | The whole point of the toggle |
| Selection belongs to another layer | Row numbers are only meaningful for the layer they came from |
| Every feature selected | That is removing the layer, not editing it |
| Rows past the end | A stale selection must not subscript out of bounds |
| Undo with no history | Says so rather than doing nothing |

**The selection is cleared after a delete** — row numbers shift, so keeping it would highlight
whatever now occupies those positions.

**Verified: 24 checks.** Two failures during development were **test faults, not code faults** —
sections that toggled edit mode blindly and inherited an armed state, and a section whose layer had
been whittled to one feature by an earlier section, so the do-not-empty guard correctly refused.
Recorded because it is the seventh and eighth time this session a check has been wrong rather than
the code.

**Still open on item 38 / 54:** *edit attribute* and *add attribute* (a column, not a row), and
moving these controls onto the right-click menu — they are dock-header buttons today. Both write
paths should reuse `.edit_snap()` rather than inventing a second undo.

**Raster symbology DONE (v0.10.27)** — band selection, five palettes with reverse, stretch
(min-max / 2-98% / 5-95% / manual), 3-9 classes or continuous, and opacity. Stored under `ras` in
the same per-layer style entry and persisted in the project.

**Measured, because it is the reason the feature exists:** a band whose values run 0-10 with four
pixels at 10,000 stretches full-range to **0-10000**, putting every real value in the bottom
thousandth of the ramp. Clipping to 2-98% gives **0.2-9.8**.

**Still open on item 11:** hillshade blend (needs a DEM and a blend pass — genuinely more work than
the rest), rule-based vector styling, and labels.

**Next:** item 42's integration work — the GIS side is now done.

### 65. Drag layers up and down to reorder them — **DONE v0.11.6**
> "make layers draggable: up and down"

**This is not only a panel affordance — it is draw order.** `.draw_layers()` iterates `layers()`
and adds each to the map in sequence, and in leaflet **the last one added sits on top**. So the
order in the panel *is* the stacking order, and today it is fixed: tables, then rasters, then
LiDAR, then vectors, in whatever order the pools happen to hold them. A user cannot currently put
a vector outline over a raster, or move one raster above another.

**What it needs:**

| Piece | Note |
|---|---|
| **An explicit order** | Today order is *derived* from the four pools in `layers()`. Reordering needs a stored sequence of layer names, with anything unlisted appended so a newly added layer still appears. |
| **Persisted in the project** | Same place as `layer_style` — a stacking order the user set once must survive reopening, or it is not worth setting. |
| **`.draw_layers()` follows it** | Otherwise the panel and the map disagree, which is worse than no reordering at all. |
| **Drag interaction** | HTML5 `draggable` is enough; no library needed. The layer rows are already rebuilt by `renderUI` on every change, so the drop handler should fire one event carrying the new order rather than mutating the DOM and hoping it sticks. |

**Traps to respect:**

- **The basemap row is pinned to the bottom and must not be draggable** — it is tiles, not a
  project layer, and it is added with `zIndex = 0` beneath everything.
- **The row already has three click targets** (visibility toggle, name, delete) and a right-click
  menu. A drag handle needs its own grip area or it will fight them — a `cursor: grab` zone on the
  left, not the whole row.
- **Reordering rebuilds the map**, which is correct here and consistent with how selection and
  symbology already work. Do not reach for `leafletProxy` (gotcha 23).
- **Rasters are drawn as images**; two overlapping rasters make the order visible immediately,
  which is the case worth testing first.

**Related, worth doing in the same visit:** the panel groups by type implicitly. Once order is
explicit, "move to top / move to bottom" from the right-click menu is nearly free and is often
easier than dragging in a long list.

### 66. Test failures kept being MY failures — the pattern, and the rules that follow
> "failures and errors in your tests have persisted. document this and ensure that the reasons are
> explained so that it does not happen again."

**Fair, and worth being precise about rather than apologetic.** Across this session **eight checks
reported failures that did not exist**, plus two scripted patches that silently did nothing. In
every single case the application code was correct and the *check* was wrong. That is not a
harmless kind of noise: a false failure invites "fixing" working code, and it costs exactly the
trust that testing is supposed to buy.

#### What actually happened

| # | Symptom | Real cause |
|---|---|---|
| 1 | "`ea_worker_shutdown()` does not precede `stopApp()`" | The regex matched the **comment** explaining the ordering, which mentions `stopApp()` first |
| 2 | "attribute table still calls `head(df, 200)`" | Matched the **new comment** saying "not `head(df, 200)`" |
| 3 | "Zoom to selected requested no fit" | Asserted on `fit_req`, a **one-shot the render consumes** — it had worked and been cleared |
| 4 | "popup JS has a string split across lines" | Regex spanned from the close-quote of one literal to the open-quote of the next |
| 5 | "id helper does not encode layer + row" | The comment-stripper cut at the first `#`, **eating the `"##"` inside the string being tested for** |
| 6 | "multi-step undo is completely broken" | `dataServer` requires `dataset_names`; omitting it threw and **aborted the observer chain** |
| 7 | "disconnect panel never renders" | My fake `window` had no `location`, which the server probe reads |
| 8 | "edit mode was not armed" / "only the valid row went" | Test sections **inherited state** from earlier ones — a blind toggle disarmed it, and a layer had already been whittled to one feature so the do-not-empty guard correctly refused |

Two more that failed *silently*: `s.replace(...)` calls in patch scripts that matched nothing and
reported success anyway.

#### The three root causes

1. **Asserting on TEXT instead of BEHAVIOUR** (1, 2, 4, 5). Every one of these greps source code.
   Source is prose plus code; a regex cannot tell them apart, and comment-stripping with
   `sub("#.*$", "")` actively corrupts string literals.
2. **Incomplete test doubles** (6, 7). A stub built from memory rather than from the real
   signature. Both threw *inside* the framework, where the error surfaced as "the feature is
   broken" rather than "your fixture is wrong".
3. **Shared mutable state across sections** (3, 8). Later assertions depended on earlier ones
   having left a particular state, so a change anywhere invalidated everything after it.

#### The rules

- **Assert on behaviour. Never on source text** when the behaviour can be observed. Every
  behaviour assertion this session was correct; nearly every source-grep was not.
- **If a source check is genuinely unavoidable, PARSE — do not grep.** `node --check` and R's
  parser were right every time a regex was wrong. **Never strip comments with a regex.**
- **Build fixtures from the real signature**, not from memory: read `formals()` for an R module
  server, and let a JS stub throw once and fill in what it asks for.
- **Every test section establishes its own preconditions.** Use an explicit helper
  (`arm()`, `reset()`) rather than inheriting. A section that only passes when run after another
  is not a test, it is a coincidence.
- **Never assert on state the system legitimately consumes.** Assert on the *effect* — the fit was
  applied, the row was deleted — not on the request object that was cleared afterwards.
- **A scripted patch must fail loudly.** Every `replace` needs an `assert` that its anchor exists;
  several silently no-opped and were only caught by re-reading the file.
- **A failing check is suspect until the behaviour test agrees with it.** On this evidence the
  prior probability is strongly that the check is wrong.
- **Delete stale tests.** `verify_step3.R` asserted hit-testing that v0.10.20 deliberately removed;
  it failed by design and was noise. A test that fails for a reason nobody will act on is worse
  than no test.

---

### 67. The analysis-to-map round trip is not discoverable — REPORTED 2026-08-09, documented only

> Reported after trying the documented five-step chain: could not bring the predictions back
> to the map, and found the buttons and the flow unintuitive. A second opinion is being sought.
> **No code changed. This is the write-up, not the fix.**

The chain built in item 42 works — the logic is tested — but **the reporter could not complete
it while holding the instructions.** That is a design failure, not a user failure, and it is
worth more than the feature: a round trip nobody can find is a round trip nobody has.

**The flow as built:**

1. Add a vector layer that has attributes (shapefile *with* its `.dbf`, or a GeoPackage).
2. Run the **Attributes to Table** algorithm → a dataset appears in the left rail.
3. Fit a model on that dataset (robust regression, GLMM, GAM, Poisson, negative binomial).
4. Press **Predictions to map layer** in the tools panel.
5. Layers panel → expand the layer → Graduated → colour by `pred`.

**Five steps, three screens, and every one of them has to be known in advance.** Nothing in the
app announces that the chain exists.

#### Specific faults, in the order they bite

1. **Nothing offers the entry point.** Step 2 is an entry in the processing-algorithm list. A
   user looking at a map layer and wanting to model it has no reason to search a
   *processing* list for the word "Attributes", and the layer's own right-click menu — which is
   where they *do* look, since that is where symbology lives — does not offer it.
2. **The name describes the mechanism, not the intent.** "Attributes to Table" says what it
   does internally. It does not say *"this is how you start modelling a map layer"*, which is
   the only reason to press it.
3. **The return button does not exist until it does.** `Predictions to map layer` is rendered
   by `actions_ui`, which returns `NULL` until a fit succeeds. So a user exploring the screen
   *before* running the model sees no evidence the capability exists — and after the run it
   appears at the bottom of the tools panel, below everything else.
4. **The refusal is the thing most likely to be seen, and it is transient.** Every refusal path
   in `ea_action_to_layer()` throws, and `mod_stat.R` reports it with
   `showNotification(..., duration = 8)`. The messages themselves are specific and good — they
   name the cause and the remedy — but they **vanish after eight seconds**. The single moment a
   user most needs the explanation is the moment it disappears. This is the same complaint
   already made about attribute pop-ups, in a new place.
5. **The refusal is also the most likely outcome for a first attempt.** The link is deliberately
   strict (a decision taken on purpose: *the best decision for the job and tool always wins*),
   so fitting on a dataset that did **not** come from step 2 refuses — which is exactly what a
   user does when they have not yet been told step 2 is mandatory.
6. **Step 5 is a second undiscoverable hop.** Even on success, the new `pred` column changes
   nothing visible; the user must know to open symbology and switch to Graduated. The layer does
   not redraw, and nothing says a new column arrived.

#### What this suggests (not decided — awaiting the second opinion)

- Offer the entry point **where the user already is**: an item on the layer's right-click menu
  (*Model this layer* / *Attributes to table*), next to symbology.
- **Show the return button always**, disabled with the reason on it, rather than hiding it until
  a fit exists. A disabled control teaches; an absent one cannot.
- **Make refusals persistent** — inline in the panel, not an 8-second toast. Reuse whatever
  fixes the pop-up complaint.
- On success, **say what happened and where** ("added `pred` and `resid` to *Plots*"), and
  consider switching the layer to Graduated on `pred` automatically, since that is the only
  reason anyone pressed the button.
- Reconsider the name.

**Blocked on the second opinion before building anything.** The reporter is right that a fix
chosen from one person's confusion may be the wrong fix.

---

### 68. Two v0.11.2 changes are UNVERIFIED VISUALLY — no browser test has been done

Recorded so it is not mistaken for tested work. The **logic** of both is covered by
`check_cv_folds.R`; what has **not** happened is anyone looking at them on screen. There is no
browser automation in this environment, so these need eyes.

**a) The cross-validation caveat, and it is weaker than intended.** The message
(*"Incomplete: 1 of 5 folds could not be fitted, so 18 row(s) (20% of the data) are NOT
included."*) is appended to the accuracy caption of the results table.

Traced end to end, without a browser: `DT` stores the caption as a raw `<caption>` element in
its JSON payload and injects it client-side, so the rendered element carries **no class**;
Bootstrap styles bare `caption` with `color: var(--bs-secondary-color)`; `ui.R:272` maps that to
`var(--bark)`, the per-theme *secondary* text colour.

So the caveat is **legible in every theme — but rendered in the lowest-emphasis text style the
table has**, with no warning colour and no weight, separated from the accuracy by a plain
dash. A statement that the number above it is unreliable is currently styled as a footnote.
That is a real weakness even though nothing is invisible. **Traced, not seen** — the cascade is
determinate but no one has looked at it.

**Likely follow-up:** give the caveat its own element with a warning tone (a translucent
`color-mix()` of a semantic token, per the fixed-light-panel rule) rather than leaving it in
the caption. Not done, because it should be *looked at* first.

**b) The time-series failure text.** `decompose()` now shows its underlying error inside
`show_placeholder()`, and the stationarity test prints a failure line. Neither has been seen
rendered. A long engine message may overflow or wrap badly in the placeholder, which is sized
for a short sentence.

**Neither is a correctness risk** — the numbers and the guard are proven. Both are presentation
risks, and both are the kind of thing that is obvious in one second of looking and invisible
from a test suite.

---

### 69. Error messages deleted themselves — FIXED v0.11.3

Chosen as the first thing to do before external testers, ahead of every other open item, on an
argument that is not about polish.

**Measured first: 110 error-type notifications in the app; 2 were persistent.** The other 108
expired after 5–8 seconds.

**Why it outranks the rest.** The messages are mostly good — they name the cause *and* the
remedy. So what expired was precisely the part worth having. And during an external test round
it is worse than a UX annoyance: **a tester cannot report a message they never finished
reading.** The report arrives as *"it didn't work"* and the diagnosis is already gone. Running
external testing with self-deleting error text is running it with the instruments switched off.

It is also a plausible contributor to item 67: every refusal in the analysis-to-map round trip
is one of these. The reporter may well have been told exactly what was wrong and had it taken
away before they could act.

**One wrapper, not 110 edits.** `helpers.R` defines `showNotification()` shadowing shiny's.
Viable because **no call site writes `shiny::showNotification`** — checked, since a qualified
call bypasses a shadow (gotcha 27) — and helpers.R is sourced into the global env, so any
unqualified call in any module resolves to ours. Signature mirrored exactly so positional calls
still land. Errors become `duration = NULL` + `closeButton = TRUE`, and get a content-derived
id so a reactive failing on every flush replaces its own notification rather than stacking.
Warnings and messages untouched.

**Guarded by `check_notifications.R`**, which proves the wrapper is reached **from a module
frame** — not just from a script, whose environment is the global env anyway — by triggering the
item-67 refusal and asserting it arrives persistent with its remedy text intact.

---

### 70. The Data Quality pop-ups — REMOVED v0.11.3

> "there is a message that comes as a notification when you load a new data … at first, that
> pop saying what you need to do to your data was useful but now, it is not."

**The reason it wore out is more useful than the removal.** The observer fired on `active_ds()`
— on dataset **activation**, not on load. So clicking between datasets in the left rail, which
is a navigation action, replayed the whole stack of warnings about data the user had already
seen. One notification per issue, every time, unprompted and undismissable except by waiting.

A diagnostic that repeats on navigation stops being information and becomes furniture — and
worse, it trains the user to ignore the notification channel, which is the same channel errors
use. Removing it protects item 69's work.

`.quality_check()` is **kept and deliberately unwired**, with a comment at the old call site
saying so, so nobody reads it as dead code. The analysis was right; the delivery was wrong.

**Where it should return:** a panel the user opens when they want it — collapsed by default,
on the data screen or in Recommend. Pull, not push. Not built yet, deliberately: it should be
designed as something declined by default rather than re-added as a quieter interruption.

---

### 71. The CV caveat was styled as a footnote — FIXED v0.11.4 (item 68a)

Item 68 recorded that the cross-validation caveat had never been looked at, and traced the
cascade without a browser: `DT` injects the caption as a bare `<caption>` with no class,
bootstrap paints bare `caption` with `--bs-secondary-color`, and `ui.R` maps that to `--bark`,
the per-theme **secondary** text colour. Legible in every theme — and rendered in the
lowest-emphasis style the table has. A statement that the number beside it was computed from
less data than it claims, styled as a footnote.

**Fixed by giving the caveat its own hook rather than moving it.** Position is not the problem:
a caveat moved away from the number is a caveat nobody reads. `.prf_dt()` now wraps the note in
`<span class="ea-cv-note">`, and `ui.R` styles it as a bordered chip using
`color-mix(in srgb, var(--warn) 18%, transparent)` — translucent, so it takes its lightness
from whatever is behind it in every theme rather than being a fixed tint that suits one
(gotcha 31).

#### Three faults in the fix itself, all caught by the guard

1. **A literal `"` inside a CSS comment in `tags$style(HTML("…"))` broke the R parse** — gotcha
   1, in the very file that documents it. The comment contained a quoted phrase.
2. **DT escapes a CHARACTER caption wholesale.** The first version built the span as a string,
   so it arrived as `&lt;span class='ea-cv-note'&gt;` — **visible angle brackets on screen**,
   which is worse than the understyling it was meant to fix. It has to be a tag:
   `htmltools::tags$caption(cap, tags$span(class = "ea-cv-note", note))`. DT does not re-escape
   a tag, and htmltools still escapes the message text, so a note containing `<` or `&` stays
   safe. There is now a CONTROL assertion for exactly this (`!grepl("&lt;span", cap)`), because
   the class-presence check passed while the page rendered brackets.
3. **`as.character()` on a bslib page does not walk the whole tree.** The assertion that the
   style rule reaches the rendered UI failed against a UI that was correct — most of the
   stylesheet was simply absent from `as.character()`'s output. `htmltools::renderTags()` is
   the right idiom, as `check_ui_js.R` already knew. A CONTROL now asserts the stylesheet is
   present at all before asserting the new rule is in it.

**Still not verified visually.** The guard proves the markup, the escaping and the presence of
the rule. Whether the chip *looks* right — contrast against each of the five palettes, wrapping
on a narrow panel — remains an eyeball job. Item 68 stays open for that reason, now narrowed to
appearance alone.

---

### 72. Interactive codebase schematic — BUILT 2026-08-09

> Asked for an interactive schematic of the codebase, to check the structure against what it is
> expected to look like. First attempt was a filterable file list; corrected to an actual
> node-and-edge diagram.

**https://claude.ai/code/artifact/826d910e-4c93-4304-9d48-bdf79a514125**

Three toggleable views over one graph — **load order** (`global.R` fanning out to foundation,
registries, runners and module groups, with `ui.R`/`server.R` binding in), **runtime wiring**
(the five pools flowing to their consumers, then to the workspace and the Co-Analyst context),
and **tool fan-out** (how 23 hand-written + 51 algorithm + 14 statistical entries become the
same 88 tool keys). Clicking a node isolates its connections. Edge style carries meaning: solid
sources, dashed binds/registers, dotted state flow. Themed from the app's own `ea_palettes`.

**Extracted from the code, not the docs** — load order from `global.R`'s `source()` calls,
bindings from `server.R`, tool keys from `mod_workspace.R`, registry counts by *calling*
`ea_algorithms()` / `ea_statistics()`. That is the entire point: it can disagree with the
written architecture, and it does.

#### CodeBoarding was considered and rejected

Checked rather than assumed: it supports Python, TypeScript, JavaScript, Java, Go, PHP, Rust
and C# — **not R**. Its static analyser has no parser for 33k lines of R, and it needs an LLM
API key per run. It also could not know that a sourced-but-unbound module is *deliberate* here;
that convention is local knowledge, which is exactly what makes ours worth keeping.

#### Three gaps between the docs and the code

1. **`ui.R` declares three view panels, not one per screen** — `projects`, `project`,
   `workspace`. The "one `.viewPanel` per screen wired into two navsets" model that CLAUDE.md
   and ARCHITECTURE.md still describe is gone; every analysis screen is a *tool* inside the
   workspace shell. Largest documentation drift in the repo. **Both docs need correcting.**
2. **Twelve module files are sourced but never bound**, deliberately — nine replaced by
   `statistics.R` entries, three by `algorithms.R` operations, each omission annotated in
   `server.R`. Nothing is broken, but **3,536 lines are parsed at every boot for no runtime
   benefit**. Open decision: delete, or move to a `superseded/` folder.
3. **`mod_annotator.R` is an orphan, not a deferred feature.** It groups with `mod_gee.R` /
   `gee_dictionary.R` under "not sourced", but those two are complete and deliberately un-wired
   pending Python and a GEE account. Annotation was *folded into* `mod_raster.R`, so this file
   has no future owner. 312 lines.

#### The number worth remembering

**65 of 88 workspace tools come from the two registries.** Capability is already mostly data
rather than code, which is the strongest evidence on record for the plugin direction
(item 61) — the pattern it would generalise already carries three quarters of the app.

**Regenerating:** the counts are a snapshot at v0.11.4 and will drift. Re-run the extraction
and republish the same file path to keep the URL.


---

### 52 continued — window controls shipped v0.11.5, undocking deliberately not

Built the half the backlog itself recommended first: *"Maximize is the highest value and the
cheapest — a full-canvas attribute table solves the cramped-strip problem on its own."*

**Shipped:** minimise, maximise, close, and drag-to-resize.

**The real bug was underneath the request.** The dock is built inside `.map_ui()`, so it is
destroyed and rebuilt on every map re-render — choosing a layer, toggling visibility, changing
basemap. The old collapse button toggled a class **on the dock** and rewrote its own label, so
both were thrown away at the first interaction and the panel sprang back open by itself. State
now lives on `<html>`, which survives every rebuild; the drag height is a custom property there
for the same reason. That is why collapsing never stuck, and it was not in the report — the
reporter only saw a cramped strip.

`.ea-wsx-attrhead` has advertised `cursor: ns-resize` since it was written, with nothing behind
it. Drag-to-resize now honours it. An affordance that promises and does not deliver is worse
than none.

**Undocking (a floating, draggable panel) was NOT built, on purpose.** The backlog flagged it as
a genuine step up needing position/size state, a drag implementation, and care not to fight the
workspace grid — and item 52's own note is the deciding argument: *a floating panel that covered
the map would fight click-to-identify*. Maximise gives the same benefit (a full-size table) with
none of that risk, and can be dismissed in one click. **Revisit only if maximise proves
insufficient in real use** — which is a question for the external testers, not for us.

**Header wording** was left as "Attributes · <layer>". The request asked for the header to name
the *action* ("Dock" / "Undock"); with undocking not built there is no state to name, and the
three buttons carry their own titles. Reopen this if undocking is later built.

**Guarded by `check_attrdock.R`**, which asserts the invariant that no screenshot would show:
state selectors rooted at `html.ea-attr-*`, buttons holding no state. It lifts `eaAttrSet` out of
the *rendered page* and runs it in node against a stub, so it tests what ships. One control was
over-broad on the first run and failed against correct code — a bare search for
`classList.toggle('collapsed')` also matched the split panes, which legitimately keep their own
collapse. Scoped to the dock.

---

### 54 revisited — the editing actions are now unblocked

"Zoom to selected" shipped in v0.10.18. **Edit attribute** and **add attribute** were held on the
grounds that the table is read-only and a write-back needs an undo mechanism that did not yet
exist — with the explicit instruction not to invent a second one.

**That mechanism now exists.** Item 38's delete-features work built a write path into
`vector_pool` with bounded undo (`.EDIT_UNDO_MAX <- 5L`) and an armed, visible edit mode. Both
actions can now be built on it rather than beside it.

Not built here — recorded so the dependency is not re-litigated later. The remaining design
question is narrower than it was: whether a cell edit joins the same undo stack as a delete
(it should) and whether adding a *column* belongs on that stack at all, since it is a schema
change rather than a data change.


---

### 65 built v0.11.6 — and the panel turned out to be upside down

Every piece the entry asked for shipped: an explicit stored order, persisted in the project,
`.draw_layers()` following it, and an HTML5 drag firing one event with the new order. Plus the
"related, worth doing in the same visit" move to top / bottom.

**But the entry's own premise was wrong in a way that mattered.** It said *"the order in the
panel IS the stacking order"*. It was the **inverse**. The panel listed pool order and
`.draw_layers()` added in that same order, and leaflet stacks the last overlay on top — so
vectors sat at the BOTTOM of the panel and on TOP of the map. Confirmed by checking that no
overlay sets a pane or `zIndex` (only the basemap does, at 0), so insertion order alone governs.

Fixed shipping the drag handle over it: dragging a row "up" would have pushed the layer **down**
the map. `layers()` is now top-first and `.draw_layers()` walks it in reverse. **The default is
the pool order reversed, so existing maps are pixel-identical** — only the panel's reading order
changed.

**Deliberate detail:** the automatic first-layer choice still reads `layers_pool()`, not
`layers()`. Correcting the panel should not change which layer opens active — that would be an
unrelated behaviour change smuggled in behind a reordering feature.

**Guarded by `check_layer_order.R`.** Its load-bearing assertion is the CONTROL that
`rev(layers())` still equals the historical pool order — the only thing between a future refactor
and every map silently restacking. Two harness faults were hit writing it, both recorded in the
file: a helper leaked `environment()` out of the `testServer` body (module internals live in its
PARENT, so `e$layers` was NULL), and the pools were fixtured with NULL values, which `.names()`
filters (gotcha 14) — emptying every pool and collapsing all 17 assertions to one table.

**Not done:** dragging does not auto-scroll the panel when the list is longer than the viewport,
which is exactly when dragging is worst. Move to top / bottom covers that case for now.

---

### 73. Ship EasyAnalysis as a QGIS plugin — open-source contribution direction

> "contributing to the open source community is something we want. this is why a part of the
> future direction is to have our tool as a plugin for qgis and others but qgis first."

Direction, not a task. Recorded now so the decisions below are not re-derived later, and so that
item 61's plugin SDK is designed with this as a target rather than retrofitted to it.

**Licensing is already right.** The repo is GPL-3 and QGIS core is GPL-2-or-later, so a GPL-3
plugin is compatible. Nothing to change — worth stating, because getting it wrong later would be
expensive to unwind.

#### The uncomfortable finding: do NOT port the algorithms

`algorithms.R` was written in the QGIS Processing idiom deliberately — one spec per operation with
`inputs`, `params`, `output`, `run` — so the obvious move is to expose its 51 operations as a QGIS
Processing provider. **That is probably the least valuable thing we could contribute.**

Most of those 51 already exist in QGIS, and often as the *same underlying tool*:

| Our group | Already in QGIS via |
|---|---|
| Vector — buffer, dissolve, centroids, clip | native Processing algorithms |
| Raster — reproject, resample, clip, mosaic, band calculator | GDAL provider |
| Terrain — slope, aspect, hillshade, TPI, TRI, roughness | native + GDAL DEM |
| Hydrology — fill, flow accumulation, TWI | SAGA / WhiteboxTools providers |

We **already call WhiteboxTools** for depression filling and flow accumulation (`fill_wb`,
`algorithms.R:429`) — the same engine QGIS ships a provider for. Re-exporting it through a plugin
adds a layer and no capability.

**This needs a per-operation audit before anyone acts on it.** The table is from knowledge of the
QGIS ecosystem, not from checking our 51 specs against a real QGIS install. A few will have no
equivalent — our Zevenbergen & Thorne curvature (which exists because `terra` has no curvature
variable at all) and the LiDAR surface chain are the likely survivors.

#### What is actually worth contributing

The things QGIS does **not** have:

1. **`statistics.R` — 14 methods with role-based variable declaration.** QGIS has essentially no
   statistical modelling: no mixed models, no GLMM, no survival, no ordinal or robust regression,
   no discriminant analysis. A user with an attribute table and a question has to leave QGIS to
   answer it. **This is the gap, and it is the part of our codebase with no equivalent anywhere in
   the QGIS ecosystem.**
2. **The analysis → map round trip** (item 42): fit a model on a layer's attributes and write
   fitted values and residuals back onto the features, ready to symbolise. That is the whole point
   of doing statistics *inside* a GIS rather than beside it.
3. **The AI Co-Analyst**, which runs analyses rather than describing them.

The plugin's pitch is therefore *"statistical modelling for your vector layers"*, not *"more
geoprocessing"*.

#### The hard constraint: QGIS plugins are Python, our core is R

| Option | What it is | Trade-off |
|---|---|---|
| **A. Python provider, R underneath** | Processing algorithms that shell out to `Rscript` against the existing `statistics.R` specs. | Keeps ONE implementation. Requires R on the user's machine — the real adoption question. |
| **B. Embed the app in a dock** | `QWebEngineView` pointing at a locally-run EasyAnalysis. | Fast to build, but it is our app in a QGIS-shaped window rather than a plugin: no Processing interop, no model-builder support, does not feel native. |
| **C. Reimplement in Python** | `statsmodels` / `scikit-learn` equivalents of the 14 methods. | No R dependency, but forks the numerical core — two implementations of every method, contradicting the rule that a method has one implementation shared everywhere. |

**Leaning A.** It keeps one implementation and matches item 64's stated policy (R for statistics).
The R dependency is the thing to solve rather than route around — and there is precedent: SAGA,
GRASS, WhiteboxTools and OTB are all QGIS providers requiring an external install, so this is
accepted practice in that ecosystem rather than a novel imposition.

#### Relationship to item 61 — and why 61 comes first

**These are the same abstraction.** If our own tools move onto a plugin SDK, a QGIS Processing
provider becomes a *second backend* for that SDK rather than a parallel port. Item 72's schematic
put a number on why that is plausible: **65 of 88 tools already come from the two registries**, so
capability is mostly data — and data is what can be re-emitted against another host's API.

Building the QGIS plugin first would mean hand-writing the export and then rewriting it when the
SDK lands.

#### Sequence, when this is picked up

1. **Audit** the 51 operations against a real QGIS install; keep only what has no equivalent.
2. **Land item 61's SDK**, with "emit a QGIS Processing provider" as an explicit target of the
   spec format.
3. **Ship a provider** carrying the *statistics* registry plus item 42's write-back.
4. Only then consider dock/UI integration, if it is still wanted.

**"and others" — recorded, not scoped.** ArcGIS (Python toolbox), R itself (the methods are
already R functions and could be a package on their own), and a Python/Jupyter API are all
plausible second targets. QGIS first, as instructed.


---

### 13 revisited 2026-08-09 — step 1 done, and the integration was quietly broken

> Asked directly whether WhiteboxTools is fully integrated. It is not, and it was worse than
> "only a few tools": the two we did expose could not run at all on a fresh machine.

**What was wrong.** WhiteboxTools is TWO installs — the `whitebox` R package (a thin wrapper) and
the WhiteboxTools **executable**, a separate ~90 MB download fetched by
`whitebox::install_whitebox()`. `launcher/deps.R` listed `whitebox` in `extras`, so the *wrapper*
installed and `requireNamespace("whitebox")` returned TRUE — **the guard passed on every machine
that had ever run the installer.** Nothing anywhere called `install_whitebox()`. So the run
proceeded and then failed inside WhiteboxTools with a missing-file error, rather than telling
anyone what to install.

This is gotcha 32's shape exactly: *verifying a proxy for the dependency is not verifying the
dependency.* `requireNamespace()` proved the wrapper, never the program.

**Fixed in v0.11.7 — this is step 1 of the integration architecture above:**

- `.ea_require_whitebox()` (helpers.R) checks the **program** via
  `whitebox::check_whitebox_binary()`, wrapped because older package versions throw rather than
  return FALSE when the binary is absent — which is precisely the case being guarded. Replaces
  the `requireNamespace`-only guard at all three call sites (`algorithms.R` ×2, `mod_hydro.R`).
- `launcher/deps.R` now downloads the program once, where the user has already consented to
  installing dependencies — not at the point of use, where a 90 MB download in the middle of an
  analysis would be a surprise. Non-fatal: it is an extra, the download can fail on a restricted
  network, and the app must still start.

**Control-tested:** with the binary present the guard passes; with `check_whitebox_binary()`
forced to FALSE, and separately forced to throw, it blocks with an actionable message. **The old
guard passed in all three cases.**

**Still open — steps 2 and 3, and this is the real answer to "is it integrated".** We expose
**2 of 700+** WhiteboxTools algorithms (`fill_wb`, `flowacc_wb`). Step 2 (wrapping the useful
`wbt_*` tools as `algorithms.R` entries) and step 3 (reading their file outputs back into the
pools) are untouched.

**Note the tension with item 73.** If the QGIS direction were pursued, most of what step 2 would
add is already available to QGIS users through the WhiteboxTools provider. That does not argue
against doing it here — our users are in *this* app — but it does mean step 2 is about making
**EasyAnalysis** complete, not about contributing something new. Worth knowing before spending
weeks on it.

---

### 74. WhiteboxTools as a PROVIDER, not 484 wrappers — investigated 2026-08-09

> "instead of wiring all of the 800+ tools, can we create a centralized system that works with
> the registry to call to the tools? like treat it as a plugin?"

**Yes, and the tool describes itself well enough to make it clean.** Investigated rather than
assumed; every number below is measured on this machine.

#### What WhiteboxTools exposes about itself

`whitebox::wbt_tool_parameters("<Tool>")` returns **structured JSON** per tool:

```json
{"parameters":[
  {"name":"Input DEM File","flags":["-i","--dem"],"description":"Input raster DEM file.",
   "parameter_type":{"ExistingFile":"Raster"},"default_value":null,"optional":false},
  {"name":"Output File","flags":["-o","--output"],
   "parameter_type":{"NewFile":"Raster"},"optional":false},
  {"name":"Fix flat areas?","flags":["--fix_flats"],
   "parameter_type":"Boolean","default_value":"true","optional":true},
  {"name":"Maximum depth (z units)","flags":["--max_depth"],
   "parameter_type":"Float","optional":true}]}
```

Name, CLI flag, description, type, default and optionality — everything a spec needs.
`wbt_list_tools()` gives **484 tools** with one-line descriptions.

#### The type vocabulary is small and closed

Sampled across ten tools spanning hydrology, terrain, raster and LiDAR:

| WhiteboxTools `parameter_type` | Our spec |
|---|---|
| `{"ExistingFile":"Raster"}` | `ea_in(key, label, "raster")` |
| `{"ExistingFile":"Lidar"}` | `ea_in(key, label, "las")` |
| `{"ExistingFile":"Point"}` / `"Vector"` | `ea_in(key, label, "vector")` |
| `{"NewFile":"Raster"}` | `ea_out("raster", default)` |
| `"Float"` / `"Integer"` | `ea_num()` |
| `"OptionList": ["a","b","c"]` | `ea_sel()` — **the choices are in the type itself** |
| `"String"` | `ea_txt()` |
| `"Boolean"` | **`ea_bool()` — does not exist yet, needs adding** |

Eight cases. That is the entire mapper.

#### Why one `run()` serves every tool

WhiteboxTools is uniformly file-based: `system()` on `whitebox_tools.exe` with `--flag=path`
arguments in and files out. So the closure is identical for all 484 —
write raster inputs to temp `.tif`, assemble flags from the params, call
`whitebox::wbt_run_tool(tool, args)`, read the output back with `terra::rast()`. **No per-tool
code at all.** That is the same argument the registry itself rests on, applied one level up.

#### The one hard constraint: metadata is SLOW

**0.55 s per `wbt_tool_parameters()` call — 484 tools is 266 s (4.4 minutes).** Each call spawns
the executable. So enumeration must never happen at boot or on demand:

- build the manifest **once**, cache it to disk as JSON, key it by `wbt_version()`;
- ship a prebuilt manifest so a fresh install pays nothing;
- rebuild only when the WhiteboxTools version changes.

This is the piece that decides whether the feature feels instant or broken, so it is not an
optimisation to defer.

#### Curation is the real problem, not plumbing

484 tools added to the current 88 makes **572**. Dumping them into the picker would make the app
harder to use, not more capable — the exact failure item 67 is already about. Needed:

- **Categories.** `wbt_toolbox()` is **broken**: it panics with
  *"Unrecognized tool name …whitebox_tools.exe"* because the R package passes the executable path
  where a tool name belongs. Categories must come from elsewhere — per-tool `wbt_toolbox(tool)`,
  or the published tool index.
- **A curated default set** surfaced in the menus, with the remaining hundreds reachable only by
  search. Coverage is not the goal; *finding the right tool* is.
- **Provenance in the label**, so a Whitebox tool is visibly not one of ours.

#### Shape of the change

`ea_algorithms()` becomes a concatenation of **providers** rather than one hand-built list:

```r
ea_algorithms <- function() c(ea_provider_builtin(), ea_provider_whitebox())
```

`ea_provider_whitebox()` reads the cached manifest and emits specs. Everything downstream —
`mod_algo.R`, the workspace registration loop, `server.R`'s binding loop, the worker routing —
already works on whatever the registry returns, so **nothing else changes**.

**This is item 61's plugin SDK arriving through the back door, and that is an argument for doing
it here first:** a provider that adapts an external toolbox is a smaller, testable instance of
exactly the abstraction item 61 needs, against a real tool rather than a hypothetical one. If the
provider interface survives WhiteboxTools, it will survive a plugin.

#### Supersedes item 13 step 2

Item 13 proposed hand-wrapping a chosen handful of `wbt_*` tools. **Do that only if the provider
proves unworkable** — hand-wrapping is more code, covers less, and goes stale when WhiteboxTools
updates, whereas a manifest rebuild picks up new tools for free.

#### Verified while investigating: Stop is NOT leaking processes

Flagged as a plausible risk beforehand, and **it turned out to be wrong** — recorded so nobody
re-opens it. whitebox invokes the tool with a plain blocking `system(exeargs, intern = TRUE)`,
so `whitebox_tools.exe` is a child of the worker R process. Tested three times: spawn an external
program from inside a `callr::r_session`, `kill()` the session, check the child. It dies every
time. `callr` uses `processx`, which places children in a Windows job object, so the whole tree
goes down together. No orphaned processes, no action needed.

---

### 74 — engine BUILT v0.11.8 (`plugins.R`); the plugin menu is phase 2

> Refined the design: a **Plugin menu** where WhiteboxTools is activated by the user, not
> automatically — "it's an external tool and we did not develop it. we add it to make our
> platform stronger." Ideally **individual tools** activatable too, with **search finding tools
> that are not yet activated** so a user can enable one straight from the result. And a curated
> list of popular tools, looked up rather than guessed.

**All of that is the right design, and the measurement backs the speed argument.** Binding one
algorithm module costs **33 ms**, so registering 484 WhiteboxTools entries would add **~16 s to
every session start** plus 484 sets of observers. Activation must therefore gate *binding*, not
merely menu visibility. (The 266 s metadata enumeration is a separate, once-only cost.)

#### Built in v0.11.8 — `plugins.R`, the engine

- **Opt-in state** at `<home>/plugins/state.json`. Deliberately NOT in the project: activating a
  tool is a preference about this installation, not data about one analysis. Provider-level and
  per-tool switches; turning the provider off hides everything **without losing the per-tool
  picks**.
- **Manifest** — `wbt_list_tools()` plus `wbt_tool_parameters()` and `wbt_toolbox()` per tool,
  cached to disk and keyed by `wbt_version()` so an upgrade rebuilds it and nothing else does.
  Roughly **1 s per tool** (0.55 s parameters + 0.47 s category), so ~8 minutes for all 484 —
  which is exactly why it is an explicit, progress-reported action and never happens at boot.
- **Type mapper**, eight closed cases, `ea_bool()` added to the spec vocabulary for the one type
  nothing hand-written had needed.
- **One `run()` closure for all 484**, because WhiteboxTools is uniformly file-based. There is no
  per-tool code anywhere.
- **Search index** — `ea_wbt_catalogue(query)` searches the manifest, so a tool that has never
  been activated is still findable, and each result reports `active` and `featured` so it can be
  enabled from the result. This is what keeps the app fast **without hiding capability**: the
  index is text, and text is cheap.
- **`ea_algorithms()` now concatenates providers.** Everything downstream — `mod_algo.R`, the
  workspace registration loop, `server.R`'s binding loop, worker routing — already operates on
  whatever the registry returns, so nothing else changed.

#### The featured set — looked up, then verified against the installed catalogue

31 tools: the DEM-to-streams hydrology chain (`FillDepressions`,
`BreachDepressionsLeastCost`, `D8Pointer`, `D8FlowAccumulation`, `DInfFlowAccumulation`,
`WetnessIndex`, `ExtractStreams`, `StreamLinkIdentifier`, `Watershed`, `Basins`, `Sink`), the
common geomorphometric derivatives (`Slope`, `Aspect`, `Hillshade`, the three curvatures,
`RelativeTopographicPosition`, `RuggednessIndex`, `MultiscaleTopographicPositionImage`,
`HypsometricAnalysis`, `FeaturePreservingSmoothing`), the LiDAR gridding/filtering set, and three
image filters.

**Every name was checked against `wbt_list_tools()` on the installed version**, and the check
re-verifies it on every run — a featured tool that did not exist would render a broken row with
no way to tell why.

#### Verified by `check_plugins.R` (26 assertions)

The load-bearing one: **a generated spec runs end to end.** `Slope` was mapped from JSON,
executed against a synthetic DEM and returned a real raster (2.07–17.06°). Plus the control that
matters for speed — provider ON with no tools activated still contributes nothing.

#### Phase 2 — not built

- **The Plugin menu itself:** a screen listing providers with authors and licence
  (WhiteboxTools is Prof. John Lindsay's; the R wrapper is MIT, Qiusheng Wu and Andrew Brown),
  an Enable switch, a "build catalogue" action with progress, and the searchable tool list with
  per-tool toggles.
- **Lazy binding.** Activation currently changes what `ea_algorithms()` returns, but `server.R`
  binds at session start, so a newly activated tool needs a reload. The fix is to bind on **first
  open** rather than on activation — otherwise activating 50 tools costs 1.7 s and reintroduces
  the problem the design exists to avoid.
- **A project that used a now-inactive tool** should say so on open, like the missing-spatial-file
  flag, rather than silently lacking it.


---

### 74 phase 2 BUILT v0.11.9 — the Plugin menu

**More -> Plugins.** Built to the design as given: opt-in provider, per-tool activation, and
search that reaches tools which are not yet enabled.

- **Provider card** naming the authors — Prof. John Lindsay, R package by Qiusheng Wu and
  Andrew Brown (MIT) — and linking out. Enabling work another team wrote should be a visible
  decision, not a feature that silently appeared.
- **Per-tool switches** reuse the layer-visibility switch idiom, so it reads as the same kind of
  control rather than a new one.
- **Search covers the whole catalogue** regardless of activation, and each row can be switched on
  from the result. This is the part that keeps the app fast without shrinking it.
- **Indexing runs in the background** (`ea_wbt_build_async()`, `callr::r_bg`). Shiny is
  single-threaded, so an in-process build would freeze the app for the whole ~8 minutes
  (gotcha 29); even the 31 featured tools would block for ~30 s. The child prints one line per
  tool and the module polls stdout, so progress needs no shared state between processes.

#### The limitation, and why it was not papered over

**A newly enabled tool needs a page reload, and the UI says so.** `MODUI` is built once at
workspace construction and `server.R` binds at session start, so immediate activation means
making the tool catalogue reactive and binding modules mid-session. Tools enabled in a *previous*
session are present at boot, so this only affects the session in which you enable something.

Binding on activation was considered and rejected: at 33 ms each, enabling 50 tools costs 1.7 s
and reintroduces exactly the cost this design exists to avoid. **The correct fix is binding on
FIRST OPEN**, which is still open.

#### Still open from this item

- Lazy binding on first open, so no reload is needed.
- A project that used a now-disabled tool should say so when it opens, like the missing-file flag.
- Only WhiteboxTools has a provider. The interface is deliberately general — `ea_algorithms()`
  concatenates providers — so a second one is the test of whether this generalises to item 61.

---

### 74 phase 2b — activation without a reload, FIXED v0.11.10

> "page reload. thats not convenient. we cant do that. same way we manage installed packages, we
> could do the same. so is the plugins foundation solid?"

**Correct on both counts, and the honest answer to the question is: solid underneath, weak at one
joint.**

Solid and proven: state on disk, the manifest cache, the type mapper, generated specs, one
`run()` closure for all 484, provider concatenation into `ea_algorithms()`. A generated spec
runs end to end.

**Not solid: two loops assumed a STATIC registry.** `MODUI` was built once at workspace
construction, and `server.R` bound algorithm modules in a one-shot `lapply`. Neither was a flaw
in the provider design — both were assumptions made when the registry could only change between
sessions. That is why a newly enabled tool needed a reload, and the package analogy is exactly
right: installing a package does not make you restart R.

#### What changed

- **`MODUI` is now a reactive.** The construction block became `.build_modui()` and
  `MODUI_R <- reactive({ plugin_epoch(); .build_modui() })`; the ten consumer references read
  the reactive, so menus, the tool picker and search all rebuild when activation changes.
  Rebuilding the list is metadata only — nothing like the 33 ms-per-tool cost of *binding*.
- **Binding is incremental and idempotent.** `.bind_algos()` walks the registry and binds only
  ids not already in `.algo_bound`. Enabling one tool costs one binding (~33 ms, imperceptible);
  enabling nothing costs nothing. The guard matters: re-binding an id would create a **second
  set of observers on the same namespace**, and duplicate observers on a Run button show up as
  an operation silently running twice.
- **`plugin_epoch`** ties them together. `pluginsServer(on_change =)` bumps it on every state
  change; `server.R` binds what is new and the workspace rebuilds its catalogue from the same
  signal.
- All "reload the page" wording removed from the UI, because it is no longer true.

**Proven by `check_plugins.R`** (40 assertions), with the control that matters: the tool is
absent from the workspace catalogue before enabling and present **in the same session** after,
carrying its provenance label. Plus: a first bind pass binds 52 entries, a second binds **zero**,
and enabling one more tool binds exactly one.

#### Still not dynamic: the Co-Analyst context

`module_ctx` is assembled once as a plain list after the initial binding, so a tool enabled
mid-session is usable but does not yet report itself to the Co-Analyst until the next session.
Recorded rather than hidden. Making it dynamic means `module_ctx` becoming `reactiveValues` —
small, but it touches every module's registration and is not worth bundling into this change.

---

### 75. More providers — GeoAI, GeoLibre, and features that are NOT plugins

> "document adding geoai, geolibre and other plugins too would be nice. like the swipe feature
> and so on."

Recorded as direction. **The most useful thing this entry can do is draw a line**, because the
three examples named are three different kinds of thing and treating them alike would produce a
bad abstraction.

#### They are not the same kind of thing

| | What it is | How it should arrive |
|---|---|---|
| **WhiteboxTools** | An external *tool library* — 484 file-in/file-out algorithms that describe themselves | **A provider.** Done (v0.11.8–0.11.10). |
| **GeoAI** | Deep learning for geospatial data — segmentation, feature extraction. **Python.** | **A provider, but a different backend.** See below. |
| **GeoLibre** | The project this app's whole layout is modelled on (DESIGN.md north star) | **A source of feature ideas**, not a tool library to wrap. |
| **Swipe** | Drag a divider to compare two layers on the map | **A map feature.** Belongs in `mod_workspace.R`, nowhere near the plugin system. |

**Swipe is the clarifying case.** It is a map *interaction*: no inputs from a pool, no output
layer, nothing to run. The provider interface generates **algorithm specs** — things that take
layers in and produce a layer out. Forcing swipe through it would mean inventing a spec kind for
"a UI gesture", which is how a clean abstraction turns into a grab-bag. Same reasoning already
applied to "Crop to drawn shape" and "Clip vector to drawn shape", which stayed in
`mod_raster.R` because they read a polygon drawn on the map rather than a pool entry.

**So: swipe is worth building, and it is not a plugin.** Alongside it, the same family from
GeoLibre and QGIS: layer transparency slider, split-screen compare, a magnifier/spyglass.

#### GeoAI is the real test of the provider interface

It is the second provider, and deliberately the *hard* one, because it differs on every axis
that matters:

- **Python, not R** — the first exercise of item 64's policy (R for statistics, Python under the
  hood for deep learning). Needs a transport decision: `reticulate`, or a subprocess with files
  in and files out, which is what WhiteboxTools already does and what the current `run()` shape
  fits.
- **Models are downloads, often large**, so the manifest/cache pattern extends to weights, and
  the opt-in argument gets stronger, not weaker.
- **GPU is optional and machine-specific**, so capability detection has to be honest — a tool
  that will take four hours on CPU should say so before it starts.
- **Self-description is unlikely.** WhiteboxTools describes its own parameters, which is what
  made generation possible. A Python library probably will not, so this provider likely needs a
  hand-written spec list — meaning the interface must support **both** generated and declared
  providers. That is the design question to answer before writing any of it.

If the provider interface survives GeoAI, it is the plugin SDK of item 61 in all but name.

#### Sequence

1. **Swipe and the compare family** — a map feature, independent of all of this, and the
   cheapest visible win.
2. **A second *generated* provider** if a self-describing tool library presents itself — it would
   confirm the interface generalises before the harder case.
3. **GeoAI**, once the transport and the declared-vs-generated question are settled.
4. **GeoLibre** as a feature backlog, mined for interactions rather than wrapped.

**Not started.** Recorded so the distinction between a provider and a feature is settled before
anyone builds the wrong one.

---

## Round 8 — plugin surfacing, menu cleanup, and large files (2026-08-09)

Reported together after testing v0.11.10. Item 76 is partly fixed already; the rest are recorded
only, as instructed.

---

### 76. Plugins must behave like Packages — a dialog, not a screen — **DONE v0.11.12**

> "plugins should have the same behavior as packages. not a full screen just the pop up that
> shows up. learn from packages screen. … not in the sidebar too."
> Also: "plugins should be in the menu. same position as Packages." / "I think it is only
> positioning."

**Two faults, one fixed.**

**(a) It was invisible — FIXED v0.11.11.** `Plugins` was registered as a workspace *tool* under
group `More`, so the only route to it was **Analysis → More → Plugins**, a nested fly-out. Built,
tested, and effectively unreachable — **item 67 repeating in a new place**, and my own check made
it worse: it asserted the tool was *registered* and its server *bound*, never that anyone could
find it. Now a top-level `.menu("Plugins", …)` beside Packages. The dead
**Packages → Optional engines → "Whitebox tools" (disabled)** placeholder was removed in the same
change: a greyed-out entry next to a working one is how a user concludes the feature does not
exist.

**(b) It is still the wrong KIND of surface — OPEN.** Packages opens a **modal dialog**
(`Install a package…`, `Optional packages…`, `Installed packages…`); Plugins opens a full canvas
screen and occupies the tool sidebar. Managing plugins is a *settings* action, not an analysis —
it should not displace the map or the tool panel.

**What to build:** convert `mod_plugins.R` from the canvas+tools contract to a modal, modelled on
the Packages handlers in `mod_workspace.R` (`pkg_install_ui`, `pkg_optional_ui`, `pkg_list_ui`).
The provider list, search box and per-tool switches all fit a dialog; nothing about them needs a
canvas.

**And the general form, explicitly asked for:** *"i hope we can have a general settings for this
for future use"* — a reusable **settings-dialog pattern**, so Packages, Plugins, Preferences and
whatever follows are one implementation rather than three lookalikes. Packages is the existing
example to extract from, not a fourth thing to copy.

---

### 77. Search must reach tools that are not activated, and show provenance — **DONE v0.11.15**

> "you search a command, and it opens in the sidebar (that is established already). if not
> activated, have the activate there for whitebox. if its not from whitebox, no need to activate."
> "search isn't finding whiteboxtools at all. i searched a simple one lastoshapefile and nothing
> returned."
> "when it starts to work, we dont know if we are using whitebox tools or not. we need some way
> to show it."

**The report is correct, and there are two separate reasons for it.**

1. **The app's tool search only searches `MODUI`** — the registered tools. An unactivated
   WhiteboxTools tool is deliberately not in `MODUI` (that is what keeps the app fast), so it can
   never appear. `ea_wbt_catalogue()` exists and searches the full 484, but **nothing calls it
   except the Plugins screen** — the same "a function nobody calls proves nothing" fault as
   gotcha 32.
2. **`LasToShapefile` would not have been found even by the Plugins screen**, because the
   catalogue has to be indexed first and indexing had almost certainly never been run. An
   un-indexed catalogue searching to zero results is indistinguishable from a broken search.

**What to build:**
- The workspace search queries `MODUI` **and** `ea_wbt_catalogue()`, merging results.
- A result for an inactive tool opens in the sidebar as normal but shows an **Activate** control
  in place of Run. Activation already takes effect without a reload (v0.11.10), so the tool
  becomes usable in-place.
- **Non-provider tools show no activation control at all** — as specified.
- If the catalogue is not indexed, the search must **say so and offer to index**, never return an
  empty list. Empty results are how a user concludes a feature is broken.

**Provenance — "we need some way to show it".** The generated label already carries
`(WhiteboxTools)`, but that is not enough: it must be visible **on the tool panel while running**
and **on the resulting layer**, so it is obvious at the moment of use which engine produced a
result. Proposed: a small provider badge in the tool header, and provider recorded on the output
layer so it survives into the project.

---

### 78. Menu cleanup — R Console standalone, and delete "More" — **DONE v0.11.14**

> "Put R console in the top menu by itself and remove it from other places."
> "'More' must be deleted. it adds no value. the options under More are already positioned in
> other places in the app."

- **R Console** currently hangs off the View menu (`.mi("R Console", …)` toggling
  `#<ns>-console`). It should be its own top-level menu item, and every other entry point
  removed, so there is exactly one way to reach it.
- **The `More` group** holds Documentation, References and (until item 76) Plugins. Documentation
  and References are reachable elsewhere; Plugins is now a top-level menu. So the group is a
  container with nothing that needs containing. Delete it — and delete the *group*, not just its
  members, or an empty fly-out remains.

**Care:** the group is derived from each entry's `grp` field, so deleting it means re-homing
`mod_docs.R` and `references.R` rather than dropping them.

---

### 79. Uploads are capped at 3 GiB and the rejection is SILENT — **FIXED v0.11.16**

> "I loaded a 4gb file for testing large rasters and no failure but i did not see it. did you cap
> data upload size and allows it fail silently? there should be no cap."

**Both halves confirmed by reading the code — this is not a guess.**

- `global.R:46` sets `options(shiny.maxRequestSize = 3 * 1024^3)` — **3 GiB**. A 4 GB file is
  3.73 GiB, so it is **over the cap and rejected**.
- The handler is `observeEvent(input$upload_files, { req(input$upload_files); … })`. When Shiny
  rejects an oversized upload the input never populates, so **`req()` halts the observer with no
  message at all**. The file vanishes with no error, which is exactly what was described.

**This is the worst failure shape in the app**: not a wrong answer, not a visible error — nothing
at all. It is the same family as the self-deleting error messages fixed in v0.11.3, and worse,
because there is not even a message to miss.

**What to do:**
- **Remove the cap** as instructed (`Inf`, or a number far beyond any plausible file).
- **Surface a rejection regardless.** Even uncapped, a browser or disk limit can refuse a file, so
  the upload path must report "this file was not accepted" rather than silently doing nothing.
  A cap that is never hit is not a fix if the silence remains.
- **Reconsider the browser upload route for very large rasters entirely.** A multi-GB file is
  copied through the browser into a temp file before anything reads it. The app is local-first and
  already has a native folder picker (Tcl/Tk, pre-warmed in `global.R`) — **pointing at a file on
  disk** avoids the copy completely and is the right answer for this size class. Related to
  item 41 (data source manager).

---

### 80. Loading large files is painfully slow — **MEASURED v0.11.17; one fix shipped**

> "loading large files is painfully slow."

Recorded with the measurement not yet taken, deliberately: "slow" spans several distinct costs
and fixing the wrong one wastes the effort. The candidates, in the order they are likely to
dominate for a multi-GB raster:

1. **The browser upload copy** (item 79) — the file is transferred and written to a temp
   directory before any code sees it. For multi-GB inputs this alone can dominate.
2. **Reading the whole raster into memory.** `terra` is lazy by default, but any operation that
   materialises values pays for all of it. LiDAR already has a read-time cap
   (`.read_las_capped`, 5 M points); rasters have no equivalent.
3. **Display preparation.** `.disp_raster()` already downsamples *before* reprojecting — a fix
   worth 18.1 s → 3.2 s when it was made — so this path is already optimised and is probably not
   the culprit.

**Next step is measurement, not optimisation:** time upload / read / first-draw separately for a
large file and fix whichever dominates. A progress indication is needed either way — the global
"Running…" pill covers server-side work but **not** the browser-side upload, which is precisely
the phase that feels like a hang.


---

### 76b built v0.11.12 — Plugins is a dialog, and the shape is reusable

> "plugins should have the same behavior as packages. not a full screen just the pop up that
> shows up. learn from packages screen. … and i hope we can have a general settings for this for
> future use. not in the sidebar too."

**Done, learned from Packages rather than invented alongside it.**

- **`ea_settings_modal()` (helpers.R) is the general shape asked for.** Extracted from the
  Packages modals — title, optional hint, body, footer — so Packages, Plugins, Preferences and
  whatever follows are one implementation instead of three that merely look alike.
- **`pluginsCanvasUI` / `pluginsToolsUI` are gone.** The module no longer has a canvas or a tools
  panel and is no longer registered in `MODUI`, so it cannot take the centre or the sidebar. The
  menu fires an app-level `plugins_open`, exactly as the Packages items fire `pkg_*_ui`.
- Provider enable/disable and the two Index buttons **moved into the provider card**, because a
  dialog has no tools panel — and a settings action should not need one.
- The catalogue status became an inline "Indexing… <tool>" string rather than a panel block.

**One deliberate structural detail.** The search box is a **real `textInput` in the dialog shell**,
not inside the reactive body; only the card and the results list are `uiOutput()`s. Rebuilding a
text field on every keystroke wipes it mid-edit — gotcha 21, which this project has already been
bitten by once in the plot-appearance panel. `ea_settings_modal()` carries that warning in its
own comment so the next caller does not rediscover it.

**Guarded.** `check_plugins.R` gained controls for the *shape*, not just the behaviour: the canvas
and tools UI must be **absent**, the dialog must be built on `ea_settings_modal`, and the module
must **not** appear in `MODUI`. The reachability assertion was also retargeted — it used to
assert the tool was *registered and bound*, which passed while Plugins sat buried in an
`Analysis → More` fly-out nobody found. It now asserts the top-level menu exists. **Registration
is not reachability**, and that was the lesson of v0.11.11.


---

### 77 built v0.11.13 — search reaches unenabled tools, and provenance is visible

**Root cause of "search isn't finding whiteboxtools at all".** `eaToolSearch` is a **client-side
index of the rendered menu DOM** — it scrapes menu anchors and clicks the match. An unenabled
provider tool is not in the menu, so it was *structurally* invisible. No amount of typing would
have found `LasToShapefile`.

**What changed:**

- The search still indexes the menu (fast, unchanged for the 88 registered tools) and now also
  asks the server, which answers from `ea_wbt_catalogue()` — all 484, enabled or not. Results
  appear under their own **"Not enabled yet"** heading with an **Activate** control.
- **Non-provider tools never reach that path**, so they never show an activation control — as
  specified.
- Activating from a result **enables and then opens** the tool. Enabling alone would leave the
  user where they started, having asked for the tool twice.
- **An un-indexed catalogue now says so** and offers to index, instead of returning "No tools
  match". Zero results and an empty catalogue are indistinguishable to a user, and the second one
  is not a search failure.

#### The finding: not every WhiteboxTools tool can be a tool here

`LasToShapefile` — the very example reported — **declares no output parameter at all.**
WhiteboxTools writes the `.shp` beside its input, so there is nothing to put in a pool. The
mapper already refused to build a spec for it, correctly. But search would then have offered an
**Activate button that did nothing**, which is worse than not finding it.

So the catalogue gained a `usable` column, and:

- unusable tools are **still shown in search** — a user looking for one deserves to learn it
  exists — but marked **"Not supported"** with the reason on hover, and not clickable;
- `ea_tool_set()` **refuses** to enable one, with a message. Hiding the button is not enough:
  any other path would otherwise store an activation that silently produces nothing, which is
  indistinguishable from a broken app.

**This is a whole class**, not one tool: any WhiteboxTools tool with an implicit output is
affected. Supporting them properly means teaching the runner about "output written beside the
input", which is worth doing later and is recorded here rather than half-done now.

#### Provenance

`algoToolsUI()` shows a **WhiteboxTools badge** with the underlying tool name whenever
`spec$provider` is set — visible *while the panel is open*, not just in the tool's title, which
was the ask ("we don't know if we are using whitebox tools or not"). Built-in tools show no
badge: there is nothing to disclose. Both directions are asserted, the second as a CONTROL.


---

### 77 — the two gaps, and where they landed

Asked directly whether 77 was completely done. It was not, and the honest answer had two parts.

**Gap 1, closed in v0.11.14: provenance on the RESULT.** The badge added in v0.11.13 says what is
about to run, but three layers later nothing said which engine made which. The output object is
now stamped with `attr(res, "ea_provider")` (provider, tool, timestamp), and the completion
notification names the engine: *"Slope complete — added layer 'Slope' (via WhiteboxTools)."*

**Gap 2 was NOT a gap — I misread the request.** Clarified: *"sidebar is not for previewing the
options. its for when you select the tool. the search popup is where you activate the type of
tool but it shows that it is from whitebox."*

The sidebar shows a tool's options once **selected**; the **popup** is where activation happens
and where the source is disclosed. That is exactly what was built. **Item 77 is complete.**

The only change following the clarification: the popup heading now reads
**"WhiteboxTools - not enabled yet"** rather than just "Not enabled yet" — the popup is where the
decision to enable someone else's engine is taken, so whose engine it is should be unmistakable
there, not only in each row's label.

Kept below for the record, because the reasoning was wrong in an instructive way — I inferred a
sidebar-preview requirement from "opens in the sidebar" when that clause was simply describing
existing behaviour, not asking for anything:

> **What I wrongly believed was still open.** The request was:
*"you search a command, and it opens in the sidebar (that is established already). if not
activated, have the activate there for whitebox."* — i.e. the tool **opens in the sidebar** and
Activate lives **there**.

What was built instead: **Activate in the search dropdown**, which enables and opens in one click.

Both reach the same end state. The difference is whether you can **inspect a tool before enabling
somebody else's engine** — read its parameters and description, then decide. For an external
provider that is a real argument, and it is the reporter's own design.

**Why it was not simply built that way:** the sidebar panel is rendered from a registered tool, and
an unenabled tool is deliberately not registered — that is the mechanism keeping the app fast.
Previewing one means adding a single transient `preview_tool` entry to the catalogue and teaching
`algoToolsUI()` to render **Activate in place of Run** when the tool is not enabled. That is
bounded and doable; it was not smuggled in unasked after already substituting one design for
another once.

**Resolved: no decision needed.** The dropdown flow was the requirement all along.

---

### 78 built v0.11.14 — one R Console, no "More"

**R Console was in two menus with two different behaviours.** Analysis → R Console called
`eaConsole(..., 'dock')`; View → R Console toggled a CSS class directly. **Which one you found
decided what it did** — a genuine inconsistency, not just duplication. Both are gone; it now has
its own top-level menu with a single Open/close entry.

**"More" is gone from the menubar.** The claim that its contents are already positioned elsewhere
was verified before deleting anything: Documentation and References are both in the **Help** menu
(`mod_workspace.R:709-710`).

They could not simply be deleted, though — Help opens them **by tool key**, so unregistering them
would have broken Help. They are now marked `hidden = TRUE`: still real, still openable by key,
but contributing no menu entry. The group builder filters hidden tools and drops any group left
empty, so `More` disappears rather than becoming an empty fly-out.

**Guarded on the RENDERED menubar**, not the source — the question is what a user can see, which
is precisely the distinction v0.11.11 got wrong. Assertions: `More` absent, `Data` present as a
control that the test works at all, Documentation still reachable, and `R Console` appearing
**exactly once**.


---

### 79 fixed v0.11.16 — no cap, and the silence explained exactly

> "did you cap data upload size and allows it fail silently? there should be no cap."

**The cap is gone: `shiny.maxRequestSize = Inf`.** Not a larger number — any finite value is a
cliff somebody eventually walks off, and this report is what walking off it looks like.

Verified that Shiny tolerates `Inf` rather than assuming it: both places that read the option
compare with `>`, and `Inf` survives both guards.

- `ShinySession$@uploadInit`: `if (maxSize > 0 && any(sizes > maxSize)) stop(...)` — `Inf > 0`
  is TRUE (so uploads stay enabled; **0 would disable them entirely**) and `any(sizes > Inf)` is
  FALSE.
- `HandlerManager$createHttpuvApp`'s `onHeaders`: `if (maxSize <= 0) return(NULL)` — not
  triggered.

#### Why it was silent — now known precisely, not guessed

**Shiny rejects an oversized upload with `stop("Maximum upload size exceeded")` inside
`ShinySession$@uploadInit`, which is an RPC handler.** That error goes back over the websocket
and surfaces in the **browser console** — not in the app. The app's own handler never runs at
all, because `req(input$upload_files)` halts on an input that never populated.

So there were two layers of silence stacked: Shiny's rejection was invisible, and the app's guard
was a no-op. Neither could have produced a message.

#### The other half: a long upload must not look like a hang

Removing the cap fixes rejection, not **feedback**. A multi-GB file still takes minutes during
which Shiny shows only a thin progress bar — and the report was *"no failure but i did not see
it"*, which is as much about silence as about the cap.

The file input now reports its selection on the browser's `change` event, **before any bytes
move**, and the server answers with *"Reading 1 file (3.7 GB)… large files can take a while."*
It costs nothing and turns a silent wait into a stated one.

**Guarded by `check_upload.R`**, which asserts against Shiny's real expressions — the `> 0` guard,
the `any(sizes > maxSize)` comparison and the `<= 0` early return — with the reported 4 GB file
and a 10 TB file as the controls, plus a CONTROL that the old 3 GiB line is really gone.

**Not verified, and it cannot be here:** an actual multi-GB browser upload end to end. There is
no browser in this environment. The cap and the plumbing are proven; the round trip needs a real
file. That is worth doing before external testers, and it overlaps item 80.


---

### 80 measured v0.11.17 — it is not the reading, and one dead boot cost is gone

Measured before optimising, as the entry insisted. Test raster: **10,000 x 10,000 = 100 M cells,
0.37 GB GeoTIFF**, on this machine.

| Phase | Time |
|---|---|
| `terra::rast(path)` — the ingest path's only raster call | **0.06 s** (lazy; it reads no values) |
| `ncell` / `ext` / `crs` / `nlyr` metadata | 0.00 s |
| `minmax` / `setMinMax` | 0.00 s |
| Display prep: aggregate to <=400k cells | 0.65 s |
| Display prep: project to WGS84 | 0.26 s |
| **Total app-side work** | **under 1 second** |
| For comparison: project at FULL resolution first — the order that was fixed earlier | **50.00 s** |

**So the app is not what is slow.** Reading is lazy, display prep is already optimised, and the
55x win from the earlier downsample-before-reproject fix is confirmed rather than assumed.

**Disk is not it either: a plain file copy ran at 1,277 MB/s**, so writing a 4 GB upload to a temp
file costs about **3 seconds** on this machine.

**By elimination, the cost is the browser upload transport** — HTTP multipart plus Shiny's
chunked write, which is far slower than the 3 s the disk alone would take. That is item 79's
closing argument restated with numbers: for a local-first app, pushing a multi-GB file **through
a browser** to reach a file that is already on disk is the wrong route. The fix is to point at
the path, not copy the bytes, which needs the native picker.

#### Shipped now: a dead 1.61 s on every boot

`global.R` pre-warmed Tcl/Tk so "the native folder/file dialogs open instantly on first click".
**Those dialogs were deleted on 2026-07-27** in favour of the browser picker — and the pre-warm
was, by then, **the only reference to tcltk left anywhere in the live codebase**. It was warming
a feature that no longer existed, at a **measured 1.61 s per boot**, while startup was one of the
things being reported as slow.

Removed. If a native picker returns — and item 79 argues it should — pre-warm it again *then*,
next to the code that uses it.

#### Still open

- **The native path-based route** for large local files. This is the actual fix for the reported
  slowness, and it belongs with item 41 (data source manager) rather than being bolted onto the
  uploader.
- **Progress during the upload itself.** The `#ea-busy` pill covers server work, and the
  selection notice added in v0.11.16 covers the start, but the minutes in between still show only
  Shiny's thin progress bar.
- **A real multi-GB browser upload has still not been timed end to end** — there is no browser
  here. The reporter is testing one; that measurement will confirm or refute the elimination
  above, and it is the only piece of this that is guesswork rather than measurement.


---

### 81. A multi-layer GeoPackage lost every layer but the first — FIXED v0.11.18

> Spotted in the terminal while testing:
> `Warning in CPL_read_ogr(...): automatically selected the first layer in a data source
> containing more than one.`

**Real data loss, and the third instance of this project's worst failure shape.**
`sf::st_read(path)` on a source with more than one layer takes the FIRST and warns. Every call
site passed `quiet = TRUE`, so the warning went to the **console** — where nobody running the app
sees it. It surfaced only because a terminal happened to be visible.

**Reproduced before fixing:** a 2-layer GeoPackage loaded **3 of 5 features** and reported
success. Not a wrong answer, not a visible error — missing data that looks complete. The other
two instances were the self-deleting error messages (v0.11.3) and the silent upload rejection
(v0.11.16).

**Fixed with `ea_read_vector()` (helpers.R)**, which returns a **named list of every layer** so a
caller cannot accidentally keep one. Layers are named `<file>:<layer>` — after the layers
themselves, not `layer1`/`layer2` — and the file prefix stops two sources that both contain
`roads` from colliding in the pool. A single-layer file returns one entry named after the file,
so there is no special case at the call sites and no suffix to explain.

Applied at the upload path and the type-detection fallback, with a notification naming the layers
when there is more than one.

**And on reopening a project**, which was the subtler half. Each layer is a separate pool entry,
so restore has to read back *that* layer: `.spatial_get()` now takes the entry name and reads the
layer after the `:`. The read cache is keyed per layer too — without that, every layer of one
file would have returned whichever was cached first, which is the same bug hiding in a place
where the names still look right.

**Guarded by `check_vector_layers.R`**, whose load-bearing assertion is the CONTROL that plain
`st_read()` really does return 3 of 5 features. Without it, the fix would pass against a
single-layer fixture and prove nothing.


---

### 57 built v0.11.18 — and the honest answer to "can it be done fully?"

**For the 65 registry-hosted tools: yes, and it is done.** Verified rather than assumed — all 14
`statistics.R` `fit()` bodies and all 51 `algorithms.R` `run()` bodies deparse.

**For the ~23 hand-written screens: no.** They carry no spec, so each needs its own emitter. That
is the real boundary, and it is another argument for the registry: the tools that are *data* got
this feature for free; the ones that are *code* did not.

#### The decision that makes it trustworthy

The script is **not a reconstruction of the analysis**. It is the spec's own `fit`/`run` body,
**verbatim**, with the user's roles and parameters bound above it, plus the two internal helpers
(`%||%`, `.ea_formula`) so it stands alone in a plain R session.

Rewriting the body to inline values would mean maintaining a second rendering of every method,
which can drift from the first — and **a script that quietly disagrees with what ran is worse
than no script**, because it looks authoritative. Binding `df`/`r`/`p` and pasting the real body
cannot misrepresent anything, because it *is* what ran.

`library()` lines are derived by scanning the body for `pkg::`, so they cannot go stale either.

#### Proof

`check_script.R` does not inspect the text and call it done: it **executes** the generated script
in a fresh environment and compares coefficients with what the app computed.
**Max difference: 0.00e+00.**

It also asserts reachability — no button before a fit, a button after one — because a script
nobody can open is item 67 again. And a CONTROL that the body is verbatim, so replacing it with a
prettified reconstruction fails the check.

`data_expr` exists so the check can execute the script with a fixture instead of regex-patching
the generated text. A test that rewrites the artefact it is testing ends up testing its own regex.

**Not done:** `mod_algo.R` has the same one-line hook available (`ea_analysis_script()` already
handles `run`), and the 23 hand-written screens need per-module work.

---

### 82. THE DATA RULE — local-first, not a web app. How industrial tools do it, and the unified fix

> "the slowness is a nightmare. I think more test cases must be documented and formulated with a
> unified fix. how does industrial grade tools handle these?"
> "we should not operate like an online web app. its a local first app."

**Promoted to a non-negotiable rule in CLAUDE.md.** This entry is the reasoning behind it.

#### How industrial tools actually handle large data

Three families, all obeying the same handful of rules.

**Desktop GIS (QGIS, ArcGIS Pro).** Never uploads anything — it opens a path. Zero copy. Then:
- **Overviews / pyramids.** A raster carries downsampled copies at several resolutions (`.ovr`,
  or internal to a COG). Drawing reads the cheapest level that satisfies the screen, which is why
  a 50 GB raster opens instantly: it never reads 50 GB.
- **Windowed reads and spatial indexes.** Only the viewport is read; vectors use an R-tree, so
  features outside the view are never touched.

**Web GIS (Felt, Mapbox, Earth Engine).** The raw file never crosses the browser. Data sits in
object storage as **COG**, and the client fetches byte RANGES for the tiles it needs. Vectors
become vector tiles. Earth Engine goes further: computation is lazy and server-side, and the
client only ever receives a rendered tile or a small summary.

**Analysis platforms (Databricks, RStudio Server, JupyterHub).** The data already sits next to
the compute; you reference a path or a table. Columnar formats (Parquet, Arrow) give column
pruning and predicate pushdown, so a 100 GB table costs only the columns and rows asked for.

**The five shared rules** — now in CLAUDE.md:

1. Reference data in place; do not carry it.
2. Read only what the question needs.
3. Read at the resolution the **screen** needs, not the resolution the file has.
4. Stream and chunk; do not materialise.
5. Do the work where the data is.

#### Where this app actually stands — and it is the good position

**EasyAnalysis is local-first, so the data is already on the same machine as R.** It is in the
*best* of the three positions and should behave like desktop GIS, not like a web app.

The browser upload is an accident of Shiny being the UI, not a requirement of the architecture.
The app takes a file already on disk, copies it through an HTTP multipart transfer into a temp
file, and then opens it — **to reach a path it could have opened directly.** Rule 1, broken at
the front door.

Everything downstream is already right, and measured:

| | |
|---|---|
| `terra::rast()` on 100 M cells | **0.09 s** (lazy) |
| display prep (aggregate + project) | **0.9 s** |
| plain disk copy | **1,277 MB/s** -> a 4 GB write is ~3 s |
| `read.csv()` on a 92 MB CSV | **15.48 s**, on the main thread, UI frozen |
| `init_data()` after it | **0.00 s** |

So the app is not the cost anywhere except CSV parsing. The transport is.

#### The unified fix

**Reference data instead of carrying it, and read at the resolution the screen needs rather than
the resolution the file has.**

| # | Change | Fixes | Kind |
|---|---|---|---|
| 1 | **Path-based ingest** — add from disk, native picker | Upload slowness, for every file type at once | Architectural |
| 2 | **Overviews for display** — read a pyramid level | Display cost stops scaling with file size | Architectural |
| 3 | **`data.table::fread` for CSV** | 15.5 s -> ~1-2 s | Symptom relief |
| 4 | **Background the ingest** | UI freeze during long reads | Symptom relief |

**Note which is which.** 3 and 4 are relief; 1 and 2 remove the cause. Backgrounding the ingest —
which was the next thing about to be built — would have relieved a symptom that was **never
reported**: the upload finishes *before* `.ingest_files` is called, since `input$upload_files`
only exists once the transfer completes. It cannot touch a second of the upload.

#### The gap this exposed in how we work

Every measurement above came from throwaway scripts in a scratch directory. **There is no
repeatable performance suite**, so "is it faster?" has no answer that survives a session, and a
regression would go unnoticed for months.

**Agreed order: B then A, then the rest.**

- **B — `check_perf.R` first.** A performance matrix with declared budgets, generating its own
  fixtures so no test data is committed. Types (CSV, GeoTIFF, multi-band, GPKG, shapefile, LAZ)
  x sizes x phases (open, first draw, one operation). Built first so that A's benefit is
  *demonstrated* rather than asserted — right now a performance "fix" could not be proven either
  way.
- **A — path-based ingest.** The fix for what was actually reported. Needs the native picker
  deleted on 2026-07-27, which is also why the dead Tk pre-warm was removed in v0.11.17: it comes
  back deliberately, next to the code that uses it.
- Then overviews, `fread`, and backgrounding.


---

### 82 step B built v0.11.19 — `check_perf.R`, and what it found immediately

The performance matrix, built first so that the path-based ingest can be **demonstrated** rather
than asserted. It generates its own fixtures (nothing committed), measures each phase separately,
and compares against a declared budget.

**Small fixtures by default (~1 min); `EASYANALYSIS_PERF=large` uses sizes near those actually
complained about.** The large run is slow by design and is not part of the default suite.

**Budgets are deliberately loose — roughly 3-5x the dev-machine time.** A tight budget on a
slower or shared machine fails for reasons nobody will act on, and a check that cries wolf gets
ignored, which is worse than not having one.

First run, small fixtures:

| group | phase | secs | budget |
|---|---|---|---|
| csv | `read.csv` [14 MB] | 2.42 | 12 |
| csv | **`data.table::fread` [candidate]** | **0.04** | - |
| csv | `init_data` | 0.00 | 2 |
| raster | `terra::rast` [61 MB, must stay lazy] | 0.08 | 1 |
| raster | metadata | 0.01 | 0.5 |
| display | aggregate to <=400k cells | 0.21 | 3 |
| display | project to WGS84 (after shrink) | 0.35 | 3 |
| vector | `ea_read_vector` [20k features] | 0.14 | 6 |
| transport | plain disk copy [61 MB] | 0.06 | - |

#### The finding: fread is not symptom relief, it is the fix for CSV

**`read.csv` 2.42 s vs `fread` 0.04 s — 60x**, not the ~10x estimated when it was filed as
"symptom relief" in item 82's table. At that ratio the CSV problem does not need backgrounding at
all: a 92 MB CSV that blocks the UI for 15.5 s would read in roughly a quarter of a second.

**That is exactly why the suite was built first.** The plan had `fread` ranked below backgrounding
the ingest; one measurement reversed it. The ranking was a guess, and the guess was wrong.

#### Assertions worth noting

- **`terra::rast` has a 1-second budget** on a 61 MB file. It is the guard against the day
  somebody makes ingest read values: laziness is the property, not the speed.
- **A CONTROL for the project-first order** runs in `large` mode. The whole display budget rests
  on downsample-before-reproject, and a refactor could silently restore the 50 s version.
- **`fread` is measured but not judged** (budget `NA`), because it is not wired in yet. It is
  there to keep the comparison honest and current rather than a number in a commit message.


---

### 82 step C built v0.11.20 — fread, and the equivalence trap it nearly walked into

Promoted ahead of backgrounding on the suite's own evidence (60x, not the ~10x guessed).
`ea_read_table()` uses `data.table::fread` with `read.csv` as a real fallback -- data.table is an
extra, and a fresh install that skipped it must still open a CSV.

**Through the app's actual code path: 1.48 s -> 0.02 s.** The 92 MB file that froze the UI for
15.5 s now reads in a fraction of a second, which is why **backgrounding the CSV ingest is no
longer worth doing** -- there is not enough time left to move off the main thread.

#### Two things that would have broken quietly

**1. `data.table = FALSE`.** fread returns a data.table by default, and data.table's `[` has
DIFFERENT semantics from a data.frame -- `df[, "col"]` and `df[i, ]` do not mean the same thing.
Around forty modules index these frames as plain data.frames, so returning a data.table would
have changed behaviour app-wide in ways nothing here would have caught.

**2. `check.names = TRUE`, and this one was nearly missed.** fread keeps column names verbatim.
Measured on a deliberately awkward CSV, **six of six columns differed**:

| read.csv | fread, default |
|---|---|
| `my.col` | `my col` |
| `X2nd.col` | `2nd-col` |
| `with.space` | `with space` |
| `TRUE.` | `TRUE` |

Every formula in the app is built by **pasting column names together**, so `y ~ my col` does not
parse and `TRUE` is a reserved word. And `init_data()` does **not** normalise names, so nothing
downstream would have repaired it. The symptom would have been "regression fails on some CSVs",
weeks later, with no obvious link to a performance change.

Types and dimensions matched throughout; it was only ever the names.

**The equivalence is now asserted in `check_perf.R`**, not just fixed: names, types and class are
compared against `read.csv` on that awkward fixture, so removing `check.names` as apparent noise
fails immediately. A performance suite that only measured speed would have shipped this.


---

### 82 step A built v0.11.21 — Add data from disk, the local-first route

**THE DATA RULE applied at the front door.** The app runs on the same machine as the data, so a
file the user already has is now **opened**, not uploaded. No HTTP transfer, no temp copy, and
therefore no size that matters.

- **`ea_pick_files()`** — a native multi-select dialog via `tcltk::tkgetOpenFile`, with filters
  per data type. Returns paths, `character(0)` on cancel, or `NULL` when no OS dialog exists
  (browser build) so the caller can fall back to the uploader. Those three outcomes are
  deliberately distinct: conflating cancel with unavailable would either swallow a cancel or show
  a spurious error.
- **`ea_files_from_paths()`** shapes real paths like Shiny's `fileInput` data.frame, so
  **`.ingest_files()` is reused verbatim**. Every file type, the shapefile grouping and the
  project bookkeeping behave identically; the only difference is that `datapath` is the user's
  own file.
- **Tk is warmed on FIRST USE, not at boot.** The old pre-warm cost a measured 1.61 s on every
  start and was removed in v0.11.17 exactly because the dialogs it warmed had been deleted.
  Restoring it at boot for a dialog most sessions never open would repeat that mistake.
- The local button is **first and primary**; the uploader is relabelled *"Upload instead"*.

**A second problem it fixes, which the uploader could not.** `.keep_source()` records where a
layer came from, and an uploaded file's temp path is gone by the next session. A real path
persists, so a project now reopens against the user's own file.

**Guarded by `check_local_ingest.R`, and the property guarded is NOT speed.** It is that **no
copy happens**: `datapath` must equal the original path. A future "optimisation" that staged
files to a temp directory would look harmless, pass every other check, and silently reinstate the
cost this route exists to remove. The check also asserts the local route appears **before** the
uploader, since the ordering is the rule made visible.

**One harness fault worth recording:** the ordering assertion first searched head **and** body and
failed against correct code — `upload_files` is named in the head JavaScript long before either
control renders. Position in a concatenation of head and body is not layout order.

#### Still open on item 82

- **Overviews for display** (rule 3). `.disp_raster()` aggregates the full grid; reading a pyramid
  level instead would make display cost independent of file size.
- **A real multi-GB file through this route, timed.** The transport is gone by construction, but
  the end-to-end number has not been taken here.
