# CHANGELOG.md — internal engineering record

**This file is NOT published.** It is ours: the technical account of each release — root causes,
what changed where, which trap it was, what was verified and what was not. Be as detailed and as
raw as is useful.

Three documents, three jobs:

| File | Audience | Published |
|---|---|---|
| **[RELEASE_NOTES.md](RELEASE_NOTES.md)** | users | **yes** — becomes easyanalysis.dev/release-notes |
| **CHANGELOG.md** (this file) | us | no — the engineering detail behind each version |
| **[BACKLOG.md](BACKLOG.md)** | us | no — reported issues, diagnosis, decisions, direction |

When you ship something a user would notice, write **both**: the plain-language entry in
`RELEASE_NOTES.md` and the technical one here. The build fails if internal vocabulary
(`BACKLOG`, `CLAUDE.md`, gotcha or item numbers, reporter quotes) reaches the published file, so
the split is enforced rather than remembered.

Format: `## vMAJOR.MINOR.PATCH — date`, newest first. Version single-sourced in `global.R`
(`APP_VERSION`).

---

## v0.11.27 — 2026-08-10

### Instrumentation, because I was guessing

Three rounds of synthetic fixtures on a different machine answered "is it slow for me", not "is
it slow for them". `ea_time()` now reports each phase to the console the app already runs in:
raster open, vector read, table read, project bookkeeping, the three display steps, and project
reopen. Only phases above 0.05 s print; `options(ea.timing = FALSE)` silences it.

### Why the UI looked fast while the app froze

`.ingest_files()` wraps its loop in `withProgress`, and for a raster that loop is
`terra::rast(path)` — **lazy**, so it finishes instantly and the bar disappears. The heavy read
happens afterwards, when **the map draws**, which has no progress indicator at all. The terminal
showed the truth because GDAL prints its own progress there.

The bar is not wrong about what it covers; it covers the wrong phase. Fixing that is next, now
that the timing lines will say exactly where the cost is.

## v0.11.26 — 2026-08-10

### A 500 MB file was still slow — the transport had come back, twice

Opening a 505 MB / 132 M-cell raster is **0.14 s**. The wait was two pieces of work the app did
not need to do.

**1. The project was copying the file.** `.keep_source()` → `ea_project_import_file()` →
`file.copy()` into the project folder: **0.88 s for 500 MB**, unbounded for multi-GB. The exact
cost "Add Data" removed, reinstated one layer down — and invisible to any UI test, because
everything still worked. It also contradicted the documented design of storing spatial layers as
**path references**. A user's own file is now referenced; an upload is still copied, since its
temp file vanishes with the session.

**2. The map read every cell to draw a thumbnail.** `terra::aggregate` must read everything to
average it — rule 3 of THE DATA RULE broken where the rule names it explicitly.
`terra::spatSample(method = "regular", as.raster = TRUE)` pushes decimation into GDAL:
**1.39 s → 0.11 s (13x)**, and the gap widens with file size, because aggregate scales with the
file and spatSample with the screen. `aggregate` remains a fallback.

**Why the perf suite missed it:** it measured `aggregate` and called that the display path, which
it was. A budget answers *"is this slower than it was"*, not *"is this the right amount of work"*
— and rule 3 exists to ask the second. Both paths are now measured side by side.

## v0.11.25 — 2026-08-10

### Add Data > From file was dead — my regression

`mod_workspace.R` did `getElementById('upload_files').click()`. Fine while the rail rendered a
file input; v0.11.24 made it a **button**, so the element vanished, `.click()` threw on `null`,
and the menu item did nothing. It still worked on Projects because that rail keeps the file input.

Both surfaces now fire one app-level action into one handler, so they cannot drift. Where no
native dialog exists the handler asks the page to open the file input. CONTROL asserts the
`getElementById(...).click()` shape is gone — the shape, not the symptom.

### See script is on the pages, not in Help

A menu nobody opens is the same as not shipping it. The button now sits at `mi$tools(mi$id)` in
`mod_workspace.R` — the one place **every** module's panel renders — so it reaches all screens at
once instead of the handful someone edits. The check asserts placement *at that seam*, since
"exists on some screens" is the failure being prevented.

Rendered unconditionally: the workspace cannot see `module_ctx`, and the handler already
distinguishes "run the analysis first" from "this screen does not expose a model", which beats a
button that disappears without saying why.

## v0.11.24 — 2026-08-10

### One way to add data

Two routes was complexity with no upside — it asked the user to know which was faster. There is
now **one "Add Data"**, with the disk route underneath. `add_from_disk`, "Upload instead" and the
size hint are gone. The control renders server-side: a button where a native dialog exists, a file
input **with the same label** where it does not.

### See script reaches hand-written screens

The registry-only boundary was honest and still wrong in practice: **Linear regression is
hand-written and is the most-used screen**, so skipping it read as broken.

`ea_script_from_fit()` derives the script from the **call the model object carries** — verified
for `lm`, `glm`, `MASS::rlm`, `nnet::multinom`, `randomForest`, `nlme::lme`, `aov`
(`prcomp`/`kmeans` carry none). The module contract gains an optional `fit = function()`, so a
screen opts in with **one line**, and **Help > See script for this analysis** is the shared
surface.

The call is rewritten to `data = df`; unqualified calls still get the right `library()` line. The
limitation is stated **in the script**: a call does not show data preparation done first. An
object with no call returns `NULL` rather than a guess — asserted as a CONTROL.

Remaining: the same one-line `fit` on the other hand-written screens.

## v0.11.23 — 2026-08-10

### Item 84 — the upload feedback was dead code

v0.11.16's selection notice never ran. The script is inside `tags$head`, so it executes **before
the body is parsed**: `getElementById('upload_files')` returned `null`, the `if (fi)` guard
skipped, and no listener was ever attached. A 4 GB upload therefore produced no message at all,
exactly as reported.

**And `check_upload.R` let it through** by asserting the string `upload_selected` appeared in the
HTML — which it did, inside code that never executed. **Presence is not function.** Now delegated
on `document` (immune to head/body order), with the check asserting delegation and a CONTROL that
the `getElementById` form is gone.

This explains "no error message" completely; it does not explain "no file". The cap is `Inf` and
was verified against Shiny's own expressions, so nothing rejected the transfer — a 4 GB browser
upload likely stalled in httpuv's chunked write, which cannot be reproduced without a browser.
**For files that size the answer is not to upload at all:** `Add data from disk` opens in place,
lazily, in ~0.09 s regardless of size.

### Item 85 — colour dots before layer names removed

The row already names the layer type, so the dot repeated it. Scoped to the layer and basemap
rows; `ea-wsx-sw` is also used for placeholder and header dots, which stay. The first attempt
asserted a bare count of the class, matched all six uses, and failed against a correct edit — the
same over-broad-control mistake as v0.11.5's.

## v0.11.22 — 2026-08-10

### Item 83 — creator credited; How to cite is in the app

**The app had no citation at all** — APA and BibTeX existed only on the landing page, which is the
one place someone finishing an analysis is not looking. And that copy's version was **frozen at
0.10.16 while the app had moved eleven releases**; citation text is where being quietly stale does
real harm, since it ends up in a paper.

- `ea_citation()` is the single source and reads `APP_VERSION` **at call time**, so it cannot
  drift. `EA_CITE_YEAR` is a constant, not `Sys.Date()` — a citation names the publication year,
  and the clock would rewrite it every January.
- **Help > How to cite…**, built on `ea_settings_modal()` so it matches Packages and Plugins.
- In-app documentation gained **section 10, How to cite**, with a sidebar entry. That was the gap
  against the landing page.
- **Acknowledgements credits Tim Casanda Gibson** as creator and lead developer, above the
  existing UEF credit; the docs footer names the creator too.
- Landing page version corrected.

`check_citation.R` — load-bearing assertion is that the version is genuinely a *parameter*
(`ea_citation("9.9.9")` must yield 9.9.9), since a hardcoded string would pass everything else and
be wrong the moment `APP_VERSION` moved. It also asserts app and landing page agree.

## v0.11.21 — 2026-08-10

### Item 82 step A — Add data from disk

THE DATA RULE at the front door: a file the user already has is **opened**, not uploaded. No HTTP
transfer, no temp copy, no size that matters.

- `ea_pick_files()` — native `tkgetOpenFile` with per-type filters. Returns paths,
  `character(0)` on cancel, `NULL` when no OS dialog exists. Three distinct outcomes on purpose:
  conflating cancel with unavailable would swallow a cancel or show a spurious error.
- `ea_files_from_paths()` shapes paths like `fileInput`'s data.frame, so **`.ingest_files()` is
  reused verbatim** — every type, the shapefile grouping and project bookkeeping unchanged.
- **Tk warms on first use, not at boot.** The old pre-warm cost 1.61 s per start and was removed
  in v0.11.17; restoring it at boot would repeat that mistake.
- Local button is primary; the uploader is now *"Upload instead"*.

**Also fixes what the uploader could not:** `.keep_source()` stores a real path, so a project
reopens against the user's own file instead of a temp path that is gone next session.

`check_local_ingest.R` guards **no copy**, not speed: `datapath` must equal the original path. A
staging "optimisation" would pass every other check and silently restore the cost. Ordering
(local before upload) is asserted too — the rule made visible.

Harness fault recorded: the ordering assertion first searched head+body and failed against
correct code, because `upload_files` appears in head JavaScript long before either control
renders.

## v0.11.20 — 2026-08-10

### CSV reading is ~60x faster (item 82, step C)

`ea_read_table()` uses `data.table::fread` with `read.csv` as a genuine fallback. Through the
app's own path: **1.48 s -> 0.02 s**. The 92 MB CSV that froze the UI for 15.5 s now reads in a
fraction of a second — which retires the plan to background it, since there is no longer enough
time left to be worth moving off the main thread.

**Two silent breakages avoided:**

- `data.table = FALSE` — fread otherwise returns a data.table, whose `[` has different semantics
  from a data.frame. ~40 modules index these frames as plain data.frames.
- `check.names = TRUE` — **nearly missed.** fread keeps names verbatim: `my col`, `2nd-col`,
  `TRUE`, where read.csv gives `my.col`, `X2nd.col`, `TRUE.`. Six of six awkward columns differed.
  Every formula is built by pasting column names, so `y ~ my col` does not parse and `TRUE` is
  reserved — and `init_data()` does not normalise names, so nothing downstream would have caught
  it. The symptom would have been "regression fails on some CSVs" weeks later.

Equivalence (names, types, class vs `read.csv`) is now **asserted** in `check_perf.R`. A suite
that only measured speed would have shipped the name bug.

## v0.11.19 — 2026-08-10

### THE DATA RULE, and `check_perf.R` (item 82, step B)

**Promoted to a non-negotiable rule in CLAUDE.md: this is a local-first app, not a web app.** The
data is already on the same machine as R, so never move bytes you do not have to. The app was
copying a file already on disk through an HTTP multipart upload into a temp file, to reach a path
it could have opened directly — rule 1 broken at the front door, and the entire reason large files
feel slow.

Five rules, taken from how desktop GIS, web GIS and analysis platforms actually work: reference
in place; read only what is needed; read at the resolution the **screen** needs, not the file's;
stream rather than materialise; do the work where the data is.

**`check_perf.R`** — a repeatable matrix with declared budgets, generating its own fixtures.
Built *before* the path-based ingest so that fix can be demonstrated rather than asserted; until
now every performance number came from a throwaway script and no claim survived the session.

**It immediately reversed a plan.** `read.csv` 2.42 s vs `data.table::fread` **0.04 s — 60x**,
not the ~10x assumed when `fread` was filed below backgrounding as "symptom relief". At that
ratio the 92 MB CSV that freezes the UI for 15.5 s would read in about a quarter of a second, and
backgrounding it becomes unnecessary. The ranking was a guess; one measurement corrected it.

Notable assertions: `terra::rast` carries a **1-second budget** on a 61 MB file — the guard is
laziness, not speed — and `large` mode keeps a CONTROL for the project-first order, since the
whole display budget rests on downsample-before-reproject not coming back.

## v0.11.18 — 2026-08-10

### Item 81 — a multi-layer GeoPackage lost every layer but the first

Noticed as a console warning while testing: *"automatically selected the first layer in a data
source containing more than one"*. Every call site passed `quiet = TRUE`, so it never reached the
app. **Reproduced: a 2-layer GeoPackage loaded 3 of 5 features and reported success.**

Third instance of this project's worst failure shape — missing data that looks complete. The
others: self-deleting error messages (v0.11.3) and the silent upload rejection (v0.11.16).

`ea_read_vector()` (helpers.R) returns a **named list of every layer**, so a caller cannot keep
just one. Named `<file>:<layer>`; single-layer files return one entry named after the file, so
call sites need no special case.

**Project restore was the subtler half:** each layer is its own pool entry, so `.spatial_get()`
now takes the entry name and reads the layer after the `:`. The read cache is keyed per layer too
— otherwise every layer of one file returns whichever was cached first, the same bug hiding
somewhere the names still look right.

`check_vector_layers.R` — the load-bearing assertion is the CONTROL that plain `st_read()` really
returns 3 of 5. Without it the fix would pass against a single-layer fixture and prove nothing.

## v0.11.18 — 2026-08-10

### Item 81 — a multi-layer GeoPackage lost every layer but the first

Console warning spotted while testing: *"automatically selected the first layer in a data source
containing more than one"*. Every call site passed `quiet = TRUE`, so it never reached the app.
**Reproduced: a 2-layer GeoPackage loaded 3 of 5 features and reported success.** Third instance
of this project's worst failure shape — missing data that looks complete.

`ea_read_vector()` returns a **named list of every layer** (`<file>:<layer>`); single-layer files
return one entry named after the file, so call sites need no special case. **Project restore was
the subtler half**: each layer is its own pool entry, so `.spatial_get()` now takes the entry name
and reads the layer after the `:`, with the read cache keyed per layer — otherwise every layer of
one file returns whichever was cached first.

`check_vector_layers.R` — load-bearing assertion is the CONTROL that plain `st_read()` really
returns 3 of 5. Without it the fix would pass against a single-layer fixture and prove nothing.

### Item 57 — See script, for the 65 registry tools

All 14 `fit()` and 51 `run()` bodies deparse. The script is the spec's **own body, verbatim**,
with the user's roles and parameters bound above it plus the internal helpers, so it runs in plain
R. Not a reconstruction: a second rendering can drift, and a script that disagrees with what ran
is worse than none. `library()` lines are scanned from the body, so they cannot go stale.

`check_script.R` **executes** the generated script and compares coefficients with the app's —
**max difference 0.00e+00** — plus reachability and a CONTROL that the body is verbatim.

**The honest boundary:** the ~23 hand-written screens have no spec and need per-module emitters.
The tools that are *data* got this for free; the ones that are *code* did not.

## v0.11.17 — 2026-08-10

### Item 80 — measured: the app is not what is slow

Test raster 10,000 x 10,000 (100 M cells, 0.37 GB):

- `terra::rast(path)` — the ingest path's only raster call — **0.06 s** (lazy, reads no values)
- metadata, `minmax`, `setMinMax` — 0.00 s
- display prep: aggregate 0.65 s + project 0.26 s
- **total app-side work under 1 second**
- projecting at full resolution first, the order fixed earlier: **50.00 s** (the 55x win, confirmed)

Disk is not it either — a plain copy ran at **1,277 MB/s**, so a 4 GB temp write is ~3 s. **By
elimination the cost is the browser upload transport** (HTTP multipart + chunked writes), which
restates item 79's argument with numbers: pointing at a path beats copying the bytes.

### Removed a dead 1.61 s from every boot

`global.R` pre-warmed Tcl/Tk for native file dialogs that were **deleted on 2026-07-27**. The
pre-warm was by then the only reference to tcltk left in the live codebase — warming a feature
that no longer exists, at a measured **1.61 s per boot**, while startup was being reported as
slow. If a native picker returns, pre-warm it next to the code that uses it.

## v0.11.16 — 2026-08-10

### Item 79 — the upload cap is gone, and the silence is explained

`shiny.maxRequestSize = Inf`. Not a larger number: any finite value is a cliff somebody
eventually walks off, and this report is what that looks like.

Verified Shiny tolerates `Inf` rather than assuming it. `ShinySession$@uploadInit` does
`if (maxSize > 0 && any(sizes > maxSize)) stop(...)` — `Inf > 0` keeps uploads enabled (**0 would
disable them**) and `any(sizes > Inf)` is FALSE. `HandlerManager$createHttpuvApp`'s
`if (maxSize <= 0) return(NULL)` does not trigger.

**Why it was silent, now known precisely:** Shiny rejects with `stop("Maximum upload size
exceeded")` **inside an RPC handler**, so the error surfaces in the browser console rather than
the app — and the app's own handler never ran, because `req(input$upload_files)` halts on an
input that never populated. Two layers of silence stacked; neither could have produced a message.

**Feedback, the other half:** removing the cap fixes rejection, not the minutes-long wait. The
file input now reports its selection on the browser `change` event, before any bytes move, and
the server answers *"Reading 1 file (3.7 GB)… large files can take a while."*

`check_upload.R` asserts against Shiny's real expressions, with the reported 4 GB file and a
10 TB file as controls.

**Not verified here:** an actual multi-GB browser upload end to end — there is no browser in this
environment. Plumbing proven; the round trip needs a real file.

## v0.11.15 — 2026-08-09

### Item 77 complete — and the "open gap" was my misreading

Clarified: the sidebar shows a tool's options once **selected**; the **search popup** is where
activation happens and where the source is disclosed. That is what was built, so there was no
gap. I had inferred a sidebar-preview requirement from "opens in the sidebar", when that clause
was describing existing behaviour rather than asking for anything.

One change from the clarification: the popup heading now reads **"WhiteboxTools - not enabled
yet"** instead of "Not enabled yet". The popup is where the decision to enable someone else's
engine is taken, so whose engine it is should be unmistakable there, not only in each row label.

## v0.11.14 — 2026-08-09

### Item 78 — one R Console, and the "More" group deleted

**R Console was in two menus with two different behaviours**: Analysis → R Console called
`eaConsole(..., 'dock')`, View → R Console toggled a CSS class. Which one you found decided what
it did. Now a single top-level menu.

**"More" removed from the menubar.** Verified first that Documentation and References are already
in Help (`:709-710`). They could not be deleted — Help opens them *by tool key* — so they are
marked `hidden = TRUE`: still real and openable, contributing no menu entry. The group builder
skips hidden tools and drops a group left empty, so `More` vanishes rather than becoming an empty
fly-out.

Guarded on the **rendered menubar**: `More` absent, `Data` present as a control, Documentation
still reachable, `R Console` appearing exactly once.

### Item 77 gap closed — provenance on the result

The v0.11.13 badge says what is *about* to run; three layers later nothing said which engine made
which. Output objects now carry `attr(res, "ea_provider")` and the completion message names the
engine.

**Still open, and a deliberate design difference:** the request was for the tool to open in the
sidebar with Activate *there*; what was built is Activate in the search dropdown (enable + open in
one click). Both reach the same state; the difference is whether you can inspect a tool before
enabling someone else's engine. Recorded for a decision rather than silently substituted again.

## v0.11.13 — 2026-08-09

### Item 77 — search reaches unenabled tools; provenance is visible

**Root cause:** `eaToolSearch` is a client-side index of the **rendered menu DOM**. An unenabled
provider tool is not in the menu, so it was structurally invisible — no amount of typing would
have found `LasToShapefile`.

- Menu index unchanged; the server now also answers from `ea_wbt_catalogue()` (all 484). Extra
  hits render under a "Not enabled yet" heading with **Activate**.
- Non-provider tools never reach that path, so never show an activation control.
- Activating **enables and opens** — enabling alone leaves the user where they started.
- An un-indexed catalogue **says so and offers to index** rather than returning "No tools match".
  Empty results and an empty catalogue are indistinguishable to a user.

**Finding — not every tool is expressible.** `LasToShapefile` declares **no output parameter**;
WhiteboxTools writes the `.shp` beside its input. The mapper already refused it, but search would
have offered a dead Activate. So the catalogue gained `usable`: unusable tools are still shown
(marked "Not supported", with the reason) and `ea_tool_set()` **refuses** to enable one — hiding
the button is not enough, since any other path would store an activation that silently produces
nothing. This is a class, not one tool; supporting implicit outputs is recorded, not half-done.

**Provenance:** `algoToolsUI()` renders a WhiteboxTools badge with the underlying tool name
whenever `spec$provider` is set. Built-in tools show none — asserted as a CONTROL.

## v0.11.12 — 2026-08-09

### Item 76b — Plugins is a dialog, not a screen

Managing plugins is a settings action, so it should not take the canvas or displace the tool
panel. Rebuilt on the Packages pattern rather than beside it.

- **`ea_settings_modal()` (helpers.R)** — the general settings-dialog shape, extracted from the
  Packages modals so Packages / Plugins / Preferences share one implementation.
- `pluginsCanvasUI` / `pluginsToolsUI` deleted; the module is no longer in `MODUI`. The menu
  fires an app-level `plugins_open`, the same way the Packages items fire `pkg_*_ui`.
- Provider enable/disable and both Index buttons moved into the provider card, since a dialog has
  no tools panel.

**Structural detail worth keeping:** the search box is a real `textInput` in the dialog shell,
not inside the reactive body — only the card and results are `uiOutput()`s. Rebuilding a text
field on each keystroke wipes it mid-edit (gotcha 21). `ea_settings_modal()` documents that in
its own comment.

`check_plugins.R` gained *shape* controls: the canvas and tools UI must be absent, the dialog
must use `ea_settings_modal`, and the module must not appear in `MODUI`. The reachability
assertion was retargeted from "registered and bound" to "has a top-level menu" — the old one
passed while Plugins was unreachable.

## v0.11.11 — 2026-08-09

### Plugins is now a top-level menu, beside Packages

It was registered as a workspace tool under group `More`, so the only route to it was
**Analysis → More → Plugins** — a nested fly-out. Built, tested, and effectively unreachable:
**item 67 repeating in a new place.** My own check made it worse by asserting the tool was
*registered* and its server *bound*, but never that anyone could find it. Registration is not
reachability.

Also removed the dead **Packages → Optional engines → "Whitebox tools" (disabled)** placeholder.
A greyed-out entry beside a working one is how a user concludes the feature does not exist.

**Still open (item 76b):** Plugins should be a *dialog* like Packages, not a full canvas screen
occupying the tool sidebar — managing plugins is a settings action, not an analysis. Plus a
reusable settings-dialog pattern so Packages / Plugins / Preferences are one implementation.

### Round 8 documented (items 76–80)

Recorded from testing, not built: Plugins-as-dialog; search reaching unactivated provider tools
with inline Activate and visible provenance; R Console as its own menu and the `More` group
deleted; the upload cap; and slow large-file loading.

**Verified while documenting, not assumed:** `global.R:46` sets
`shiny.maxRequestSize = 3 * 1024^3` — **3 GiB** — so a 4 GB file (3.73 GiB) is rejected, and the
handler is `observeEvent(…, { req(input$upload_files); … })`, which halts **silently** when the
input never populates. The file vanishes with no error. Same family as the self-deleting error
messages, and worse: there is not even a message to miss.

## v0.11.10 — 2026-08-09

### Item 74 phase 2b — enabling a tool no longer needs a page reload

The reload was rejected, correctly, and the underlying question was whether the plugin
foundation is sound. It is — **at one joint it was not**: `MODUI` was built once at workspace
construction and `server.R` bound algorithm modules in a one-shot `lapply`. Both assumed a static
registry. Neither is a flaw in the provider design; both were assumptions from when the registry
could only change between sessions.

- `MODUI` construction became `.build_modui()` behind
  `MODUI_R <- reactive({ plugin_epoch(); .build_modui() })`; the ten consumer references now read
  the reactive, so menus, tool picker and search rebuild on activation. List construction only —
  nothing like the 33 ms-per-tool cost of binding.
- `.bind_algos()` binds only ids absent from `.algo_bound`. **Idempotence is the point:**
  re-binding an id would create a second set of observers on one namespace, which surfaces as a
  Run button firing an operation twice.
- `plugin_epoch` joins them; `pluginsServer(on_change =)` bumps it. All "reload the page" wording
  removed, because it is no longer true.

`check_plugins.R` is now 40 assertions. The control that matters: the tool is absent from the
workspace catalogue before enabling and present **in the same session** after, with its
provenance label. A first bind pass takes 52 entries, a second takes **zero**, and enabling one
more binds exactly one.

**Left dynamic-but-not-yet:** `module_ctx` is a plain list assembled once, so a tool enabled
mid-session is usable but does not report to the Co-Analyst until the next session. Recorded, not
hidden.

### Item 75 — provider roadmap, and the line between a provider and a feature

Documented. The useful part is the distinction: **WhiteboxTools** is a tool library (a provider),
**GeoAI** is a provider with a Python backend and probably a *declared* rather than generated
spec list, **GeoLibre** is a source of feature ideas, and **swipe is a map feature that is not a
plugin at all** — no pool inputs, no output layer, nothing to run. Forcing it through the
provider interface would mean inventing a spec kind for "a UI gesture". Same reasoning that kept
the draw-based crop/clip operations in `mod_raster.R`.

## v0.11.9 — 2026-08-09

### Item 74 phase 2 — the Plugin menu (`mod_plugins.R`)

A screen under **More → Plugins**. Provider card names WhiteboxTools' authors (Prof. John
Lindsay; R package by Qiusheng Wu and Andrew Brown, MIT) and links out — enabling somebody
else's work should be a visible decision, not a feature that silently appeared.

- **Enable / disable the provider**; disabling hides its tools but remembers the per-tool picks.
- **Per-tool switches**, same switch idiom as layer visibility so it reads as the same control.
- **Search covers the whole catalogue**, activated or not, so a tool is findable before it is
  enabled and can be turned on from the result. Filters: common / enabled / everything.
- **Indexing runs in the BACKGROUND** via `ea_wbt_build_async()` (`callr::r_bg`). Shiny is
  single-threaded, so an in-process build would freeze the app for the whole ~8 minutes
  (gotcha 29) — even the 31 featured tools would block for ~30 s. The background process prints
  one line per tool and the module polls its stdout, so progress needs no shared state.
  Deliberately not `compute_worker.R`: that session is shaped around running one algorithm spec
  and preloads a package set this does not need.
- All colours are tokens with translucent `color-mix()` tints (gotcha 31).

**Known limitation, stated in the UI:** a newly enabled tool needs a page reload. `MODUI` is
built once at workspace construction and `server.R` binds at session start, so making activation
take effect immediately means making the tool catalogue reactive and binding modules mid-session.
Tools enabled in a *previous* session are present at boot, so this only affects the session in
which you enable something. Binding on activation was rejected — 33 ms each means enabling 50
tools costs 1.7 s and reintroduces exactly the cost this design exists to avoid; the correct fix
is binding on **first open**.

`check_plugins.R` now 34 assertions, covering the screen's behaviour (renders, provider toggle,
per-tool switch writes through, bulk enable/disable) and that the tool is registered and bound —
a screen nobody can open is the item-67 failure in a new place.

## v0.11.8 — 2026-08-09

### Item 74 — `plugins.R`: WhiteboxTools as an opt-in provider

Generates registry specs from WhiteboxTools' own self-description instead of hand-wrapping 484
tools, and makes every external tool opt-in so nothing is registered or bound until a user asks.

Both costs measured, not assumed: metadata **0.55 s/tool** (266 s for all 484) and module binding
**33 ms/tool** (~16 s added to every session start). Activation therefore gates *binding*.

- State at `<home>/plugins/state.json` — a preference about the installation, not project data.
  Provider and per-tool switches; turning the provider off keeps the per-tool picks.
- Manifest cached and keyed by `wbt_version()`. Captures parameters **and** the authoritative
  `wbt_toolbox(tool)` category — note `wbt_toolbox()` with no argument is broken in the R package
  (panics with *"Unrecognized tool name …whitebox_tools.exe"*), per-tool works.
- Eight-case type mapper; `ea_bool()` added for the one type nothing hand-written needed.
- **One `run()` closure for all 484** — WhiteboxTools is uniformly file-based, so there is no
  per-tool code.
- `ea_wbt_catalogue(query)` searches the manifest, so a never-activated tool is still findable and
  each result reports `active`/`featured`. Fast *without* hiding capability.
- `ea_algorithms()` concatenates providers; everything downstream was already generic.

31 featured tools, verified against `wbt_list_tools()` on the installed version — and re-verified
by the check on every run.

**`check_plugins.R`** — 26 assertions. The load-bearing one: a **generated** spec runs end to end
(`Slope` mapped from JSON, executed on a synthetic DEM, real raster back). Plus the speed control:
provider ON with no tools activated contributes nothing.

**Phase 2 not built:** the Plugin menu UI, lazy binding on first open (activation currently needs
a reload), and flagging a project that used a now-inactive tool.

## v0.11.7 — 2026-08-09

### Item 13 step 1 — WhiteboxTools was guarded on the wrong thing

WhiteboxTools is two installs: the `whitebox` R wrapper, and the ~90 MB executable that
`whitebox::install_whitebox()` fetches. `deps.R` listed `whitebox` in `extras`, so the wrapper
installed and `requireNamespace("whitebox")` returned TRUE — **the guard passed on every machine
that had run the installer** — while nothing anywhere called `install_whitebox()`. The run then
died inside WhiteboxTools with a missing-file error.

Gotcha 32's shape: verifying a proxy for the dependency is not verifying the dependency.

- `.ea_require_whitebox()` (helpers.R) checks `whitebox::check_whitebox_binary()`, wrapped in
  `tryCatch` because older package versions throw rather than return FALSE when the binary is
  absent — exactly the case being guarded. Used at all three sites (`algorithms.R` ×2,
  `mod_hydro.R`).
- `deps.R` fetches the program once, at install time where consent already exists, rather than
  mid-analysis. Non-fatal by design.

**Control-tested:** passes with the binary present; blocks with `check_whitebox_binary()` forced
to FALSE and separately forced to throw. The old guard passed in all three.

**Steps 2–3 remain open: we expose 2 of 700+ WhiteboxTools algorithms.**

## v0.11.6 — 2026-08-09

### Item 65 — draggable layer reordering

**The panel was upside down relative to the map, and that had to be fixed first.** It listed pool
order (tables, rasters, lidar, vectors) and `.draw_layers()` added them in that same order —
leaflet stacks the LAST overlay on top, so vectors sat at the BOTTOM of the panel and on TOP of
the map. Verified there are no panes or `zIndex` on the overlays; only the basemap gets
`zIndex = 0`, so insertion order alone governs. Nothing exposed the inversion while the order was
fixed, but shipping a drag handle over it would have made "up" mean "down".

`layers()` is now top-first (GIS convention) and `.draw_layers()` walks `rev(layers())`. **The
default order is the pool order reversed, so every existing project's map is pixel-identical** —
only the panel's reading order changes.

- `layers_pool()` keeps the raw pool order. The automatic first-layer choice deliberately uses
  it, so correcting the panel does not change which layer opens active.
- Unlisted layers are prepended (new layers arrive on top, as every GIS does); names in the order
  with no live layer are dropped, so a deleted layer cannot be resurrected.
- `layer_order` is a `reactiveVal` persisted beside `layer_style` through
  `ea_project_save_data()`. The rename observer rewrites it too — it stores names, so a rename
  that skipped it would drop the layer out of its own order.
- Only the grip is `draggable`. The row already carries a visibility toggle, a name, a delete
  button and a context menu; a whole-row drag makes all of them feel sticky.
- The drop handler sends the **complete new order**, not a move instruction, so the server never
  reconstructs the gesture and the DOM is never the source of truth. A drop that fails to save
  snaps back.
- The basemap row has no `data-lyr`, so it is neither draggable nor a drop target.
- Move to top / bottom added to the layer context menu — nearly free once order is explicit, and
  better than dragging in a list that scrolls while you drag.

### `check_layer_order.R` — new guard

The load-bearing assertion is **not** the new feature: it is the CONTROL that
`rev(layers())` still equals the historical pool order, which is the only thing standing between
a future refactor and every map silently restacking.

**Two harness faults on the way, both mine:**

1. A helper passed `environment()` out of the `testServer` body so cases could share setup. The
   module's internals live in the **parent** of that environment, so `e$layers` was `NULL` and
   the failure read as a defect in `layers()`. Rewritten inline — duller and cannot lie.
2. The pools were fixtured as `reactiveValues(Ras1 = NULL, ...)`. `.names()` filters NULL-valued
   keys because a `reactiveValues` key assigned `NULL` keeps its name (gotcha 14), so every pool
   was **empty** and all 17 assertions collapsed to the single table. Non-NULL placeholders fixed
   it.

Persistence round-trip verified separately: `layer_order` saves as a character vector, reloads
identically, and an omitted argument preserves the stored value rather than clearing it.

## v0.11.5 — 2026-08-09

### Item 52 — attribute table window controls

Minimise / maximise / close, plus drag-to-resize. Maximise was built first on the backlog's own
reasoning: it solves the cramped-strip complaint outright and costs least.

**The state lives on `<html>`, not on the dock, and that is the whole fix.** The dock is built
inside `.map_ui()`, so it is destroyed and rebuilt on every map re-render — layer choice,
visibility toggle, basemap change. The old button toggled `.collapsed` **on the dock** and
rewrote its own `textContent`, so both were discarded at the first interaction and the panel
sprang back open by itself. The root element survives all of it; the height is a custom property
there for the same reason.

`.ea-wsx-attrhead` has carried `cursor: ns-resize` since it was written with nothing behind it.
Drag-to-resize now honours it — an affordance that promises and does not deliver is worse than
none.

Client-side by necessity, not preference: a server round-trip would queue behind any running fit
(gotcha 29).

Both menu entries that toggled `.collapsed` now go through `eaAttrSet`, so *Attribute table* can
reopen a **closed** dock rather than only un-collapsing a visible one.

### `check_attrdock.R` — new guard

Asserts the invariant that is invisible in a screenshot: every state selector is rooted at
`html.ea-attr-*`, and the buttons carry no state. It lifts `eaAttrSet` **out of the rendered
page** and runs it in node against a stub implementing `classList` and the attribute pair, so it
exercises what ships rather than a copy — proving the states replace rather than stack.

**One control was over-broad on first run** and failed against working code: a bare search for
`classList.toggle('collapsed')` also matched the split panes (`.ea-wsx-sp`), which legitimately
keep their own collapse and are not rebuilt the same way. Scoped to the dock. The check was
wrong, not the code — again.

### Item 54 status

"Zoom to selected" shipped in v0.10.18. The remaining two actions (edit attribute, add
attribute) were held pending a write/undo model — **which now exists**, via edit mode's delete
with bounded undo. They are unblocked; not built here.

## v0.11.4 — 2026-08-09

### Item 68a — the CV caveat was styled as a footnote

`.prf_dt()` wraps the note in `<span class="ea-cv-note">`; `ui.R` styles it as a bordered chip
via `color-mix(in srgb, var(--warn) 18%, transparent)` — translucent so it takes its lightness
from the background in every palette (gotcha 31). Position deliberately unchanged: a caveat
moved away from the number is a caveat nobody reads.

**Three faults in the fix, all caught by the guard — see BACKLOG item 71:**

1. A literal `"` inside a CSS comment in `tags$style(HTML("..."))` broke the R parse. Gotcha 1,
   in the file that documents gotcha 1.
2. **DT escapes a character caption wholesale**, so the first version rendered
   `&lt;span class='ea-cv-note'&gt;` — visible angle brackets, worse than the understyling it
   replaced. Must be `htmltools::tags$caption(cap, tags$span(...))`. CONTROL assertion added
   (`!grepl("&lt;span", cap)`) because the class-presence check passed while the page was
   broken.
3. **`as.character()` on a bslib page does not walk the whole tree** — the style-rule assertion
   failed against a correct UI. `htmltools::renderTags()` is the idiom, as `check_ui_js.R`
   already used. A CONTROL now confirms the stylesheet is present before asserting the rule.

**Appearance still unverified** — the guard proves markup, escaping and presence of the rule,
not contrast across the five palettes or wrapping in a narrow panel. Item 68 remains open,
narrowed to that.

## v0.11.3 — 2026-08-09

### Error notifications are persistent — one wrapper, not 110 edits

**Measured before touching anything: 110 error-type notifications in the app, 2 of them
persistent.** The other 108 expired after 5–8 seconds.

The messages themselves are good — most name the cause *and* the remedy — so what expired was
exactly the useful part. It is also a hidden tax on the external testing about to start: **a
tester cannot report a message they never finished reading**, so the report arrives as "it
didn't work" with the diagnosis already deleted. Fixed now rather than after, because the
whole point of the test round is the diagnostics.

Implemented as a single `showNotification()` wrapper in `helpers.R` shadowing shiny's. Viable
because **no call site writes `shiny::showNotification`** (checked — a qualified call bypasses
a shadow, gotcha 27), and helpers.R is sourced into the global env, so an unqualified call in
any module resolves to ours. The signature mirrors shiny's exactly so positional calls still
map correctly.

- `type = "error"` → `duration = NULL`, `closeButton = TRUE`.
- Errors get a **content-derived id** (`xxhash64` of the message), so a reactive that fails on
  every flush replaces its own notification instead of stacking hundreds.
- Warnings and messages are untouched — transient by intent.

### Data Quality pop-ups removed

Reporter: useful the first time, noise afterwards. **The reason it wore out is the part worth
keeping:** the observer fired on `active_ds()`, i.e. on dataset **activation**, not on load —
so clicking between datasets in the left rail replayed the entire stack, one notification per
issue, every time.

`.quality_check()` in `helpers.R` is **kept and deliberately unwired**, with a comment at the
old call site saying so, so it is not mistaken for dead code. The analysis was right; the
delivery was wrong. Its intended home is a panel the user opens.

### `check_notifications.R` — new guard

Control-tested: asserts an error passed `duration = 8` arrives at shiny with `duration = NULL`,
while a message passed `duration = 3` still arrives as 3. Records what actually reaches shiny
via `assignInNamespace`.

**Two harness faults caught during the writing, both the familiar kind:**

1. The module-level section was appended **after the script's `quit()`**, so it never ran — and
   the run still printed PASS, from the earlier ending. A guard that cannot execute reports
   success.
2. The role inputs were set as `role_y`/`role_x`; `mod_stat.R` uses **`r_<key>`**. With the
   wrong names nothing fitted, no action fired, and the check proved nothing while looking
   green.

Now proves the real path: fitting `robust` on a dataset with no layer link, pressing
*Predictions to map layer*, and confirming the refusal arrives **from inside a module frame**,
persistent, with the remedy text intact — the exact message the reporter could not read.

Verified: all four guards pass; build OK; app serves HTTP 200 (a shadowed shiny function is a
runtime risk, not a build-time one, so serving was checked rather than assumed).

## v0.11.2 — 2026-08-08

### Item 36 — the cross-validation fold loops (priorities 2 and 4)

Filed as one shape ("same fold-skip"). It was **two**, and only one of them merely omits data.

**`mod_logistic.R` — omission.** A failed fold was `next`-ed, so its rows left the pooled
prediction. Accuracy was computed over a subset while the caption still said *"5-fold CV"*.
Now counts `bad_folds` / `bad_rows` and reports them.

**`mod_classification.R` — fabrication.** A one-vs-all sub-model that failed returned
`rep(0.5, nrow(te))`, and that constant **still entered `which.max`**. On any row where every
fitted class scored below 0.5, the class with *no model at all* won the vote, and the invented
label counted toward the reported accuracy. Failed classes now yield `NA` and are withdrawn
from the vote; a row where all classes failed is `NA` and is **not scored** (excluded from
accuracy, not counted as an error). Also fixed a latent crash: `vapply` collapses to a
dimensionless vector when a fold holds a single row, which `apply()` cannot take.

**Why these outrank the rest of the sweep despite being fewer sites:** folds fail
non-randomly — a fold fails when its training split is degenerate, which is the hard case — so
dropping it **biases the metric upward**. Wrong numbers, presented with full confidence, not
missing ones. See gotcha 35.

`mod_lme.R` was **already correct** (NA-fills failed folds, prints `%d/%d rows used`); only the
wording was strengthened so a shortfall is stated rather than inferred from two numbers.

**Priority 4, `mod_timeseries.R`:** `decompose()` reports its error instead of a bare
"Decomposition failed"; the optional ADF test says it could not be computed instead of printing
nothing — which had made a *failed* test indistinguishable from one that was never on the screen.

**Presentation:** new `.cv_note()` in `helpers.R`; `.prf_dt()` gained `note =` so the caveat
travels in the **same caption as the accuracy**. Returns `NULL` on a clean run.

### `check_cv_folds.R` — new guard, control-tested both ways

Asserts the old 0.5 rule *does* predict the unfitted class, and injects a real fold failure and
requires the caveat to appear: *"Incomplete: 1 of 5 folds could not be fitted, so 18 row(s)
(20% of the data) are NOT included."* 24 assertions, no skips.

**Three failed injection attempts are recorded in the file**, because each is a harness fault
this project repeats (gotcha 33): a rare factor level does not trigger "factor has new levels"
(R **retains unused levels when subsetting**); targeting by call number hit the main fit, since
the module fits more often than the loop iterates; a one-shot flag was consumed by the
module's **first** of two CV evaluations, so the returned value came from a second clean pass.
Only a stateless marker-row stub fires on every pass. A guard that passes because the failure
never reached the code proves nothing.

### `tools/testkit.R` — `ea_sig()` was broken

It failed on any function with a required argument. A formal with no default **is the empty
symbol**, and binding it (`d <- fm[[n]]`) makes the local variable itself "missing", so the next
line touching `d` threw. Now tests the flag and reads the default only where one exists. Found
by using it, which is the only reason it was found at all.

## v0.11.1 — 2026-08-08

### Item 36 — the silent tryCatch sweep, Co-Analyst half

Five sites in `agent_tools.R` swallowed a failed metric to NULL and rendered `else ""`. The model
itself was always correct, so this is not wrong numbers -- it is **missing numbers, silently**, and
that is worse here than anywhere else in the app: this output is what the assistant ANSWERS FROM.
A metric that vanished without explanation left it two bad options -- report a model with no R2 and
no reason, or guess.

Sites: `lm` metrics, ANOVA's `TukeyHSD`, LME's `r.squaredGLMM` and metrics, and random forest's OOB
metrics.

`.agent_soft(expr, what)` returns `list(v, why)`; `.agent_why()` renders a one-line note. The whole
answer still survives a failed metric -- these legitimately fail (singular fit, absent optional
package, too few groups for Tukey), so failing the entire response would be the wrong trade. Saying
so plainly is the only version that keeps the answer truthful.

**Verified, 22 checks.** The one that matters: with `uef_evaluation` forced to fail, the model still
answers, the metrics are absent, AND the output names which figure failed and why. A **control**
reproduces the old shape and confirms it left no trace at all.

**Test-harness fault (ninth):** the first run called `.agent_run_analysis(pool, "d", "lm", ...)`;
the real signature is `(args, dataset_pool)` with args a list. Exactly what gotcha 33 says to avoid
-- build fixtures from the real signature. Fixed by reading it rather than guessing again.

### Reference page — internal name leaked
`uef_evaluation()` appeared in the metrics section of the PUBLIC reference page. Package functions
belong there (a user may need to cite `MASS::polr`); app internals do not -- the name means nothing
to a reader, and the calculation is the useful part.

Rewritten to describe what is computed, and **guarded**: `tools/build-reference.R` now fails the
build on any `uef_*`/`ea_*`/`.ea_*` call reaching the page. **Control-tested** -- injecting
`uef_evaluation()` into a note exits 1 and names it; removing it exits 0. Same class of leak the
release-notes guard already blocks, in the other generated page.

Note the regex uses character classes (`[.]`, `[(]`) rather than backslash escapes: the pattern
passes through a generator, and every added backslash is one more layer to get wrong -- the first
attempt died on exactly that.

### Still open on item 36
~194 `error = function(e) NULL` sites remain app-wide, but most are legitimate "not available"
guards where NULL is a true answer. The remaining NAMED priorities are the fold loops in
`mod_logistic.R`, `mod_classification.R` and `mod_lme.R`, and `mod_timeseries.R`'s decompose -- a CV
fold that fails silently is dropped from the average, which biases a reported metric rather than
merely omitting it. That is the more dangerous half and should be swept next.

## v0.11.0 — 2026-08-08

### Item 42, phases 1 and 2 — the analysis/map round trip

Minor bump, not a patch: the first time the two halves of the app can reach each other.

**Phase 1, the on-ramp.** `vec_attributes` ("Attributes to Table") in `algorithms.R`, using the
existing `pool = "table"` precedent so it is a registry entry and nothing else. All 14 statistical
methods become usable on a shapefile, previously impossible because `statServer` reads
`dataset_pool` only.

**Phase 2, the return leg.** `ea_action_to_layer()` in `statistics.R`, attached to robust, poisson,
negbin, gam and glmm. `statServer` now receives `vector_pool`/`raster_pool` and passes them to
actions -- `mod_stat.R` previously handed over only `list(table = dataset_pool)`, which is why no
action could ever touch the map.

**The join is the only part that really matters.** A model drops incomplete rows, so a positional
write-back attaches predictions to the wrong features and produces a map that looks plausible and
is wrong. Three mechanisms, none of them guesses:

- **`.ea_fid`** -- the row position in the source layer, carried in the exported table.
- **`ea_fit_rows()`** -- reads `model.frame(fit)` row names, which are R's OWN record of which
  original rows survived. Better than re-deriving `complete.cases()`, because each method decides
  for itself what usable means (its own `na.action`, a singleton factor level, a zero-variance
  column). Returns NULL when it cannot be established, and NULL means CANNOT LINK -- never
  "assume 1:n".
- **`ea_layer_fingerprint(v, cols)`** -- a digest proving the layer is unchanged, **scoped to the
  exported columns**. A test forced that scoping: a whole-table digest made the tool refuse its own
  previous write-back, because adding `pred` changed the layer. Scoping keeps every real protection
  (deleted feature -> row count, edited value -> digest, renamed column -> missing) while ignoring
  columns added afterwards. Geometry is excluded on purpose: moving a vertex does not invalidate a
  model fitted on attributes.

**Matched by fingerprint, not by name**, so a rename is harmless and a renamed-but-edited layer
cannot masquerade as the original.

**The fit record carries a minimal link** (`fid`, `fp`, `cols`) rather than a second copy of the
data frame, which for a large layer would double memory for a feature most fits never use.

**Verified, 36 checks**, weighted at the join: predictions land on exactly the right features with
rows 4/9/15 dropped by the model and left NA rather than shifting the rest; a deleted feature is
REFUSED and the layer left untouched; a rename still works; a second write-back suffixes rather
than overwrites; a layer with no attributes refuses with the .dbf hint; and an end-to-end run
(export -> fit -> write back) puts numeric values on the right features, ready for graduated
symbology.

**Deliberately not attached to the classifiers or ordinal regression:** `polr`'s `fitted()` is a
probability MATRIX, so there is no single value to map. The action refuses safely there, but a
button that always refuses is worse than no button.

### Still to come on item 42
Phase 3 (a `model_pool` so fits outlive their screen -- decided: **saved with the project**) and
phase 4 (predict onto a raster surface). Phase 4 is impossible without phase 3.

## v0.10.27 — 2026-08-06

### Raster symbology — the second half of round-3 item 11

What it replaced: the single-band branch of `.draw_layers()` was hardcoded to **band 1, viridis,
`range(vals)` and `opacity = 0.85`**. The band was the worst of those — a multi-band stack could
only ever show its first.

Stored under **`ras`** in the same `layer_style` entry, so `mode`/`r`/`g`/`b` (RGB composite),
`vec` and `ras` coexist without collision. Persisted in the project like the rest.

- **`.ras_range()`** resolves the display range: minmax / 2-98 / 5-95 / manual. Falls back to the
  data range when manual is blank or inverted, and returns NULL for a constant or empty raster so
  the caller skips drawing rather than building a degenerate palette.
- **`.ras_pal()`** builds one leaflet palette from the style — `colorNumeric` for continuous,
  `colorBin` with even breaks for 3-9 classes. Reverse applies to both.
- The band is **clamped** to `nlyr()` at draw time, so a stored band from a raster that was later
  replaced by a narrower one cannot error.
- UI only appears when NOT in RGB composite mode; a true-colour composite has no ramp to configure.

**Verified, 30 checks.** The one that demonstrates the point: a test raster whose band 2 holds four
outlier pixels at 1e4 gives **full range 0-10000** versus **2-98% = 0.2-9.8** — the flat-grey
problem, and the fix, measured. Also: manual honoured; blank and inverted manual both fall back;
constant and empty rasters produce no palette; continuous gives >10 distinct colours where 5
classes gives at most 5; reverse changes the mapping; every control stores and persists under
`ras` without colliding; out-of-range band still renders.

**Test discipline held this time** — 30 checks, no false failures, because every assertion is
behavioural (call the function, inspect the result) and the fixtures were built from the real
signatures. See the rules recorded as gotcha 33.

### Docs
- **Item 65** opened: drag layers up/down. Recorded that this is **draw order, not just panel
  order** — `.draw_layers()` adds in sequence and leaflet puts the last on top — so it needs an
  explicit persisted order, `.draw_layers()` following it, a drag handle that does not fight the
  three existing click targets on a row, and the basemap row staying pinned.
- **Item 66** opened: the eight false test failures, categorised by root cause, with the rules that
  follow. Condensed into **CLAUDE.md gotcha 33**.
- Fixed a stale label on the published page: the header read "generated from CHANGELOG.md" after
  the source moved to `RELEASE_NOTES.md`. It now says "updated with every release" — naming an
  internal file on a public page is the same leak the guard blocks in release bodies. An older
  release body naming `release-notes.html` was cleaned too.

## v0.10.26 — 2026-08-06

### Item 38 — delete features (GIS parity Step 4)

The first destructive map operation, so it sits behind an explicit `edit_mode` toggle (the QGIS
pencil idiom). Without it a stray click could remove data from a layer someone meant only to view.

- **Undo per layer**, `.EDIT_UNDO_MAX = 5L`, newest last — deliberately mirroring `mod_data.R`'s
  stack. Keyed by layer name so an undo cannot restore layer A's geometry into layer B.
- **Pruning filters on the VALUE, not `names()`** — gotcha 14, applied pre-emptively this time
  rather than after the leak. `vector_pool[[k]] <- NULL` keeps the name.
- **The selection is cleared after a delete.** Row numbers shift, so keeping it would highlight
  whatever now occupies those positions — a different feature.
- **Refuses to empty a layer**: deleting every feature is a layer removal, not an edit.
- **Switching layer disarms edit mode**, or someone deletes from the wrong one.
- **A selection belonging to another layer is refused** (`identical(s$layer, nm)`), and
  out-of-range rows are clamped.
- `.ea-wsx-selclear.on` (warn) and `.ea-wsx-seldel` (danger) make the armed state visible — a
  destructive mode that looks like a passive one is the failure to avoid.

**Verified, 24 checks:** refused when not editing; the right features go and the rest survive;
selection cleared; undo restores byte-identically; 7 deletes retain 5 snapshots and no stack is
created for an untouched layer; emptying refused; layer switch disarms; a foreign selection is
refused; out-of-range clamped; undo with no history refuses cleanly; no Edit control on a table
layer.

**Two test faults, not code faults.** Sections G/H toggled edit mode blindly and inherited an
armed state, silently disarming it — fixed with an explicit `arm()` helper. Section I then failed
because section E had whittled that layer to a single feature, so the do-not-empty guard correctly
refused; the test needed its own layer. **The code was right both times.**

### Item 60 — the tab-switch grace period was arbitrary

The 30 s window was wrong in both directions: away for a minute and the panel still appeared,
while a genuine failure 20 s after glancing at another tab was hidden.

Replaced with **state, not elapsed time**: a disconnect arriving while `document.hidden` sets
`eaPendingDc` and is **held indefinitely**; the `visibilitychange` handler decides it when the page
is visible again. `shiny:connected` clears the flag, so a drop that recovered while away produces
nothing at all.

**Verified behaviourally** (functions extracted from `ui.R`, run against a fake document with a
controllable clock): an hour hidden shows nothing and holds the disconnect; five minutes away then
returning shows the panel after the delay; recovered-while-hidden shows nothing; a real disconnect
on a visible tab still reports; a momentary drop is cancelled; Quit exempt; hidden during the delay
does not pop up behind the tab.

**My own escaping trap:** rewriting the test through a Python patch put `
` inside JS string
literals — gotcha 1b, in the test this time. Rewrote the file directly instead.

### Housekeeping
- Deleted `verify_step3.R` from the scratch tests: it asserted the coordinate hit-testing that
  v0.10.20 deliberately removed, so it failed by design. `verify_v20.R` is the current test for
  identify. A stale test that fails is worse than no test.

## v0.10.25 — 2026-08-06

### Item 60 — a hidden tab was reported as a disconnect

My defect from v0.10.14. `eaShowDisconnect` fired on `shiny:disconnected`, and a backgrounded tab
has its websocket throttled or dropped by the browser — indistinguishable from a real failure at
the instant the event arrives.

Three changes, all in the client:

- **`visibilitychange` records `window.eaLastHidden`.** The handler returns early if the page is
  hidden *now*, or was hidden within the last 30 s. That covers both "dropped while away" and
  "dropped on the way back".
- **A 2.5 s delay before showing anything** (`window.eaDcTimer`). A momentary drop usually
  reconnects on its own, and a panel that appears and vanishes is worse than no panel. Split
  `eaShowDisconnect` (decide) from `eaRenderDisconnect` (show) so the delay has something to call.
- **`shiny:connected` now clears the pending timer as well as the shown panel.** Without that, a
  drop that recovered inside the delay still popped the panel afterwards — the exact interruption
  being fixed.

`eaRenderDisconnect` re-checks `eaQuitting` and `document.hidden`, so a tab hidden *during* the
delay cannot have a panel appear behind it.

**Verified behaviourally, not by grep.** `verify_tab.mjs` extracts both functions from `ui.R` by
brace-matching and runs them against a fake `document`/`window` with a controllable clock: hidden
tab → no panel; just-returned → no panel; real disconnect → nothing immediately, panel after the
delay; reconnect inside the delay → cancelled; quitting → exempt; hidden during the delay → no
panel. All 7 pass. `check_ui_js` PASS (9 blocks), symbology regression clean, serves 200.

**Harness fault (sixth this session):** the first run threw `TypeError: Cannot read properties of
undefined (reading 'pathname')` — my fake `window` had no `location`, which `eaRenderDisconnect`
needs for the server probe. The code was fine.

### Docs
- Symbology recorded as **tested and working by the reporter**, with deferred improvements listed
  explicitly so they are not mistaken for oversights: raster symbology (stretch / classified /
  paletted / hillshade), rule-based styling, labels, more break methods (equal interval, Jenks,
  stddev, manual), size-by-value for points, and style presets.
- **DOI still not done** — `.zenodo.json`, `DOI.md` and the commented `identifiers` block are all
  waiting on a Zenodo login.
- **Desktop icon on existing installs: answered from the code.** Re-running the installer is
  enough — it re-downloads the app (`install.ps1:100-104`), recreates both shortcuts
  unconditionally (`:217-223`) and copies the `.ico` into `$AppHome` each run (`:210-212`). Caveat
  recorded: Windows caches shortcut icons, so Explorer may show the old one until sign-out; and a
  *missing* shortcut is a different failure that prints a warning during install.

## Documentation split — 2026-08-06 (no version; nothing shipped)

Three files, three audiences, enforced by the build.

- **RELEASE_NOTES.md** is now the ONLY published file. `build-release-notes.mjs` and the GitHub
  workflow both read it instead of this one.
- **CHANGELOG.md (this file) is internal.** It can be as raw and detailed as useful — root causes,
  file paths, gotcha numbers, what was verified and what was not.
- **BACKLOG.md** is unchanged: the engineering log, by round and item.

Why: internal vocabulary had leaked onto the live site. Nine instances were published —
`BACKLOG item 24`, `Round 4 (items 18-25)`, `CLAUDE.md gotcha 27/28/29`, `Backlog item F24`,
`Gotcha 22`, plus `uef_evaluation()` named directly — all reading as jargon about tickets a
visitor cannot see. The seed for RELEASE_NOTES.md was this file with those stripped; the originals
stay here.

The guard in `build-release-notes.mjs` now fails the build on `BACKLOG`, `CLAUDE.md`,
`gotcha N`, `backlog item N`, a bare `item N.` or a reporter quote. **Control-tested**: injecting
`(BACKLOG item 99)` exits 1 and names the line; removing it exits 0.

Consumers repointed: the workflow's path filter, its commit message, the builder's error text and
the release-notes checker.

## v0.10.24 — 2026-08-06

### Added — a Reference page: what EasyAnalysis actually computes

There is a new **Reference** page on the website describing what happens when you run an analysis:
the R function behind each method, the variables it needs, the options it offers, and what the
results mean. It covers 14 statistical methods and 50 spatial operations.

**The page is generated from the application itself.** The method names, variable roles, options
and the underlying function calls are read out of the app when the page is built, so they cannot
drift away from what the software actually does. Assumptions and caveats are written by hand,
because those cannot be derived from code.

If you are publishing a result, this is the page that tells you what to describe in your methods
section.

### Changed — Documentation is now "Getting started"

The old Documentation page was doing two jobs: helping new users find their way around, and
serving as the reference for what the app does. It is now **Getting started** — install, the
workspace, menus, file formats, projects, privacy and troubleshooting — and the method detail
lives on the new Reference page. Existing links still work.

## v0.10.23 — 2026-08-06

### Fixed — undo history for deleted datasets was never released

Undo keeps up to five steps of history for each dataset. When a dataset was removed from the
project its history was meant to be released with it, but never was, so a long session slowly
accumulated saved copies of data that no longer existed. Removing a dataset now frees its history
straight away.

Undo itself is unchanged: still five steps, still separate for each dataset, and it tells you how
many steps remain each time you use it.

## v0.10.22 — 2026-08-06

### Added — map symbology for vector layers

Layers were always drawn in the same green. You can now style each one, and the settings are saved
with the project.

Expand a layer in the **Layers** panel and choose how it is drawn:

- **Single symbol** — one fill and outline colour for the whole layer.
- **Categorised** — a colour per distinct value of a column, such as species or land-cover class.
- **Graduated** — a numeric column split into 3 to 9 shaded classes, such as volume or height.

Categorised and graduated layers get a legend showing what each colour means. Five colour ramps
are available, four of which stay readable for the most common forms of colour blindness.

Only columns that suit the mode are offered, so you cannot accidentally colour by something that
gives every feature its own colour. Class boundaries for graduated layers are chosen so each class
holds a similar number of features, which keeps skewed data readable.

Outline width and fill opacity can be adjusted in every mode. Selected features stay outlined in
red whatever styling you choose, so a selection is never lost in the colour scheme.

Symbology is reached in two ways: **right-click a layer** in the Layers panel and choose
**Symbology…**, or use **View ▸ Layer ▸ Symbology…** for the layer you are working in. Either one
selects the layer, switches to the map if you were on the data view, and opens its settings.

Full details are in the documentation under **Map symbology**.

## v0.10.20 — 2026-08-06

### Fixed — clicking a point on the map did nothing

Identify worked on polygons but not on point layers. Clicking a point marker was being handled
differently by the map, and the code was watching for the wrong thing, so the click never
registered.

Every feature drawn on the map now carries its own identity, so a click reports exactly which
feature was hit rather than working it out from coordinates. Points, lines and polygons all
identify the same way, and clicking a feature of a layer you were not already working in switches
to that layer.

### Changed — the map only moves when you ask it to

The map used to zoom automatically to frame your data the first time a layer was added. It no
longer moves on its own: use **Zoom to layers**, **Zoom to active layer**, or the **Zoom to**
button beside the selection count.

This also means selecting features no longer disturbs the view you have set up.

## v0.10.19 — 2026-08-06

### Fixed — the identify panel stayed only for a moment

Clicking a feature showed its attributes, but the panel closed again as soon as you clicked
anywhere on the map. It now stays open until you close it with the X, so you can read it, compare
it with the table, and pan around without losing it. Closing it leaves the feature selected.

### Fixed — the identify panel ignored the theme

It was drawn on a white background with dark text whatever theme was in use, which made it hard
to read on any of the dark themes. It now uses the theme's own colours, including a clearly
visible close button.

## v0.10.18 — 2026-08-06

### Added — click the map to identify a feature

Clicking a feature on the map now selects it: the feature is outlined in red, its row is
highlighted in the attribute table, and a panel shows its attributes at the point you clicked.
Clicking empty space clears the selection.

It works both ways round now — click a row to find it on the map, or click the map to find it in
the table.

Clicking a raster shows the value of every band at that point instead, with empty cells shown as
"no data".

Points and lines are matched to whatever is nearest within a few pixels of where you clicked, and
that allowance scales with how far you are zoomed in, so it stays usable at every scale.

### Added — Zoom to selected

A **Zoom to** button next to the selection count fits the map to the features you have selected.
Selecting a single point zooms to a sensible scale around it rather than as far in as the map can
go.

## v0.10.17 — 2026-08-06

### Fixed — selecting a row now actually highlights the feature

The feature added in the previous version did not work: selecting rows in the attribute table
changed nothing on the map. The right features were being found; they were simply never drawn.
Selecting a row now outlines those features on the map.

### Changed — the highlight is red, and drawn as an outline

Selected features are outlined in red. The outline carries the highlight rather than a solid
fill, so the selection stays visible over satellite imagery and you can still see the feature
underneath instead of it being covered up.

## v0.10.16 — 2026-08-06

### Added — select a feature in the attribute table and see it on the map

Selecting rows in a layer's attribute table now highlights those features on the map in amber.
Select several and they all highlight; the header shows how many are selected and offers
**Clear**, which matters because selections build up as you sort and page through a large table.

Selecting a row no longer redraws the map, so it stays quick even with a large raster underneath,
and the highlight survives anything that rebuilds the map. Switching to a different layer clears
the selection, since row numbers only mean something for the layer they came from.

This is the first half of working with features directly; clicking the map to identify a feature
comes next.

### Added — how to cite EasyAnalysis

The documentation had a placeholder where the citation should be. There is now a full citation in
APA and BibTeX on the documentation page, and a `CITATION.cff` in the repository, so GitHub's
**Cite this repository** button produces it for you.

If you used a published method through EasyAnalysis, please cite that method as well — its paper
is listed on the app's **References** screen. Citing the tool does not replace citing the method.

## v0.10.15 — 2026-08-06

### Fixed — tables of your own data were limited to 100 rows a page

Whatever the size of your dataset, the largest page a table would show was 100 rows, and there
was no way to ask for more — so a table of thousands of rows looked like it held 100.

The attribute table, the data view and the View Data window now let you choose
**10 / 25 / 50 / 100 / 500 / 1000 / All** rows a page. The data view had a second, separate limit
that stopped it at 200 rows regardless; that is gone too, so all three now show the whole
dataset.

## v0.10.14 — 2026-08-06

### Fixed — the app no longer becomes unusable after the computer sleeps

Closing a laptop lid, or leaving the machine to sleep, broke the connection between the page and
EasyAnalysis. All you got was a grey screen with no way to recover — the app looked permanently
broken, and the only way back was to find and run the launcher again.

There is now a panel that explains what happened and offers a **Reconnect** button. It also
checks whether EasyAnalysis is still running and tells you which situation you are in:

- still running (the usual case after sleep) — Reconnect picks up where you left off
- no longer running — it tells you to start EasyAnalysis again from the Desktop shortcut

Your project is saved as you work, so nothing is lost either way.

## v0.10.13 — 2026-08-06

### Fixed — the attribute table stopped at 200 features

A layer's attribute table only ever showed its first 200 features, with nothing to indicate there
were more — so a shapefile with thousands of features looked like it had 200. It now shows every
feature, and you can select rows in it.

### Changed — two ways to run EasyAnalysis, and only two

Installing is done once, from the terminal. On Windows that install then creates an
**EasyAnalysis** shortcut on your Desktop and in the Start Menu, and from then on you just
double-click it — no terminal in day-to-day use.

The downloadable Windows setup file offered briefly in the previous version has been withdrawn.
Windows security features restrict downloaded files of that type, so it was not a dependable way
to install. The one-line command remains the supported route on every platform, and is unchanged.

A properly signed Windows installer is still planned; that is the version that will work without
any of these restrictions.

## v0.10.12 — 2026-08-05

### Fixed — the documentation still described the old way in

The walkthrough told you to *"keep the terminal window open while you work"* and to re-run the
install command every time you wanted to start the app. Neither is true any more: there is a
**Quit** button, and on Windows there is a Desktop shortcut. The reference page never mentioned
either, and the project's README offered no install instructions at all.

All four now describe the same thing: download and double-click on Windows, or use the one-line
command on any platform; restart from the Desktop shortcut; close with **Quit**. The security
prompt Windows shows for downloaded installers is explained rather than left as a surprise.

The terminal remains a fully supported way to install and run EasyAnalysis — it is the route on
macOS and Linux, and nothing about it has changed.

## v0.10.11 — 2026-08-05

### Added — EasyAnalysis now has its icon, everywhere

The Desktop shortcut added in the previous version used a generic PowerShell icon. It now uses
the EasyAnalysis mark, built at seven sizes so it stays sharp from the taskbar to large-icon
view.

### Fixed — the website and the app had no icon at all

The favicon had been in the project since July, but it was never placed where the website could
serve it and no page ever referred to it. So the site showed a blank icon in browser tabs and
bookmarks, and `favicon.ico` returned "not found" — despite an earlier release note saying this
was done. It works now.

The app's own browser tab had the same problem and now shows the icon too.

## v0.10.10 — 2026-08-05

### Added — no more terminal: download it, double-click it, done

Until now the only way in was to open PowerShell and paste a command — and because nothing
created a shortcut, **that was needed every single time you wanted to open the app**, not just to
install it. Someone who installed last week had no way back in except finding that command again.

Two changes fix it:

- **The installer now creates an EasyAnalysis shortcut** on your Desktop and in the Start Menu.
  After the first install you just double-click it. It starts in seconds, because it skips
  everything already downloaded.
- **There is a downloadable installer** on the website for people who would rather not touch a
  terminal at all. The one-line command still works and is still documented for anyone who
  prefers it.

The shortcut opens the app minimised rather than hidden, so if something ever goes wrong there is
still a window to look at. Close the app with the **Quit** button.

Windows may warn that the downloaded file came from the internet — choose **More info → Run
anyway**. That warning appears for any installer that has not been signed with a paid
certificate; it is not a sign that anything is wrong.

*(The shortcut is Windows-only for now, and it still uses a generic icon.)*

## v0.10.9 — 2026-08-05

### Fixed — nothing was clickable in v0.10.7 and v0.10.8

The Quit button added in v0.10.7 carried a hidden line-break character in its confirmation
message. That one character was invalid where it landed, which stopped **the whole block of the
app's interface code from loading** — so every button in the top bar went dead at once. Projects
would not open, Settings would not open, and the app otherwise looked completely normal, which
made it hard to tell anything was wrong.

Fixed, and a check now runs over the app's interface code to make sure it is valid before a
release. That check was written against this exact bug and confirmed to catch it — the previous
tests only checked the message *text was present*, never that the code around it worked.

**If you are on v0.10.7 or v0.10.8, update.** Those versions are unusable.

## v0.10.8 — 2026-08-05

### Added — the site can now be found

The website had no sitemap and no `robots.txt`, so nothing told a search engine or an AI
assistant which pages existed. Both now exist, and AI crawlers are welcomed explicitly rather
than left to guess — people increasingly find tools by asking an assistant, and there is nothing
here worth withholding.

Every page also gained a canonical URL, link-preview tags (so a shared link shows a title and
summary instead of a bare address), and structured data describing what EasyAnalysis is, what it
costs, and what it runs on.

### Fixed — the summary written for AI assistants was unreachable, and wrong

`llms.txt` is a plain-language description of the tool intended for AI assistants. It was sitting
in the wrong folder, so **the published site returned "not found" for it**, and its contents still
described the old browser-based version — claiming the app ran inside the browser with no install,
which stopped being true some time ago. It also used the assistant's former name.

It is now published at `easyanalysis.dev/llms.txt` and describes the current app: a local install,
the real setup commands, and what it can actually do.

*(No link-preview image yet — one still needs to be made.)*

## v0.10.7 — 2026-08-05

### Added — a Quit button

There was no way to close EasyAnalysis from inside the app. Stopping it meant closing the R
console window the launcher opened — which is also why the app could not be started from a
tidy desktop shortcut: hiding that window would have left no way to stop it at all.

**Quit** now sits at the right of the top bar, on every screen. It confirms first, stops the R
session, and replaces the page with a plain "EasyAnalysis has closed — you can close this tab"
message rather than the grey disconnected screen, which looked like a crash.

### Fixed — an invisible R process could be left running

Closing the browser cleared the app's data but never shut down the background R session used for
heavy, cancellable jobs. That session kept running with nothing attached to it, invisible, until
the machine was restarted. It is now shut down both when the browser closes and when you press
Quit.

## v0.10.6 — 2026-08-05

### Added — turn the basemap off from the Layers panel

Data layers already had a switch each; the **basemap** was the one thing on the map with no row
and no switch. Turning it off meant hunting for "None" at the bottom of a 14-entry menu.

There is now a **Basemap row** at the bottom of the Layers panel — where it belongs, since the
basemap draws beneath every data layer. Same toggle switch as a layer, but no remove button and
no expander: it is tiles, not a project layer. Its label shows which basemap is active, so the
row doubles as a readout. It appears even in an empty project, because there is still a map to
turn off.

The toggle is deliberately the **same state** as the menu's existing "None" entry rather than a
second flag, so the two can never disagree — and switching back on restores the basemap you were
using, not the default.

### Added — pick your theme before you start

The theme picker used to live only in the workspace View menu, which does not exist until a
project is open. **Theme is now the first section in Settings**, and the Settings gear is on the
topbar from the moment the app loads — including on the Projects screen. Six swatches, each
previewing its own background and accent colour.

Both entry points call the same function, so there is one mechanism, not two. Changes apply
instantly and are remembered on this computer.

*(A black & white theme is still on the list — this change moves where the picker lives, it does
not add a palette.)*

## v0.10.5 — 2026-08-05

### Fixed — CRS search really does query GDAL/PROJ now

CRS search felt hardcoded, and some coordinate systems could not be found at all. Both symptoms
were real, and they had three separate causes. The search function queried PROJ's `proj.db`
correctly — but **nothing ever called it with a query.** Every picker was built from a **static
500-entry list**, which selectize then filtered in the browser, so what you typed never reached
the database.

| | Before | After |
|---|---|---|
| CRS you can pick | 500 | **6,886** |
| `"utm 35n"` | 0 hits | **17 hits** |
| `"amersfoort rd"` | 0 hits | **3 hits** |
| Without `RSQLite` installed | 8 hardcoded codes | listed as a dependency |
| Page weight per picker | 509 KB if built client-side | **0.9 KB** |

- **The list stopped at EPSG:32632.** It was ordered by numeric code and cut at 500, so British
  National Grid (27700), UTM 35N (32635), Belgian Lambert 72 (31370), Czech Krovak (5514) and
  Dutch RD New (28992) simply were not in it.
- **Search was one `LIKE '%whole query%'`**, so multi-word searches always failed — the real
  name is "WGS 84 / UTM zone 35N", which `%utm 35n%` cannot match. Matching is now tokenised:
  every word you type must appear somewhere in the entry, so a code, a name, or a mix all work.
- **`RSQLite` was in neither dependency list**, and it is the only way to read `proj.db`. On a
  fresh install every picker silently degraded to 8 hardcoded codes — which is what made the
  picker feel hardcoded in the first place. It is now an `extras` dependency.
- The catalogue is attached **server-side**, which is what makes 6,886 entries practical at all:
  embedding them measured 509 KB per picker and the app builds five of them.
- `mod_raster.R` stopped claiming it was "Querying 7,000+ official GDAL/PROJ EPSG…" while
  offering 500.

Only `vertical` and `engineering` systems are withheld, because neither can serve as a
horizontal target CRS. Anything not in the catalogue can still be typed in by hand.

### Changed
- The workspace's tool-render signal now reports **which** tool rendered, not just that one did,
  so a panel can re-arm its own controls without every other panel re-arming too.

## v0.10.4 — 2026-08-05

### Added
- **Release notes on the website, kept up to date automatically.** Every version's entry is
  now published at **easyanalysis.dev/release-notes.html**, generated from this file and
  regenerated by CI whenever it changes — so the page can never drift behind the app. Each
  version has its own link, so a support answer can point at one release.
- **"What's new in this version"** next to the version number in the app's About panel. The
  notes existed nowhere a user could reach them before.

### Fixed
- The About panel read "an Co-Analyst" — a slip from renaming the assistant in the previous
  version.

## v0.10.3 — 2026-08-05

### Fixed
- **More fixed-light surfaces found by an app-wide scan**, the same fault as the References
  page rather than new ones: the confusion-matrix cells on Classification, the F1 bar, the
  macro-average row in every precision/recall table, and GAM's Yes/No non-linearity column
  were all fixed pastels that stayed pale on a dark theme. They are translucent tints of the
  theme's own colours now, so they keep their meaning and follow the theme.
- The Recommender's priority colours, a Download-spatial-data caption, the active dataset
  row's text, and the Co-Analyst's typing dot and disabled send button were likewise pinned
  to fixed colours.

### Changed
- The Recommender's "Ask AI" button — a robot emoji plus a **fourth** name for the same panel
  — is now an icon and "Ask Co-Analyst". (The visual language rules emojis out.)

## v0.10.2 — 2026-08-05

### Fixed
- **The References page was unreadable in every theme except light.** Each reference card was
  pinned to a white background with fixed grey text, so on any dark set the card stayed white
  while the text that had no explicit colour inherited the app's light body colour — which is
  why some lines read as black and others vanished. The whole page now uses theme colours,
  including the Implemented / In progress / Cataloged badges.

### Changed
- **One name for the assistant: "Co-Analyst".** The Analysis menu offered it as "AI
  Assistant" while its own panel header and the top-bar button both said Co-Analyst — three
  names in the code for one feature. Everything now says Co-Analyst.

## v0.10.1 — 2026-08-05

### Fixed
- **Discriminant Analysis validated a different model than the one you configured.** Its
  cross-validation refitted each fold with the package defaults instead of the settings you
  chose — Kernel DA ran at the default RBF width and cost rather than yours, Maximum Margin
  ignored its cost, and Locally Linear DA always used 5 neighbours whatever the slider said.
  Measured on test data: a default-parameter fold agreed with the configured model on only
  **38% of rows**, so the reported accuracy described a substantially different classifier.
- **Locally Linear DA's validation silently scored a different method entirely.** When that
  fit falls back to its PCA-decorrelated form (which happens whenever the local covariance is
  singular), the validation no longer recognised it and quietly cross-validated plain LDA
  instead. It now validates the method actually used, and says so honestly when it cannot.

## v0.10.0 — 2026-08-05

### Changed
- **ANOVA is now a registry entry** — the last of the nine screens migrated. Verified against
  `aov()` and `TukeyHSD()` directly: identical ANOVA table, identical Tukey comparisons,
  identical eta-squared, Cohen's f and leave-one-out cross-validation. **No bug was found in
  this screen.**
- **All nine screens are migrated.** XGBoost, SVM, Decision Tree, Neural Network, PCA/FA/MDS,
  GAM, Random Forest, Survival and ANOVA now share one variable picker, one result layout and
  one place to add the next analysis. Adding one is a list entry rather than a new screen.

### Fixed across the migration (v0.9.1 – v0.10.0)
Nine screens were ported; **ten faults were found in seven of them**, every one pre-existing
and none reported by a user — because each failed silently or produced plausible-looking
numbers:

- **Three screens could not produce a result at all.** XGBoost errored the moment you pressed
  Train (a package API had moved underneath it); GAM never fitted a model, ever; Survival's
  Cox proportional-hazards model never fitted.
- **Five screens validated a different model than the one on display** — SVM, Decision Tree,
  Neural Network, GAM and Random Forest all refitted their folds with settings you had not
  chosen, so the accuracy figures described a model you were not looking at. In SVM's case the
  cross-validation had never produced any result at all.
- **PCA and ANOVA were clean.**

## v0.9.8 — 2026-08-05

### Fixed
- **The Cox proportional-hazards model never fitted.** Adding covariates produced nothing at
  all, with no error shown. The formula it built used internal column names starting with
  underscores, which R cannot parse as variable names — so the formula failed before the model
  was ever attempted, and the failure was silently discarded. Cox models now fit, with the
  proportional-hazards check alongside them.
- Kaplan-Meier and the log-rank test were unaffected and always worked; only the Cox half was
  broken.

### Changed
- **Survival analysis is now a registry entry** (migration 8 of 9), verified against the
  `survival` package directly: identical survival curves, risk sets, log-rank chi-square and
  Cox coefficients, under both tie-handling methods.
- An event indicator that is not 0/1 is now refused with a message naming the offending
  values, instead of producing a meaningless model.
- The Cox and log-rank views explain what to choose when you have not selected covariates or
  a grouping variable, rather than showing an empty panel.

## v0.9.7 — 2026-08-05

### Fixed
- **Random Forest's 10-fold CV described a different forest than the one you trained.** It
  never passed your tree count through, so the CV curve always came from 500-tree forests
  however you set the slider — and it used the classification `sqrt(p)` rule for choosing
  variables per split even on a regression model, whose displayed fit used `p/3`. Both now
  match the model on screen.

### Changed
- **Random Forest is now a registry entry** (migration 7 of 9), verified to produce
  **identical out-of-bag predictions and identical variable importance** to the module it
  replaces, for both regression and classification, with the same `mtry` rules.
- Its partial-dependence plot still sits behind its own button (it is slow on large forests)
  and now reports clearly when the chosen variable was not one of the model's predictors.

## v0.9.6 — 2026-08-05

### Fixed
- **The GAM screen could never fit a model at all.** Every "Fit GAM" ended in an error
  notification. It built its smooth terms as `mgcv::s(...)`, and mgcv does not recognise a
  namespaced smooth — it identifies one by the term label starting with `s(`, so the
  namespaced form was treated as an ordinary variable and the fit failed with
  `invalid type (list) for variable 'mgcv::s(...)'`. The screen now fits.
- **Its cross-validation also dropped two of your settings** — the fold models were built
  without the smooth type you chose (always the thin-plate default) and with smoothness
  selection hardcoded to REML. So a cubic-regression GAM selected by GCV.Cp would have been
  validated as a thin-plate REML fit. Both now match the model on screen.

### Changed
- **GAM is now a registry entry** (migration 6 of 9), verified against `mgcv::gam` directly:
  identical coefficients, fitted values and R-squared, including a non-default basis and
  selection method.
- Its "Predictions to data pool" button is preserved, and GAM now says what went wrong when a
  fit fails (too large a basis, too many predictors) instead of showing a raw message.

## v0.9.5 — 2026-08-04

### Changed
- **PCA / Factor analysis / MDS is now a registry entry** (migration 5 of 9), verified against
  `prcomp`, `cmdscale` and `factanal` directly: identical loadings, scores, standard
  deviations, MDS coordinates and factor uniquenesses.
- Factor analysis now explains itself when it cannot run. Asking for more factors than the
  variables support used to surface R's bare complaint; it now says what failed and what to
  try instead (fewer factors, or Principal axis).
- The method-specific options (rotation, distance metric, component axes) appear only for the
  method they belong to, and "Colour points by" only for PCA.

- The colour-by column is subset by the same complete-case filter as the data, so it stays
  aligned with the points when a variable has missing values. (Verified rather than changed —
  the old screen did this correctly too.)

## v0.9.4 — 2026-08-04

### Fixed
- **The Neural Network screen's validation ignored your Max iterations setting.** Both of its
  cross-validation loops trained each fold for a hardcoded 200 iterations, so a network you
  trained for 1000 was being scored against one trained for 200. Third screen in a row with
  a validation that measured a different model than the one on display. The folds now use the
  iteration count you set.

### Changed
- **Neural Network is now a registry entry** (migration 4 of 9), verified to produce
  **identical predictions and an identical final objective value** to the module it replaces,
  for both regression and classification, including a non-default architecture (hidden units,
  decay, iterations, restarts and scaling all changed together).
- Its validation is computed once when you press Run, and a regression network now refuses a
  categorical response with a clear message instead of failing inside `nnet`.

## v0.9.3 — 2026-08-04

### Fixed
- **The Decision Tree screen's validation scored the wrong tree.** Its per-fold refits were
  built with rpart's *default* settings instead of the max depth, cp, min-split and
  min-bucket you had set — so the validation numbers described a tree you were not looking
  at. Measured on the test data: the default tree had **8 leaves** where the configured one
  had **2**. The folds now use the same controls as the tree on screen.

### Changed
- **Decision Tree is now a registry entry** (migration 3 of 9), verified to produce
  **identical predictions and an identical CP table** to the module it replaces, for both
  regression and classification trees, including non-default depth/cp/min-split settings.
- Its validation is computed once when you press Run, rather than being recomputed every
  time the results redrew — the same change SVM got.
- A regression tree now refuses a categorical response with a clear message instead of
  failing inside rpart, and the pruning control is labelled to distinguish it from the
  separate hold-out validation.

## v0.9.2 — 2026-08-04

### Fixed
- **SVM's cross-validation never worked.** It always showed "Awaiting SVM CV results…" and
  no result ever arrived. The refit inside each fold passed the fitted model's `kernel` back
  to `svm()` — but an e1071 model stores the kernel as an integer **code** (radial = 2), and
  feeding that back errors with "wrong kernel specification!". The error was swallowed by a
  `tryCatch` that returned `NULL`, so every fold failed silently and the screen waited
  forever. Now the kernel name is passed, and validation produces a result — and it honours
  the cost, gamma and scaling you actually set, which the old fold refits ignored.

### Changed
- **SVM is now a registry entry** (migration 2 of 9), verified to produce **identical
  predictions and identical support vectors** to the module it replaces, for regression,
  classification and a non-default kernel.
- **SVM validation is computed once, when you press Run.** The old screen recomputed the
  whole k-fold loop inside its render outputs, so every time the metrics table redrew it
  refitted k models. It now runs once under the progress bar, where a slow job belongs.
- SVM's two cross-validation controls are labelled so you can tell them apart — one is
  e1071's own built-in check, the other a separate hold-out validation. Both were present
  before with no indication which was which.

## v0.9.1 — 2026-08-04

### Fixed
- **XGBoost was broken and would error the moment you pressed Train.** Not a regression —
  the `xgboost` package changed its API in version 3.x and the screen was never updated. Two
  separate breakages: `xgboost(data =, params =, verbose =)` no longer exists (`params` was
  removed and `data` renamed to `x`), and `xgb.cv()`'s `best_iteration` moved out of the top
  level into `early_stop`, so the screen read `NULL` and passed it straight to the trainer.
  Both fixed while porting the screen, and the best-iteration lookup now checks both
  locations and falls back to the minimum of the test metric, so the next API move degrades
  instead of erroring.
- XGBoost also refuses a binary task on a response that does not have exactly 2 classes,
  instead of silently encoding a continuous column into hundreds of "classes".

### Changed
- **XGBoost is now a registry entry** rather than its own module — the first of the existing
  screens migrated onto `statistics.R`. Same method, same hyperparameters, same views;
  verified to produce **identical predictions** to the module's own computation. The old
  `mod_xgboost.R` is retired: still present, no longer registered or bound, so the screen
  appears once rather than twice.

### Added
- The registry can render **plots**, which it could not before. A spec declares drawing
  functions in `plots` and the runner binds one `renderPlot` per entry — a plot needs a
  device, so unlike a table it cannot simply be returned as UI. Also added boolean options
  and conditional options (a setting that only appears when it applies).

## v0.9.0 — 2026-08-04

### Added
- **Five new analyses**, and a registry so the next ones are cheap:
  **Ordinal regression**, **Robust regression**, **Poisson regression (counts)**,
  **Negative binomial**, and **GLMM (generalised mixed effects)**. Find them under
  Regression, or search for them.
- **GLMM fills a real gap.** The existing Mixed effects screen is `nlme::lme`, which fits
  Gaussian responses only — it has no `family` argument at all, so a yes/no or count outcome
  with random effects could not be fitted anywhere in the app. The new screen does binomial
  and Poisson with random intercepts, random slopes, and crossed or nested grouping
  variables, and reports singular fits and convergence trouble in plain language with the
  usual remedies rather than as a raw error.
- **`statistics.R` + `mod_stat.R`** — one spec per method, one generic runner, the same move
  `algorithms.R` made for spatial operations. Adding an analysis is now a list entry: no new
  module, no new variable pickers, no new view plumbing. Methods that genuinely do not fit
  (Tests, Discriminant analysis, Descriptive, Clustering) stay as they are.
- Every registry method shares one variable picker, generated from the roles the method
  declares — so predictor selection is finally identical across them, and the Co-Analyst sees
  a registry method exactly as it sees a hand-written screen.
- `lme4` added to the optional packages.

### Fixed
- `CLAUDE.md`'s note that `uef_evaluation()` was "available but unused" was out of date — it
  is called by the LME, Random forest and Linear regression screens, and now by the registry
  too. Corrected so the next reader does not wire up something that already works.

## v0.8.4 — 2026-08-04

### Fixed
- **Model results were unreadable in light mode.** The Model Summary, Performance Metrics and
  Cross-Validation blocks rendered light grey on white on every model screen. Bootstrap
  colours `<pre>` from `--bs-emphasis-color-rgb` — an `R,G,B` **triplet**, not the
  `--bs-emphasis-color` the app was overriding — and bslib compiles that triplet once from the
  default dark palette, so it stayed light text on every theme. It was never only `<pre>`: the
  same variable colours `code`, `.well`, `.navbar` and `.link-body-emphasis`, which is why the
  problem showed up across many screens. Each palette now emits the triplet, **derived from
  its own `ink`** with `grDevices::col2rgb()` so it cannot drift.
- **Fixed light panels stayed light in dark mode.** Twelve inline
  `background-color: #f8f9fa` / `#fff8e1` / `#e9ecef` blocks across six modules kept a cream
  or pale background while the app's light text ran across them — the Quick Builder and
  Convergence Options panels on Mixed effects being the reported case. Replaced with reusable
  classes (`.ea-subpanel`, `.ea-subpanel-warn`, `.formula-box`, `.ea-row-warn`,
  `.ea-row-flat`). The warn variants are translucent tints of the semantic colour, so they
  take their lightness from whatever is behind them and work on every set.
- No fixed-light panel hex remains in any module. The two `strip.background` values inside
  `mod_da.R`'s ggplots are deliberately kept: plots render on their own light canvas
  regardless of theme, so a themed colour there would be wrong.

## v0.8.3 — 2026-08-04

### Changed
- **Column types are spelled out.** The dataset summary showed tibble/pillar abbreviations
  (`dbl`, `int`, `fct`, `chr`, `lgl`) that mean nothing to anyone who does not write R — and
  this app exists so people do not have to. They now read **number, whole number, text,
  category, true/false, date**, with the R class kept as the cell's tooltip. The coloured
  badge behind them is gone too: it carried six hardcoded hex values that followed no theme,
  and the colour never said anything the word did not. (Backlog item 28.)
- **The Co-Analyst no longer offers suggestion chips.** They were the last place the app
  volunteered a next step, which contradicted its own system prompt — that already forbids
  the model from proposing one. The Recommend screen is kept and is where suggestions belong.
  (Backlog item 27.)

### Added
- **Undo now goes back 5 steps, not 1.** `snap()` was already the single choke point every
  data operation passes through, so the change is one bounded stack. Each undo reports how
  many steps remain, so the last press reads as "no further undo steps" rather than a dead
  button. Capped deliberately — each entry is a full copy of the data frame. (Backlog item 32.)
- **A "Docs" button in the app.** The documentation pages have been live on the website for
  days, but nothing inside the app pointed at them, so users who never visited the site never
  found them. It sits in the top bar on both the projects screen and the analysis area, and
  opens in a new tab so a running project is never navigated away from. (Backlog item 17.)
- **The guided tour covers 9 steps, up from 6** — added the tool search, Undo/Reset, and the
  new Docs link, clearing the "at least 8" requirement. (Backlog item F24.)

### Fixed
- **Undo could corrupt a dataset.** The undo snapshot was a single slot shared across every
  dataset, so switching from A to B and pressing Undo restored **A's data into B**. The stack
  is now per dataset, and stacks for deleted datasets are pruned.

## v0.8.2 — 2026-08-04

### Fixed
- **The app would not start on a machine without `plotly`** — the failure every fresh
  install hits. `plotly` was in **neither** the `core` nor the `extras` list in
  `launcher/deps.R`, so the installer reported `deps: OK` and the app then died at boot with
  `there is no package called 'plotly'`. Three causes, all fixed: `plotly` added to `extras`;
  the workspace's `output$chart_i <- plotly::renderPlotly(...)` binding guarded the way its
  UI already was (a `pkg::` in a binding resolves when the module server is **built**, so it
  threw before the UI's `requireNamespace()` guard could degrade to the static plot); and the
  `observeEvent(workspace_ctx$tool_open())` in `server.R` moved **after** the assignment it
  references, so a failure there no longer surfaces as a misleading "object not found" on
  every flush. Audited every other eager `output$x <- pkg::render*` binding — all use core
  packages, so `plotly` was the only one exposed. (CLAUDE.md gotcha 27.)
- **Nothing showed that the app was working.** Only 12 of 42 modules use `withProgress`, so
  on the other 30 — including most model screens — a slow fit looked like a frozen app. Worse,
  `ui.R` deliberately disables Shiny's own dimming (`--shiny-fade-opacity: 1`) on the promise
  of a "Running pill" that had never been built, leaving less feedback than stock Shiny. Added
  the global `#ea-busy` pill: pure CSS keyed off Shiny's `shiny-busy` class, so it needs no
  per-module wiring and works even while R is blocked (a server-rendered spinner cannot).
  Shown only by real request state, never a timer, and only after 400 ms so quick actions do
  not flash it. Also extended the existing skeleton shimmer to the model canvas.
  (CLAUDE.md gotcha 29.)
- **Native `<select>` popups and scrollbars ignored the theme.** Page CSS colours the closed
  control but not the browser-drawn popup list. Every colour set now declares
  `scheme = "light"|"dark"` in `theme.R` and `ea_theme_css()` emits a real `color-scheme`
  declaration; `:root` declares it too, since a first-time visitor has no `data-ea-theme`
  attribute yet while the default palette is dark. Added `option` colour rules as the
  Chromium-specific complement. (CLAUDE.md gotcha 28.)

### Docs
- `BACKLOG.md`: Round 4 (items 18-25) and a Round 5 reconciliation table mapping a re-sent
  batch of 24 reports onto existing entries — all 24 were already recorded.
- Recorded the **verified** state of the docs/tour surface: the landing documentation and
  how-to-use pages are built and linked, but the in-app tour has **2 of the 8+** steps asked
  for and **nothing in the app links to the docs**.
- `DOCS.md` now indexes the published `landing/` pages, which were missing from it entirely.

> **Changelog gap, stated rather than papered over:** work landed between v0.8.1 and this
> entry (2026-07-30 → 08-01: B6, B8, C9, C14, D17, round-3 items 7/9/10/14/16, the custom
> domain and the landing-site rewrite) that was never given a version or an entry here.
> `BACKLOG.md` records it in full. This is exactly the drift BACKLOG item 24 is about — a
> release-notes page publishes from this file, so an entry has to be part of finishing work.

## v0.8.1 — 2026-07-29

### Fixed
- **Model screens opened with empty variable selectors.** Linear regression, ANOVA and
  Random forest could not be run at all — by hand or by the Co-Analyst — because the
  workspace renders a module's panel lazily and `updateSelectInput` fired before the
  element existed. `active_dataset()` now depends on `ds_refresh`, bumped when a tool
  opens. (CLAUDE.md gotcha 18.)
- **Raster invisible on the map** although the view zoomed to it: layers were added by
  `leafletProxy` after the map element had been re-created. Tiles, view and layers are
  built in one pass now. Reprojection also ran at full resolution before downsampling
  (18.1 s, and a `warp failure` under memory pressure that `tryCatch` swallowed) — it is
  downsampled first, memoised, and the fit comes from the extent alone.
- **Zoom to layer** was wired to the same input as Zoom to layers, so it always framed
  everything; it now targets one layer and reports honestly when there is nothing to
  zoom to.
- **Adding a file yanked the map view.** The automatic fit now applies only to the first
  spatial layer; everything after overlays.
- **Dark surfaces on the light colour sets** (data tables, accordions, the R console,
  buttons) — Bootstrap's component variables restated from the tokens. (Gotcha 22.)
- **The R console cleared your script on every Run.** It keeps it now.

### Added
- **R console write-back.** Objects a script produces become project layers by class
  (data.frame, SpatRaster, sf, LAS), so a clip appears in the Layers panel and on the map.
  Only genuine OUTPUTS: consumed intermediates and aliases of loaded layers are skipped.
  Modes `auto` (default) and `ask` via `options(ea.console_sync)`.
- **Plot appearance app-wide** — title, axis labels and colour on every screen, stored per
  screen. ggplot via a `renderPlot` wrapper; base-R plots per call site, with multi-panel
  diagnostic grids taking only an overall title.
- **`.ea-pop`**, a reusable hover panel behind one icon; plot appearance is its first user.
- **Co-Analyst `run_in_app`** — opens the real screen, fills it and presses Run. Every name
  is verified against the loaded data; near-misses and case differences are refused, never
  substituted. Linear regression only so far.
- **True-colour RGB** for multi-band rasters with a per-layer band mapping (detected from
  the file, never guessed), point clouds drawn and a density slider reaching the file's
  full point count, a 3D view button, a dockable/floatable R console with line numbers,
  and a guided tour that now runs inside the workspace.

---

## v0.8.0 — 2026-07-27

**The unified workspace.** The ~35 separate analysis screens are now one workspace:
a GeoLibre-style menu bar, a layers panel, a canvas that follows your data, a tool
panel and a results dock. Plus a public site and a macOS/Linux installer.

### Workspace
- **One frame, two views** — *Map view* and *Data view*, plus a resizable *Split*.
  A project with spatial data opens on the map; a table-only project opens on data.
- **GeoLibre menu bar in the top bar** — Project · Edit · View · Add Data · Processing ·
  Controls · Packages · Settings · Help, with hover fly-outs and a tool search box.
  Every analysis is launched from **Processing**; the old per-screen menus are retired.
- **Layers panel** — every dataset and layer in one list, each with a visibility toggle
  and an expandable legend / styling.
- **Tools open in the side panel, results in the centre.** A tool can be floated
  (draggable, resizable) or minimised to the dock; past results park there as chips.
- **R console** is a bottom dock that slides up on demand.
- **Data & Exploration operations are individual menu entries** — pick "Row filtering"
  and only that operation's controls appear.
- **Map:** real layer rendering (rasters + vectors), 14 basemaps, and the view is
  preserved when you switch basemap. The attribute table shows the **active vector
  layer's own attributes**.
- **Charts:** a plot builder with a **Static ⇄ Interactive** toggle (plotly), and a
  draggable split between plot and table.

### Look & feel
- **Six colour sets** (Forest, Light, Midnight, Ocean, Plum, Paper) — instant, remembered.
- **App icon is now a lightbulb**; the app is **emoji-free** (icons only).
- **Fixed the startup dim at the root** — Shiny fades every output while it recomputes;
  now suppressed and replaced with a proper boot screen, shimmer loaders and subtle
  result reveals (CSS only — no animation library).
- **Contrast swept:** 0 low-contrast text in all six themes.

### Assistant
- **Recommend is merged into the Co-Analyst** — one surface: recommend a method, then
  ask it to run the analysis.

### Packages
- **Packages menu** (was "Plugins") with a real CRAN search that tolerates typos, honest
  per-package progress, and immediate loading — **no restart needed**.

### Fixes
- Single click on a project card opens it (pre-rendered clicks were being lost).
- Map zooms to your raster (the fit is applied when the map is built, not via a proxy
  call that could be discarded).
- Uploading a file no longer jumps you to another screen.
- LAS/LAZ: reopening a project no longer runs out of memory.
- Memory: the results store is bounded, the CRAN index is released, and session state is
  cleared on disconnect.

### Distribution
- **`install.sh`** — one-line install for **macOS and Linux** (mirrors `install.ps1`).
- **`landing/`** — public site: landing page with a 3D LiDAR hero, a how-to-use
  walkthrough and full documentation. Self-contained; no CDN.

### Security
- Documented in ARCHITECTURE.md §10: no secrets in the repo, no user data tracked, and
  the only outbound calls are the Co-Analyst (opt-in), CRAN, basemap tiles and satellite
  search. Removed unused PowerShell dialog helpers.

---

## v0.7.15 — 2026-07-22
- **DA plots now show something useful with >1 predictor.** The 1-D decision plots
  (Scatter+Regions/Class Lanes/Class Density) require a single axis; with 2+ predictors they
  showed "requires exactly 1 numeric predictor". Now they **fall back to the 2-D PCA/LD
  projection** (points by class + predicted-class ellipses) so a plot renders whatever's
  selected. (TODO next: true filled decision-boundary regions in the 2-D PCA plane — needs a
  grid-predict that also handles the PCA-decorrelated LLDA model.)
- **Download hardening.** The `ea-download` blob save now runs against the top document when
  possible, to escape iframe download restrictions (CSV/TSV export).

## v0.7.14 — 2026-07-22
- **Fix: CSV/TSV export wasn't downloading in the browser build.** The standard Shiny
  `downloadHandler` doesn't reliably trigger a file download under webR. Replaced it with a
  message-based download — R builds the file text and sends it to the browser, where a small
  JS handler saves it as a Blob. Multi-format (CSV / TSV) + optional filename preserved.
  (Same webR limitation likely affects the hover plot-PNG download — a follow-up.)

## v0.7.13 — 2026-07-22
- **LLDA now works with multiple correlated predictors.** `klaR::loclda` inverts a *local*
  covariance; with >1 collinear predictor (e.g. two diameter columns) that's singular
  (`dgesv: system is exactly singular`), so the fit died before any plot. Now, on that
  failure the numeric predictors are **decorrelated via PCA** (orthogonal → never collinear)
  and loclda is refit on the components — labelled "Locally Linear DA (PCA-decorrelated)".
  Multi-predictor LLDA plots (the PCA-projection scatter) now render because the fit succeeds.
  (A 3D rotating scatter is the next increment.)

## v0.7.12 — 2026-07-21
- **Fix: the Rows overview tile showed a blank icon** — `icon("rows")` isn't a real FontAwesome
  name; swapped for a valid one.

## v0.7.11 — 2026-07-21
- **Fix: a deleted dataset reappeared in the left data rail.** The list now explicitly drops
  any pool entry whose value is NULL — in this webR build `pool[[key]] <- NULL` can leave the
  name behind, so the deleted dataset kept showing. Now it stays gone.
- **Fix: CSV download on the Dataset Overview could error.** The handler now guards against no
  active dataset / empty data and sanitizes the filename.
- **Clickable overview tiles (drill-down).** Each tile on the Dataset Overview now opens a
  detail modal: **Total NA** → per-column NA counts + a table of the actual rows with missing
  values; Columns → type/missing/unique per column; Numeric/Categorical → those columns;
  Complete rows → the incomplete rows; Rows → the full table.
- **Multi-format, named export.** The export toolbar now offers **CSV / TSV** and an optional
  **file name** (defaults to the dataset name). TSV opens directly in Excel; native `.xlsx`
  export is a follow-up (the `writexl` wasm bundle needs sorting — shinylive skipped it).

## v0.7.10 — 2026-07-21
- **Added the EasyAnalysis favicon** (the EA app icon). Center-cropped to a square PNG,
  copied into the site root as `favicon.png` + `favicon.ico`, and linked from the page
  `<head>` (also stops the `/favicon.ico` 404 in the console).
- **First-boot UX (the "doesn't work on new browsers" report).** Confirmed by watching a
  *fresh, uncached* browser boot the deployed site end-to-end: v0.7.9 boots fine — it just
  takes ~5–8 min the first time (downloading the R environment). The problem was the splash's
  **safety timeout removing the splash after only 8 min**, so a slower first boot got cut off
  and looked like "loads forever then ends". Raised the timeout to **20 min**, and the splash
  note now says "3–8 minutes (longer on a slow connection) … keep this tab open." The splash
  still fades immediately once the app is actually ready (`ea-app-ready`).

## v0.7.9 — 2026-07-20
- **Critical fix: the app was stuck on the splash and never booted** (regression from v0.7.7).
  `mod_docs.R`'s `.doc_b()` helper took a single argument but was called with two in the
  Documentation overview, throwing "unused argument" *while building the UI* — so the app never
  rendered and the splash never received its ready signal. `.doc_b()` now accepts `...`.
  (Parse-checks pass on this kind of bug; the full `source(global/ui/server)` build check is now
  the gate before every push.)

## v0.7.8 — 2026-07-19
- **Splash: removed the sliding light-sweep** (and leftover progress-bar CSS) — no sliding
  bar element on the splash at all now; the globe/satellite/radar/bars motion stays.
- **Co-Pilot: Enter now reliably sends.** The old handler clicked the send button, which could
  fire before Shiny had synced the typed text (sending stale/empty). Enter now passes the
  input's current value straight to the server (`input$enter`), race-free.
- **Added `llms.txt`** (llmstxt.org) served at `/llms.txt` — a detailed description of
  EasyAnalysis for LLMs and search: what it is, features, data formats, analyses, privacy,
  tech, and author. Copied into the site on every build by `webapp_export.R`.

## v0.7.7 — 2026-07-19
- **Honest "Running…" progress indicator.** A global pill shows the *elapsed* time
  ("Running… 0:08", counting up) whenever the app is computing for more than half a
  second — no fabricated "time remaining" (we can't know an analysis's duration, so we
  don't pretend to). Driven by Shiny's busy/idle events; works on every screen.
- **Co-Pilot status now reflects the real step.** Instead of a hardcoded "Thinking…",
  the progress message updates to what the agent is actually doing — "Reading your data…",
  "Running a random forest…", "Computing correlations…", etc. — via a status callback
  threaded through the agent's tool loop.
- **New in-app Documentation screen** (`mod_docs.R`): a full user guide — interface,
  loading data, exploring, running analyses, the AI Co-Pilot, R Console, privacy, and a
  Tips/FAQ — reachable from the top menu, with a jump-to-section contents list.

## v0.7.6 — 2026-07-19
- **Redesigned loading splash.** Replaced the plain screen with an animated hero — a
  rotating Earth-observation globe (raster shimmer, meridian wireframe), an orbiting
  satellite, radar pings and rising data bars — over a frosted-glass card with drifting
  aurora depth and a panning data-lattice. SVG line-icons (no emoji) for the four
  highlights: AI Co-Pilot, Recommend, Any data, Fully private. Respects
  `prefers-reduced-motion`.
- Also includes the v0.7.5 fixes below (delete-name fix, About/Acknowledgements split).

## v0.7.5 — 2026-07-19
- **Fix: deleted dataset's name lingered in the left data panel.** Clicking × removed
  the data from the pool but the label stayed, because `reactiveValuesToList()` reliably
  re-fires on key ADDs (uploads appear) but not on key REMOVALs in this webR build. Added
  a `ds_refresh` trigger that the delete handler bumps and `datasets_list` depends on, so
  the list re-renders and the removed name disappears.
- **About / Acknowledgements split.** About now reads "a platform for conducting analyses
  without writing complex code…". Moved "University of Eastern Finland" out of About into
  a new **Acknowledgements** section crediting UEF for code contributions and for data used
  in analyses and testing — EasyAnalysis is an independent build, not a university product.

## v0.7.4 — 2026-07-19
- **Reverted the v0.7.3 boot-load experiment** (it broke booting — see below) and confirmed
  the finding in `webapp/global.R`: compiled ML/stats packages can't link in this
  spatial-heavy browser build, late OR at boot. Fix is a separate lean build.
- Retained: `.ensure_pkg()` retry helper (v0.7.2), Decision Tree `pickerInput` selector,
  and the "3–5 minutes" splash estimate.

## v0.7.3 — 2026-07-19
- **Boot-load the compiled analysis packages that fail on late link (experiment).**
  v0.7.2's retry fixed *R-level* packages (klaR::loclda works), but compiled ones
  loaded lazily still fail to register native routines: rpart `C_rpart not found`,
  xgboost `XGDMatrixCreateFromMat_R not found`, tidyr `bad export type '_ZTINSt3…'`
  (the kmeans cluster-map uses tidyr via factoextra). The proven fix is linking at
  BOOT (as the lidR stack does). Now `webapp/global.R` links **base64enc first**
  (so boot is safe), then **tidyr, rpart, xgboost** — a small measured set; will
  grow once confirmed boot survives the module-link budget in the browser.
- **Decision Tree predictor selector** now uses the `pickerInput` chip/search
  widget (with select-all), matching Random Forest instead of a plain dropdown.

## v0.7.2 — 2026-07-18
- **Fix: bundled optional packages still showed "install package" on first use.**
  The v0.7.1 packages (klaR, kernlab, xgboost, rpart, glmnet, mgcv, survival,
  car, lavaan, tseries, trend, Hmisc, BayesFactor) are bundled and work, but in
  the browser (webR) a compiled package's **first** lazy-load can transiently
  fail ("file could not be read") even though a retry succeeds — proven in-app:
  `klaR::loclda()` fits fine, yet the screen's one-shot `requireNamespace()`
  reported it missing. Replaced every guard with a retrying `.ensure_pkg()`
  helper (helpers.R) that attempts the load up to 8× before giving up, so the
  first-try flake no longer surfaces as a false "install package" message.
- Splash note now reads "3–5 minutes" for the first-visit load estimate.

## v0.7.1 — 2026-07-18
- **Bundle the optional analysis packages into the browser build.** klaR, kernlab,
  xgboost, glmnet, mgcv, survival, rpart, car, lavaan, tseries, trend, Hmisc, and
  BayesFactor are now included, so the Discriminant Analysis (LLDA/RLDA/KDA/MMC),
  GAM, Survival, Decision Tree, SEM, Bayesian, Time Series, XGBoost, and Ridge/Lasso
  screens can load them. Added via `webapp/_deps.R` (shinylive's scanner doesn't
  follow `requireNamespace()` guards, so these were simply never being bundled).
- **Correction to the v0.7.0 "hard budget" note.** The "install package" messages
  were *not* (primarily) a link-budget problem — the packages were never included
  in the build at all. Each has a WebAssembly build on repo.r-wasm.org; they just
  weren't scanned. (heplots/ggord/mda genuinely have no wasm build and still fall
  back to string-indirection.)

## v0.7.0 — 2026-07-18
- **Branded loading screen.** The ~1-3 min first boot now shows an EasyAnalysis
  splash: what the app is, an elapsed timer, a "first visit is slow, then instant"
  note, rotating tips, a privacy line, and an auto-generated **"What's new"** from
  this changelog. Fades out when the app is actually ready (`ea-app-ready` signal).
  Injected by `webapp_export.R` from `splash_template.html`.
- **Random Forest "unexpected input" error fixed** (see below) — RF itself works
  (randomForest attaches at boot).
- **Known limitation (browser build): some optional compiled ML/stats packages
  can't load** — xgboost, glmnet, kernlab, mgcv, survival, rpart, car, klaR.
  Their screens show "install package". Root cause: this webR build has a hard
  budget for how many compiled `.so` can dynamically link before a libc++ symbol
  becomes unavailable; the LiDAR stack already consumes most of it, and preloading
  these pushed past the budget and broke the whole app's boot. Making them work in
  the browser needs a slimmer-boot strategy (future) — for now they run in the
  server build. (Not a regression; they were never working in the browser.)
- **Fix: Random Forest "unexpected input" training error** — column names weren't
  backtick-quoted in the formula, so names with digits/dots/spaces (VMI codes)
  broke parsing. Fixed in RF and the same bug in Decision Tree, SVM, Neural Net,
  and GAM.
- **Co-Pilot: no unsolicited advice, stricter grounding, accurate capabilities.**
  The agent no longer volunteers "best next step" suggestions unless you ask for a
  recommendation; the prompt hardens the no-hallucination rule (only tool outputs
  / context / image); and it's now given the app's real method list, so it stops
  claiming built-in methods (e.g. LLDA) are missing — it points you to the screen
  instead.
- **Fix: deleted-dataset name lingering** in the file-upload widget — cleared on
  delete.

## v0.6.3 — 2026-07-18
- **Browser tab title → "EasyAnalysis"** (shinylive shipped "Shiny App"). Patched
  in `webapp_export.R`.
- **Clip LAS to a shapefile.** New "Clip LAS to this shapefile" button in the LiDAR
  tools — clips the point cloud to the polygon selected in *Plot Shapefile* (from
  an uploaded vector), matching CRS then `lidR::clip_roi`. The manual 4-coordinate
  clip is kept as an alternative.
- **Auto-zoom to spatial data**: already implemented (raster `.zoom_to` on load,
  LAS `fitBounds` on its location map) — the reason it appeared not to work was the
  raster *display* failing, which v0.6.2 fixes. No new code needed; noting it here.

## v0.6.2 — 2026-07-18
- **LiDAR: access the full point cloud.** Read cap raised 500k → 5M (full
  plot-level clouds now load; still a memory safety net for huge files), and the
  "Max display points" slider now reaches the **full loaded cloud** (its max is
  set to the actual point count on upload). Default display stays 60k for a
  responsive 3D viewer.
- **Fix "Install the 'rstac' package".** rstac/exactextractr were bundled in
  v0.6.1 but their `requireNamespace()` guard runs on a button click = LATE, and
  exactextractr is compiled → same late-link ABI bug. Now **preloaded at boot**,
  so the guards pass. (If you still saw the message, you were on the pre-v0.6.1
  deploy.)
- **Raster/TIFF display fix.** `leafem::addGeoRaster` (client-side JS renderer) is
  fragile in the wasm build; added a fallback to `leaflet::addRasterImage`
  (server-side PNG overlay via the now-working cairo device). Display errors,
  previously swallowed silently ("feels like it doesn't load"), are now shown.

## v0.6.1 — 2026-07-18
- **Fix: .laz / .tif uploads failed** with `bad export type for
  '_ZTINSt3__216__owns_one_stateIcEE'`. Root cause: v0.5.0 made `lidR`/`stars`
  lazy-loaded; a heavy C++ .so that links LATE (on first `pkg::` use) fails in
  this webR build — the same failure as the cairo/LAPACK bug. **Reverted:**
  `lidR`, `sf`, `terra`, `stars` are attached at boot again. Heavy C++ packages
  cannot be lazy-loaded here; lazy-loading is off the table as a fast-start
  approach for the spatial stack. (The v0.5.0 change was "verified" in the Node
  harness, which does not reproduce the browser's linking limits — only the
  browser does.)
- **Fix: "Install the 'rstac' package to use satellite search".** `rstac` and
  `exactextractr` (both behind `requireNamespace()` guards, so invisible to the
  shinylive scanner) are now force-bundled via `webapp/_deps.R`. Download Spatial
  Data and zonal stats work in the browser build.
- **About panel**: added a short description of what EasyAnalysis is (runs in your
  browser, your data never leaves your machine).
- **Upload diagnostics**: spatial-file load errors are now persistent and shown in
  full, plus an empty/unreadable-file guard — to pin down the .laz/.tif upload
  issue. (Verified in webR that terra/sf/lidR *can* read TIF/SHP/LAS; the
  remaining variable is the browser upload→filesystem step, so we need the exact
  on-screen error to finish the fix.)

## v0.6.0 — 2026-07-17
- **R Console** (`mod_rconsole.R`) — new "R Console" screen. Run arbitrary R
  directly on your data: the active dataset is `df`, every loaded dataset is
  available by name, assignments persist between runs, and a single evaluation
  captures both printed output and any plot (base or ggplot — no double-eval, so
  RNG/side-effects behave correctly). Click-to-insert examples, Ctrl+Enter to run.
  - Safe in the browser build: each user runs their own sandboxed webR session in
    their own browser on their own data. (Would be arbitrary code execution on a
    shared server; the shipped product is the browser build.)
  - Verified via testServer: text output, persistent state, base+ggplot capture,
    error handling, the lm/LAPACK path, and clear all work.

## v0.5.0 — 2026-07-17
- **Lazy-load the heavy spatial stack.** `lidR`, `stars` (and `rlas` via lidR) are
  no longer attached in `global.R`; they load on first use. Every call to them is
  `pkg::fn()` qualified (audited: zero unqualified call sites across all modules —
  the 13 apparent hits were all CSS/strings/labels), and `::` loads a namespace on
  demand, so this needed no code changes. Sessions that never open a LiDAR/Surface
  screen never fetch them.
  - Bonus: it *reinforces* the v0.2.2 cairo/LAPACK fix — those libs failed when
    linking after the spatial stack, which now isn't loaded at boot at all.
  - **Ceiling:** `sf`/`terra` still load at boot because `leaflet` (needed at UI
    build for 8 `leafletOutput()` calls) imports `sf`. Making those lazy too
    requires deferring the map screens' UI behind `uiOutput()` placeholders.
  - **Constraint:** keep heavy-package calls `pkg::` qualified. An unqualified
    `rast()` would now fail at runtime.
- **Build is now self-healing** (`webapp_export.R`), after a careless
  `cp mod_*.R webapp/` broke two builds:
  - Prunes files `global.R` doesn't source. `mod_gee.R` (rgee/reticulate, no wasm
    build) had poisoned the bundle → "fatal-missing: reticulate".
  - Applies the no-wasm indirection (`ggord`/`heplots` → `.opt_pkg`/`.opt_fun`)
    itself, instead of relying on `webapp/mod_da.R` not being overwritten.
  - Both hard-fail with an explanation if they can't be satisfied.

## v0.4.0 — 2026-07-17
- **Renamed to EasyAnalysis** in the UI: top-bar brand and About monogram
  (`SA` → `EA`). Status bar/About already used `APP_VERSION`.
- **Co-Pilot: fixed the 400 error.** GPT-5 family models (incl. the configured
  `gpt-5.4-nano`) **reject the `temperature` parameter** —
  *"Unsupported value: 'temperature' does not support 0.1 with this model"*.
  `temperature` is now only sent for models that accept it. (The model id itself
  was fine — verified against OpenAI's current model list.)
- **Co-Pilot send UX:** animated typing indicator while the agent works (a turn
  with tool calls + vision can take 10–30s and the panel previously looked dead),
  send button disabled during a turn, double-sends ignored, auto-scroll to the
  newest message.
- **Co-Pilot capabilities:** two new agent tools —
  - `column_stats(dataset, column)` — full numeric summary (quartiles, sd,
    skewness, IQR outliers) or level frequencies, incl. a skew hint suggesting a
    transform.
  - `correlate(dataset, columns, method)` — Pearson/Spearman with the strongest
    pairs ranked first, for "what relates to what" questions.
  Both verified end-to-end, including error paths.

## v0.3.0 — 2026-07-17
- **Run button on every model screen.** All 18 model screens now fit only on an
  explicit click (ANOVA, Logistic, Clustering and Discriminant Analysis were
  still refitting reactively on every input change). This matters most in the
  browser build, where each fit runs on the user's own single-threaded machine —
  a stray dropdown click could previously freeze the tab on a random forest.
  Recorded as UX rule #8 in DESIGN.md. Cheap outputs (descriptive stats,
  distribution plots) stay live.
- **Removed 20 redundant plot-download buttons** (+ their 20 handlers) across 14
  modules. The global hover overlay already injects a PNG button on every plot —
  verified working in the wasm build before removing anything. All 43 CSV /
  raster / GeoJSON downloads are untouched (the overlay can't handle those).

## v0.2.2 — 2026-07-17
**Fix (the real one): blank plots AND "LAPACK routines cannot be loaded".**
- **Root cause:** R links some of its own shared libraries *lazily, on first use* —
  `cairo.so` on the first plot, `libRlapack.so` on the first linear-algebra call.
  In this app that first use happens **after** ~40 packages incl. the heavy C++
  side-modules (terra/sf/lidR/rgl) are loaded, and in the **browser** build that
  late link fails. Two symptoms, one bug: blank plots + dead model summaries.
- **Fix:** `global.R` now touches both at startup — a throwaway PNG device and a
  2×2 `svd()`/`solve()` — **before** `library(lidR)/sf/terra/rgl`. Load order is
  the entire point; keep those probes above the spatial libraries.
- Verified in the browser: plot renders (real PNG), model summaries work, and the
  `cairo`/`bad export type`/`LAPACK` console errors are gone.

> **Correction to v0.2.1:** that entry blamed the terra `R.js` patch. That was
> **wrong** — the patch is fine (Node runs terra + plots with it happily). The
> control experiment that "proved" it changed two variables at once (pristine
> R.js *and* a tiny package set), so it isolated nothing. The surgical patch in
> v0.2.1 is still worth keeping (it is narrower and safer), but it was never the
> cause. Node cannot reproduce this bug at all — only a real browser can.

## v0.2.1 — 2026-07-17
**Fix: all plots rendered blank in the browser build.**
- Root cause: the `R.js` terra/PROJ patch introduced in v0.1.0 was far too broad.
  It rewrote the generic wasm stub factory and threw on *any* unresolved symbol,
  which broke side-module loading — `cairo.so` failed (`bad export type for
  '_ZTINSt3__216__owns_one_stateIcEE'`), R's PNG device never initialised, and
  every `renderPlot` silently produced nothing. It also surfaced as "LAPACK
  routines cannot be loaded" on screens doing linear algebra.
- Proven by a control app: pristine `R.js` + identical pins renders plots fine.
- Fix: patch **only** `resolveSymbol()`, supplying a no-op **only** for genuinely
  unresolved `internal_proj_*` symbols. No throw, nothing else touched.
  (R.js is now +83 bytes vs pristine, was +1969.)
- `webapp_export.R` now writes patched files with `writeBin` — `writeLines` was
  silently converting every LF to CRLF on Windows.
- New `serve_local.R`: serves `webapp_site/` with COOP/COEP headers via
  `httpuv::staticPath`, so local testing is cross-origin isolated (webR uses the
  fast SharedArrayBuffer channel) **and** Range/HEAD still work for webR's lazy
  file loading. Use this instead of `httpuv::runStaticServer` for local testing.

## v0.2.0 — 2026-07-16
- **References screen** — new "References" item in the menubar. Lists the
  published methods implemented in the app (currently Kalliovirta & Tokola 2005),
  each with full citation, the named method(s) derived, where it's used, and a DOI
  link. Single-sourced in `references.R` (`APP_REFERENCES`), kept in sync with
  `papers/METHODS.md`.
- **About panel** refreshed: name → EasyAnalysis, live `APP_VERSION`, tagline
  "A universal scientific analysis platform" (was stale "v0.9.0" / forestry-only).
- **Source now lives in the deploy repo** — a curated `src/` copy of the app
  source was added to the EasyAnalysis repo (not just the compiled site), so it is
  a full project repo.

## v0.1.0 — 2026-07-16
First versioned baseline. The app now exists in two builds from one codebase, with
an AI agent and the first paper-derived methodology implemented.

**Platform**
- **Browser build** via Shinylive/WebAssembly — the whole app runs in each user's
  browser, no R server. Built by `webapp_export.R` (pins shinylive assets 0.10.10 /
  R 4.5 channel, patches the terra PROJ loader, bumps the SW cache, integrity-checks
  the bundle).
- **Deployment**: static site + Vercel serverless AI proxy (`api/chat.js`); the
  OpenAI key lives only in Vercel env, never in the client. Cross-origin isolation
  headers set in `vercel.json`.

**AI Co-Pilot → agent**
- The Co-Pilot now RUNS analyses via OpenAI tool-calling (`agent_tools.R`):
  `list_datasets`, `describe_dataset`, `run_analysis` (descriptive, lm, anova,
  ttest, lme, logistic, rf, clustering, pca), using the app's own fitting functions.
- Dual transport (httr on server, sync-XHR via webR in browser); user-supplied key
  overrides the shared proxy key.

**Analysis features**
- **Dependent-variable transforms** in Linear Regression (log / log1p / sqrt / 1/Y),
  in addition to predictor transforms. Options always visible (nothing hidden).
- **Bias-corrected back-transformation** to the original Y scale — *Kalliovirta &
  Tokola 2005* — with original-scale metrics. Verified numerically.

**Docs**
- ARCHITECTURE.md, DESIGN.md, MEMORY.md, CLAUDE.md rewritten around the
  "universal scientific analysis platform" vision.
- `papers/` folder + `papers/METHODS.md` catalog (paper → named method → status).

**Cataloged papers**
- Kalliovirta & Tokola 2005 — stem diameter & tree age models (bias-corrected
  transformed-Y regression). core methodology implemented.
