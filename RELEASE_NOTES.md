# Release notes — EasyAnalysis

**This file is PUBLISHED.** `landing/build-release-notes.mjs` turns it into
[easyanalysis.dev/release-notes](https://easyanalysis.dev/release-notes) on every push to `main`.

Write it for **users**:

- Say what changed *for someone using the app*, in plain language.
- **No internal references** — no `BACKLOG`/`CLAUDE.md`, no gotcha numbers, no item or round
  numbers, no file paths beyond what makes a change understandable.
- **Never quote a reporter's words.** Describe the symptom neutrally instead.

The engineering detail — root causes, the code that changed, which trap it was, what was verified —
goes in **[CHANGELOG.md](CHANGELOG.md)**, which is internal and can be as raw as you like. The
build fails if internal vocabulary reaches this file, so the split is enforced rather than
remembered.

Format: `## vMAJOR.MINOR.PATCH — date`, newest first. Version single-sourced in `global.R`
(`APP_VERSION`).

---

## v0.11.11 — 2026-08-09

### Plugins now has its own menu

It was buried under Analysis → More, where nobody would look for it. It now sits in the top menu
bar next to **Packages**, which is where you would expect to find it.

## v0.11.10 — 2026-08-09

### Enabling a tool now works straight away

Turning on a WhiteboxTools tool used to require reloading the page before you could use it. It
does not any more — enable it and it appears in the tool list immediately, the same way an
installed package is available as soon as it is installed.

## v0.11.9 — 2026-08-09

### New: a Plugins screen

Under **More → Plugins**. EasyAnalysis can now offer tools from other open-source projects,
starting with **WhiteboxTools** and its 484 algorithms for hydrology, terrain, LiDAR and image
processing.

Nothing is switched on for you. You enable WhiteboxTools yourself, and then enable individual
tools one at a time — so the app only carries what you actually use. The screen credits the
people who wrote it: Prof. John Lindsay, with the R package by Qiusheng Wu and Andrew Brown.

**Search finds a tool even before you enable it.** Type what you are looking for, and if it is
not enabled yet you can switch it on right there in the result.

Building the tool list runs in the background, so you can keep working while it does. Start with
**Index the common tools** — 31 tools covering the usual hydrology, terrain and LiDAR workflows —
or index all 484 if you want everything.

One thing to know: after enabling a tool, reload the page to use it.

## v0.11.8 — 2026-08-09

### Groundwork for optional tool packs

Internal plumbing that lets EasyAnalysis offer tools from other open-source projects — starting
with WhiteboxTools and its 484 spatial algorithms — **without slowing the app down**.

Nothing changes for you yet, and nothing is switched on. Tools from an external project will stay
off until you choose to enable them, they will be credited to the people who wrote them, and you
will be able to enable them one at a time. Searching will find a tool even before it is enabled,
so you can turn it on at the moment you need it.

## v0.11.7 — 2026-08-09

### The WhiteboxTools hydrology tools could not run on a new machine

*Fill depressions* and *Flow accumulation* use WhiteboxTools, which comes in two parts: a small
R package, and the WhiteboxTools program itself — a separate download of about 90 MB. The
installer set up the package but never the program, and the app only checked for the package. So
both tools looked available and then failed with a confusing file error.

The installer now downloads the program too, once. If it is still missing — on a restricted
network, say — the tools now say exactly that, and how to fix it, instead of failing obscurely.

## v0.11.6 — 2026-08-09

### Drag layers to reorder them

Grab the handle at the left of any layer row and drag it up or down. The order you set is the
**drawing order on the map** — put a vector outline above a raster, or one raster above another.
Right-click a layer for **Move to top** and **Move to bottom**, which are quicker in a long list.

Your order is saved with the project, so it is still there when you reopen it.

**The layers panel now reads the way every GIS reads: the top row is the top of the map.** It
used to be the other way round — the list was effectively upside down, so vectors appeared at
the bottom of the panel while drawing on top of everything. Nothing looked wrong while the order
was fixed, but it would have meant dragging a layer "up" pushed it down.

**Your existing maps look exactly the same.** Only the panel's reading order changed; nothing
restacks.

The basemap stays pinned at the bottom and cannot be dragged — it is background tiles rather
than one of your layers.

## v0.11.5 — 2026-08-09

### The attribute table now has proper window controls

Reading a wide table in a short strip at the bottom of the map was cramped. The table now has
minimise, maximise and close buttons in its header:

- **Maximise** fills the whole map area, which is the point — a full-size table instead of a
  letterbox.
- **Minimise** collapses it to its header.
- **Close** hides it; *Attribute table* in the map menu brings it back.
- **Drag the header up or down** to set any height in between. The header has always shown a
  resize cursor; now it actually resizes.

Your choice also **stays put**. Previously, collapsing the table and then selecting a layer,
toggling visibility or changing the basemap made it spring back open, because the panel was
rebuilt from scratch each time and forgot its state.

## v0.11.4 — 2026-08-09

### The cross-validation warning now looks like a warning

The message that says part of your data was left out of a cross-validated score was correct,
and sat in the right place — but it was rendered in the same faint style tables use for
ordinary labels. A statement that the number next to it is unreliable read like a footnote.

It now appears as a highlighted chip beside the score, in a colour that adapts to whichever
theme you are using. It still sits next to the number rather than somewhere else on the page,
because that is the only place it will actually be read.

## v0.11.3 — 2026-08-09

### Error messages now stay on screen until you dismiss them

When something failed, the app explained why — and then deleted the explanation a few seconds
later. Almost every error message in the app behaved this way.

Those messages are usually the most useful thing on screen: they name the cause *and* what to
do about it. Losing them meant you were told how to fix the problem and then had it taken away
before you could act.

Error messages now remain until you close them. If the same error happens repeatedly it
updates in place instead of stacking up. Ordinary confirmations ("Raster added to the project")
still fade on their own, since those are meant to be glanced at.

### The Data Quality pop-ups are gone

Selecting a dataset raised a stack of warnings about missing values, duplicate rows and similar
issues — every time, one pop-up per issue. Because they appeared whenever a dataset became
active rather than only when it was first loaded, simply clicking between datasets replayed
warnings you had already read.

They no longer appear. The underlying checks still exist and will return somewhere you can open
when you want them, rather than as an interruption you cannot decline.

## v0.11.2 — 2026-08-08

### Cross-validation accuracy could be reported too high

**If you have recorded a cross-validated accuracy from Logistic Regression or Classification,
please re-run it.** On some datasets the figure shown was optimistic.

Cross-validation splits your data into parts, fits the model several times, and pools the
results. When one of those fits could not be completed, the app used to carry on quietly:

- **Logistic Regression** left those rows out of the pooled result, so the accuracy was
  calculated from less data than the label suggested — but still presented as a full
  cross-validation.
- **Classification** was affected more seriously. It fits one model per class. When a class
  could not be modelled at all, it was still allowed to compete for the prediction, and could
  even win it — so some predictions came from a model that never existed, and those counted
  towards the accuracy as though they were real.

This matters because fits do not fail at random. They fail on the awkward parts of a dataset —
a rare category, an unusual split — which are exactly the cases a model finds hardest. Leaving
them out made results look better than they were.

Now:

- A class that could not be modelled takes no part in the prediction.
- A row that no model could handle is left unscored rather than guessed, and is excluded from
  the accuracy instead of being counted as a mistake.
- **Anything left out is stated next to the number it affects**, for example: *"Incomplete:
  1 of 5 folds could not be fitted, so 18 rows (20% of the data) are NOT included."*
- A clean run shows no such message, so nothing changes when everything fits.

Mixed-effects models already handled this correctly; their wording is now clearer about how
many rows were used.

### Time series: failures now explain themselves

Seasonal decomposition said only "Decomposition failed" — it now shows the reason. The
stationarity test used to print nothing when it could not run, which made a failed test look
like one the screen never offered; it now says it could not be computed.

## v0.11.1 — 2026-08-08

### Fixed — the assistant no longer drops figures without saying so

When the Co-Analyst ran a model for you, any figure it could not compute simply vanished from its
answer. Ask for a mixed-effects model and the R² could be missing with no indication why; ask for
an ANOVA and the post-hoc comparison could be absent as though it had never been requested.

The assistant answers from what the analysis hands it, so a figure that disappeared silently left
it unable to tell you it was missing, let alone why. Those figures now come back with a plain
explanation instead — the model is still reported in full, and the answer states which figure could
not be computed and the reason.

Affects the linear model, ANOVA post-hoc comparisons, mixed-effects models and random forest.

### Changed — the reference page no longer names internal code

The Methods reference described model-quality figures by naming an internal function. It now
describes what is computed, which is the part that is useful. Package functions such as
`MASS::polr()` are still named — those you may need to cite.

## v0.11.0 — 2026-08-08

### Added — analyse a map layer, and put the results back on the map

Until now the analysis side and the map side could not reach each other. A shapefile's attributes
could not be modelled at all without leaving EasyAnalysis, and nothing a model produced could be
shown on the map. Both directions now work.

**Attributes to Table** takes a vector layer and makes its attribute table an ordinary dataset, so
any of the statistical methods can model it.

**Predictions to map layer** does the return trip: after fitting, it adds the fitted values and
residuals to the layer the data came from, as new columns. Colour the layer by one of them in the
Layers panel and you are looking at your model on the map.

Available on robust regression, Poisson, negative binomial, GAM and GLMM.

**About accuracy.** A model normally leaves out rows with missing values, so results do not line up
one-to-one with the features. Rather than assume they do, the link between the data and the layer
is recorded when the attributes are exported and checked again before anything is written:

- results always land on the features they were computed from, and features the model left out are
  marked as having no value rather than being given someone else's;
- if the layer has been edited since the attributes were exported, the write is **refused** with an
  explanation, because attaching results to shifted features would produce a map that looks right
  and is wrong;
- renaming a layer is harmless — the link does not depend on the name;
- existing columns are never overwritten.

## v0.10.27 — 2026-08-06

### Added — raster symbology

Single-band rasters were always drawn the same way: the first band, one fixed colour ramp, the
full range of values and a fixed transparency. All four are now yours to set, in the same place as
the vector symbology — expand the layer in the **Layers** panel.

- **Band** — choose which band to display, instead of always the first.
- **Palette** — five colour ramps, and a **Reverse** option.
- **Stretch** — decide which values the colours cover: the full range, **2–98%**, **5–95%**, or
  limits you type in. This is the one that usually matters. A handful of extreme or no-data pixels
  can drag the full range so far that everything real ends up in the middle of the ramp and the
  image looks flat. Clipping to 2–98% brings it back.
- **Classes** — keep a continuous ramp, or split the values into 3 to 9 bands.
- **Opacity** — see the basemap or another layer underneath.

Settings are kept per layer and saved with the project.

## v0.10.26 — 2026-08-06

### Added — delete features from a layer

You can now remove features from a vector layer. Select the rows you want in the attribute table,
turn on **Edit** in the attribute panel, and press **Delete**.

Editing is off by default and has to be switched on deliberately, so nothing can be removed by a
stray click. The button shows that the layer is editable while it is on, and switching to a
different layer turns it off again.

**Undo edit** reverses the last deletion, up to five steps per layer. Deleting every feature at
once is refused — remove the layer itself if that is what you want.

### Fixed — switching tabs still showed a disconnection after a while

The previous version ignored connection drops for 30 seconds after you left a tab, which was not
long enough: coming back after a few minutes still showed the panel. There is no time limit now. A
drop that happens while you are on another tab is simply held, and only reported if the connection
is genuinely still gone once you are looking at the page again.

## v0.10.25 — 2026-08-06

### Fixed — switching browser tabs no longer looks like a disconnection

Moving to another tab and coming back could show the "connection lost" panel even though nothing
was wrong. Browsers slow down or drop the connection for tabs you are not looking at, and the app
was treating that as a failure.

It now ignores connection drops while a tab is in the background, and waits a moment before
reporting anything — so a brief interruption that recovers on its own passes unnoticed. A genuine
disconnection, such as after the computer sleeps, still reports as before.

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
  now published at **easyanalysis.dev/release-notes**, and regenerated automatically
  whenever a release is added — so the page can never drift behind the app. Each
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
- Internal notes claimed the shared model-quality function was unused. It is in fact used by the
  mixed-effects, random forest and linear regression screens, and now by the method registry too,
  which is what keeps those figures comparable between screens.

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
  and the colour never said anything the word did not.
- **The Co-Analyst no longer offers suggestion chips.** They were the last place the app
  volunteered a next step, which contradicted its own system prompt — that already forbids
  the model from proposing one. The Recommend screen is kept and is where suggestions belong.

### Added
- **Undo now goes back 5 steps, not 1.** `snap()` was already the single choke point every
  data operation passes through, so the change is one bounded stack. Each undo reports how
  many steps remain, so the last press reads as "no further undo steps" rather than a dead
  button. Capped deliberately — each entry is a full copy of the data frame.
- **A "Docs" button in the app.** The documentation pages have been live on the website for
  days, but nothing inside the app pointed at them, so users who never visited the site never
  found them. It sits in the top bar on both the projects screen and the analysis area, and
  opens in a new tab so a running project is never navigated away from.
- **The guided tour covers 9 steps, up from 6** — added the tool search, Undo/Reset, and the
  new Docs link, clearing the "at least 8" requirement.

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
  packages, so `plotly` was the only one exposed.
- **Nothing showed that the app was working.** Only 12 of 42 modules use `withProgress`, so
  on the other 30 — including most model screens — a slow fit looked like a frozen app. Worse,
  `ui.R` deliberately disables Shiny's own dimming (`--shiny-fade-opacity: 1`) on the promise
  of a "Running pill" that had never been built, leaving less feedback than stock Shiny. Added
  the global `#ea-busy` pill: pure CSS keyed off Shiny's `shiny-busy` class, so it needs no
  per-module wiring and works even while R is blocked (a server-rendered spinner cannot).
  Shown only by real request state, never a timer, and only after 400 ms so quick actions do
  not flash it. Also extended the existing skeleton shimmer to the model canvas.
- **Native `<select>` popups and scrollbars ignored the theme.** Page CSS colours the closed
  control but not the browser-drawn popup list. Every colour set now declares
  `scheme = "light"|"dark"` in `theme.R` and `ea_theme_css()` emits a real `color-scheme`
  declaration; `:root` declares it too, since a first-time visitor has no `data-ea-theme`
  attribute yet while the default palette is dark. Added `option` colour rules as the
  Chromium-specific complement.

### Docs
- Checked the state of the guided tour and the links to the documentation, and recorded what
  was actually there rather than what was assumed.

> **A gap in these notes, stated rather than papered over:** work done between v0.8.1 and this
> release — including the custom domain and the rewritten website — was never given a version
> or an entry here. These notes are published from a single file, so writing the entry is now
> part of finishing the work rather than something done afterwards.

## v0.8.1 — 2026-07-29

### Fixed
- **Model screens opened with empty variable selectors.** Linear regression, ANOVA and
  Random forest could not be run at all — by hand or by the Co-Analyst — because the
  workspace renders a module's panel lazily and `updateSelectInput` fired before the
  element existed. `active_dataset()` now depends on `ds_refresh`, bumped when a tool
  opens.
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
  buttons) — Bootstrap's component variables restated from the tokens.
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
- The project's internal documentation was rewritten around the "universal scientific analysis
  platform" goal, and a catalogue of published methods was started — each paper mapped to the
  method it provides and whether that method is implemented yet.

**Cataloged papers**
- Kalliovirta & Tokola 2005 — stem diameter & tree age models (bias-corrected
  transformed-Y regression). core methodology implemented.
