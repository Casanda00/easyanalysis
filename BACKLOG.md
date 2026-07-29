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

## 1. Project loading shows no progress, and reloads work already done

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

**To check first:** whether the pools are genuinely cleared on every open (`.clear_pools()`
in `open_project`) and whether a re-read is actually necessary, or whether a session-level
cache keyed by path+mtime would be sound. Caching spatial objects has a memory cost — the
LAS OOM history (CLAUDE.md, `.read_las_capped`) is the cautionary tale, so a cache needs a
bound and probably a size check.

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

## 3. Black bar in the 3D view

> "in the 3d view, there is a black color there in the bar. it does not match the theme."

Another hardcoded colour that survives the theme, same class as the R console's old
`#0f1a12`. Find it in the LiDAR 3D UI and move it to tokens. **Bug.**

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

## 8. Linear regression colours, including black

> "the color viz on linear regression isnt good. some hardcoded ones are in there. the
> black too"

Hardcoded colours in `mod_linear_regression.R` that ignore the theme. Related to items 3
and 10 — same root cause, different screens. **Bug.**

## 9. Adjustable sidebar

> "can we make the sidebar adjustable?"

Draggable width for the workspace side panels. The app already has drag-to-resize for the
console dock, the attribute dock and the data-view split, so reuse that pattern.

## 10. Regression output highlighting is unreadable

> "hightliighting the output from the regression cant really be seen due to color problems.
> this should be the same for others, i guess."

Highlighted/selected output has poor contrast. The reporter expects this to affect **other
screens too** — so treat it as a sweep, not a one-screen fix, like the earlier text and
surface passes. **Bug.**

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
