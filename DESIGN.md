# DESIGN.md — SimpleAnalysis

The product & UX design of the app: who it's for, the design north star, the
layout idiom, the non-negotiable UX rules, and how the AI agent fits the
experience. Pair with [ARCHITECTURE.md](ARCHITECTURE.md) (how it's built) and
[MEMORY.md](MEMORY.md) (why decisions were made).

---

## 1. Audience & intent

**The vision: a universal analysis tool.** Anyone with data — researchers,
students, analysts across *any* field — should be able to run rigorous
statistical, machine-learning, deep-learning, spatial/remote-sensing, time-series,
and other analyses **without writing code**. Breadth of method + ease of use is the
whole point; the tool aspires to be the single place you go to analyse data,
whatever the discipline.

**Founding audience:** forestry / forest-inventory researchers working with Finnish
NFI (VMI) data — that's the origin and the source of the built-in example workflows.
But the design is domain-general on purpose, and a secondary audience
(business/ops/HR/marketing) is already served by the Recommend engine's domain
question templates. When designing, favour method breadth and general applicability
over forestry-specific shortcuts.

**Design intent:** every analysis a practitioner would reach for (LM, LME, ANOVA,
GLM, discriminant analysis, random forest, XGBoost, SVM, neural nets, clustering,
PCA, survival, GAM, SEM, Bayesian, time-series, spatial ops, LiDAR…) available
point-and-click, with **plain-English interpretation** of results and an **AI agent**
that can drive the whole thing on request.

---

## 2. Design north star: GeoLibre

The entire UI is modelled on **GeoLibre** (github.com/opengeos/GeoLibre): a slim
top menubar, a left data rail, a central canvas, right contextual tools, and a
bottom status bar. This is the single persistent frame — screens swap *inside*
it, the frame never reloads. Keep every new screen in this idiom.

Map-centric screens (raster, vector, LiDAR, remote sensing, and the future Earth
Engine screen) follow GeoLibre most literally: a full-bleed leaflet canvas with
left/right panels floating over it.

### Visual language
- **Primary green `#2e7d32`** (forestry), secondary `#4caf50`, on the **bslib
  `zephyr`** preset (Bootstrap 5). Defined once as `app_theme` in `global.R`.
- Rounded cards, soft shadows, generous whitespace.
- **No emojis anywhere in the UI.** Dataset types in the rail are shown with a
  small colour-coded dot (`.ds-item .dot`), not an emoji — tabular / raster /
  LiDAR / vector each get a distinct colour. Use Font Awesome glyphs (`icon()`)
  or coloured markers, never picture emoji, in any new UI.
- The Co-Analyst uses a gradient green header, avatars, suggestion chips.

---

## 3. Layout & interaction model

```
Top menubar   → picks the screen (sets current_view)
Left rail     → picks the DATA (active dataset); global upload lives here
Center canvas → the screen's main output (plot / map / table / 3D)
Right tools   → the screen's controls (accordion of options + Run)
Status bar    → what dataset is active + its dimensions
```

**Two orthogonal selections drive everything:** *which screen* (top menubar) and
*which dataset* (left rail). A screen always operates on the rail's active
dataset. This separation is why modules must not have their own dataset pickers —
it would create a second, conflicting source of truth (UX rule #10).

**All screens exist at once** (hidden) and are wired once at startup; switching a
view just reveals the right canvas + tools pair. No reload, instant switching.

### Menu-free project flow (evolution of the GeoLibre frame)

The GeoLibre menubar is **not shown everywhere**. Getting *into* a project is a
calm, menu-free funnel; the full menubar only appears once you're actually
analysing:

```
Projects (welcome back)   → identity line only (brand + New project). No menubar.
   │  open a project
Overview (a project's home) → identity line only. "Open project" is the one door in.
   │  Open project  (routes by data: spatial → map, table → Data screen)
Workspace (analysis)      → the full green menubar returns: menus + tool search
                            + Undo/Reset. This is the GeoLibre frame proper.
```

Mechanically: the top bar carries a `menufree` class on the `projects` and
`project` views (shipped in the initial markup, toggled by the `ea-view` client
handler). `menufree` drops the green skin to a plain identity line and hides the
analysis menus, the tool search and Undo/Reset. A **tool search** box in the
workspace menubar indexes every menu item (built from the live menu DOM) so the
long combined menus never feel clunky. Rule of thumb for the workspace canvas:
**spatial data → a map view; a plain table → a data-summary view.**

---

## 4. App-wide UX rules (non-negotiable — enforce in every module)

These are load-bearing consistency rules. Breaking one makes the app feel
incoherent or reintroduces a past bug.

1. **No per-module dataset selector.** The active dataset comes from the left
   rail via the `active_dataset` reactive. Use `active_dataset()` directly.
   *Exception:* spatial modules distinguishing pools (e.g. `vector_pool` vs
   `raster_pool`) may show a single source picker labelled by type — never a flat
   list of all datasets.
2. **Predictor/variable selectors use `selectizeInput(multiple=TRUE)`** (tag
   chips). Never `checkboxGroupInput` for predictor selection.
3. **No per-module plot download buttons.** A global JS hover overlay injects a
   PNG download button over every `.shiny-plot-output`. CSV/table/raster
   downloads still need their own `downloadButton` (formats the hover can't handle).
4. **Namespace every id** with `ns()`; pass shared state as arguments, not globals.
5. **Sidebars scroll internally** (`overflow-y:auto; max-height:100%`) so
   expanding an accordion doesn't stretch the page.
6. **Never hand-roll tab switching** — let bslib/Bootstrap 5 do it; a custom
   `.hide()` handler leaves an inline `display:none` Bootstrap can't clear
   (the original freeze bug).
7. **Friendly failures** — singular-matrix fits, non-convergence, empty selections
   return a `show_placeholder()` hint, not a stack trace.
8. **Every model screen fits on an explicit Run button**, never reactively.
   Use `eventReactive(input$run_model, ignoreNULL = FALSE, {...})` (or an
   `observeEvent` + `reactiveVal`), and put the button at the end of the tools
   panel: `actionButton(ns("run_model"), "Run Model", class = "btn-success w-100",
   icon = icon("play"))`. **Why it matters here:** in the browser build every fit
   runs on the *user's own machine, single-threaded* — a stray dropdown click
   must never kick off a random forest and freeze their tab. Cheap, instant
   outputs (descriptive stats, distribution plots) stay live.

---

## 5. The analysis screens (what exists)

Grouped as they appear in the top menubar:

- **Data** — Data & Exploration (ETL toolbox + EDA), Descriptive stats, Tests,
  Recommend (question→method engine).
- **Statistical Models** — Linear Regression, LME, ANOVA, Logistic,
  Discriminant Analysis, PCA, SEM, Bayesian, GAM, Survival, Time Series.
- **Machine Learning** — Random Forest, Classification (one-vs-all), Clustering,
  Decision Tree, Neural Net, SVM, XGBoost.
- **Spatial & LiDAR** — Point Cloud/3D, CHM & ITD, Metric Evaluation, Surface
  Models (DTM/DSM/CHM/nDSM).
- **Spatial Analysis** — Raster Analysis (+ Annotator), Terrain, Hydrology,
  Land Classification, Suitability, Wind, Night-time Lights, Climate Trend,
  Download Spatial Data (STAC), Change Detection, RS Classification.

Each screen: canvas = primary output, tools = accordion of controls. Model
screens surface `uef_evaluation()` metrics (RMSE/R²/Bias/RRMSE) and, increasingly,
plain-English interpretation cards.

---

## 6. The AI Co-Pilot — design

A floating, app-level panel (not a screen). Toggled from a top-bar button.

### From describer to agent
Originally the Co-Pilot could only *describe* the current screen (its context +
a screenshot of the plot). It is now an **agent**: it can *run* analyses.

**Interaction model:**
- Ask about the current screen → it answers from context + the plot image.
- Ask it to *do* something ("fit an LME of height by soil with plot as random
  effect", "which predictors matter most?") → it inspects the dataset, picks a
  method, runs it against the real data, and interprets the numbers.
- Every answer that ran analyses shows a **transparency trace**:
  `[gear icon] ran describe_dataset(...) → run_analysis(method=lme, ...)`. Users always see
  what the agent actually did.

**Trust & honesty by design:**
- The system prompt forbids inventing columns, coefficients, or p-values — the
  agent may only use tool outputs, the on-screen context, and the plot image.
- Tool errors are returned as text so the agent self-corrects rather than
  bluffing.
- Results come from the **same fitting functions the manual screens use**, so an
  agent-run model matches what the user would get by hand.

### Key entry (design of a hard constraint)
In the browser build there's no server to hold a secret, so the user supplies
their own OpenAI key via a gear-icon `passwordInput`. Copy reassures: *"Runs in
your browser — the key stays on your machine and is sent only to OpenAI."* This
is a deliberate honesty/consent surface, not an afterthought. (Hosted
deployments can instead proxy a shared key — see ARCHITECTURE §7.)

---

## 7. Future UX direction

- **Plain-English interpretation on every model screen** — a templated
  "Interpretation" card ("Group A (mean=42.3) is significantly higher than B…").
  Priority: Tests, ANOVA, Linear Regression.
- **Proactive data-quality diagnostics** — on dataset load, auto-scan for missing
  data, duplicates, near-constant columns, high skew, suspected ID columns; surface
  as a collapsed accordion + toast.
- **Business framing** — domain question templates (Operations/HR/Marketing/
  Finance) in the Recommend screen.
- **Agent expansion** — more tools (spatial ops, plots the agent can generate),
  multi-step analysis plans, and letting the agent switch screens / populate
  controls so its work is visible in the normal UI, not just chat.
