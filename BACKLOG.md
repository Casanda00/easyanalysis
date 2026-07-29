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

## 4. 3D view should be 3D only, and the toggle should be obvious

> "3d view should remove the two pane, map and 3d. 3d is only 3d not map view on 3d. there
> is no way to switch back from 3d to the map view, perhaps, that 3d view should act as a
> toggle. yeah, the button does it but it is not clear."

- Drop the split: the 3D view shows **only** the cloud, no map pane.
- Getting back to the map is unclear. The button *is* a toggle already, but it does not
  read as one. Make the state obvious (label/icon changes to "Back to map", clear active
  styling), rather than relying on the user discovering it.

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

## 9. Adjustable sidebar

> "can we make the sidebar adjustable?"

Draggable width for the workspace side panels. The app already has drag-to-resize for the
console dock, the attribute dock and the data-view split, so reuse that pattern.

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

## 11. Results / Diagnostics / Assumptions tabs that may do nothing

> "why do we have results tab, disgnostics, and assumptions if that regression does not
> do it?"

**Verify before acting.** Either those tabs are genuinely empty/broken (a bug), or they
work and were never reachable because the Response dropdown was empty until v0.8.1 (in
which case re-test now that the screen runs). Do not remove anything until this is
established.

## 12. Stop competing for space — one view with a dropdown

> "maybe we should start competing for view and do the simple thing: use a drop down for
> view. this applies to model summary, performance metrics, LLOCV, ANOVA table, the plots,
> Assumption checks. they are too clutter. one view, a drop down to change."

A layout principle, not a single fix: **one output area, a dropdown to choose what it
shows.** Applies to Model summary, Performance metrics, LOOCV, ANOVA table, plots and
assumption checks. Likely the same treatment for other model screens afterwards.
This subsumes part of item 11 — decide 11 first, since a dropdown over broken panes is
worse than no panes.

## 13. Plot appearance belongs above the plot, and multi-variable handling

> "the plot appearance button should not be in the side bar, it should be on top of the
> plot. i think it only applies to single variables, what if we have multiple variables,
> does it handle it?"

- **Move it.** The `.ea-pop` icon should sit above the plot it affects, not in the tool
  panel. It is one icon, so this is cheap.
- **The multi-variable question — answer, because it is a real limitation.** The colour
  setting is applied only to layers carrying a **fixed** colour or fill. Layers that map
  colour to a *variable* are deliberately left alone, because overriding them would
  destroy the encoding and make the plot lie. So on a multi-series plot the single colour
  does **not** apply, by design. Title and axis labels work regardless.
  **Decide:** whether multi-series plots should get a palette choice (a set of colours)
  rather than one colour. That is the honest fix, and is more work than a colour picker.

---

## Cross-cutting

Items **3, 8, 10** are all the same underlying problem — hardcoded colours that ignore the
active theme — on three different screens. Worth one sweep with a browser check across the
colour sets rather than three separate patches, and note the measurement trap in CLAUDE.md
gotcha 24 when verifying.

Items **11, 12** are entangled: settle what actually works before redesigning around it.

Items **5, 13** both use the existing `.ea-pop` pattern, so they are cheap once its
placement rules are agreed.
