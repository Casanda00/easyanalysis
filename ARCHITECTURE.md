# ARCHITECTURE.md — SimpleAnalysis

Technical structure of the app: how the pieces fit, how state flows, and how the
two deployment targets (R server vs. browser/WebAssembly) are produced from one
codebase. Pair this with [DESIGN.md](DESIGN.md) (UX/product) and
[MEMORY.md](MEMORY.md) (decision log & gotchas).

---

## 1. What the app is

A single-page R **Shiny** application that is a **universal scientific analysis
platform**: users upload data of any kind (tabular, raster, LiDAR, vector) and run
~30 tools spanning **statistics, machine learning, deep learning, spatial /
remote-sensing / LiDAR, time-series, survival, Bayesian, and SEM**, plus an **AI
Co-Pilot agent** that runs those analyses on the user's behalf.

Its **founding domain** is Finnish NFI/VMI data (forest trafficability & tree-growth
modeling) — the origin of the app and its sample workflows — but the architecture is
deliberately **domain-general**: the four data pools, the module contract, and the
agent tools are all data-type-driven, not forestry-specific. New capability should be
added as general-purpose analysis, with forestry as one worked example among many.

The same codebase ships two ways:

| Target | Runtime | Where compute happens | Entry |
|--------|---------|-----------------------|-------|
| **Server build** | R + Shiny Server / shinyapps.io / `runApp()` | On the host | root `ui.R`/`server.R`/`global.R` |
| **Browser build** | webR (R compiled to WebAssembly) via **Shinylive** | In each visitor's browser | `webapp_site/` static site |

**Direction (as of 2026-07): the app is LOCAL-FIRST.** The primary — and effectively
the only actively developed — target is the **server build run on the user's own
machine** via the local launcher (`launcher/run.R`: picks a port, runs `runApp()`,
opens the browser). All feature/UI work goes here.

The browser (WebAssembly/Shinylive) build below is **being phased out** — it proved
too slow and limited in testing and did not get good feedback. `webapp/` is a stale
pre-Projects snapshot; do **not** invest in it or "re-sync" changes into it. §6 and
§7 document that pipeline for historical reference only.

---

## 2. Top-level file layout

```
Shiny_app/
├── global.R                # loaded once: libraries, app_theme, source()s every module + helpers
├── ui.R                    # page_fillable CSS-grid shell (.app-shell); one .viewPanel per screen
├── server.R                # shared reactive state + wires each module server once
├── helpers.R               # stateless helpers + plot engines (%||%, show_placeholder, plot_* )
├── evaluation_function.R   # uef_evaluation(pred, obs) -> RMSE/R2/Bias/RelBias/RRMSE
├── agent_tools.R           # AI Co-Pilot agent: tool registry + dispatcher (see §5)
├── mod_*.R                 # one self-contained Shiny module per screen (~35 modules)
│
├── webapp/                 # BROWSER BUILD SOURCE — clean, secrets-free copy of the app
├── webapp_site/            # generated static Shinylive site (git-ignored, ~286 MB)
├── webapp_export.R         # build script: webapp/ -> webapp_site/ with wasm-specific patches
│
├── ARCHITECTURE.md  DESIGN.md  MEMORY.md  CLAUDE.md   # docs
└── *_legacy.R              # pre-rebuild monolith snapshots — NOT sourced; port logic from here
```

### Module count
~35 `mod_*.R` files. Largest: `mod_raster.R` (1409), `mod_data.R` (863),
`mod_recommend.R` (858), `mod_da.R` (802). Total app source ≈ 16k lines.

---

## 3. The application shell (GeoLibre-inspired)

`ui.R` is a `page_fillable` with a CSS-grid `.app-shell`. Five regions:

```
┌─────────────────────────────────────────────────────────┐
│  Top menubar  (.topMenu / .topItem — sets current_view)  │
├──────────┬───────────────────────────────┬──────────────┤
│ Left rail│        Center canvas          │ Right tools  │
│ (.app-   │  navset_hidden(id=canvas_view)│ navset_hidden│
│  left)   │   one .viewPanel per screen   │ (tools_view) │
│ uploads  │                               │ per screen   │
│ dataset  │                               │              │
│ list     │                               │              │
├──────────┴───────────────────────────────┴──────────────┤
│  Status bar (.app-status) — active dataset + dimensions  │
└─────────────────────────────────────────────────────────┘
```

- **Top menubar** — `.topMenu()`/`.topItem()`; each item runs
  `Shiny.setInputValue('current_view', '<view>')`. Groups: Data / Models /
  Machine Learning / Spatial & LiDAR / Spatial Analysis.
- **Left rail** — global `fileInput("upload_files")` (routes by extension, §4.2) +
  clickable `uiOutput("datasets_list")` + New Dataset + View Data.
- **Center canvas** — `navset_hidden(id="canvas_view")`, one `.viewPanel(value)` per screen.
- **Right tools** — `navset_hidden(id="tools_view")`, swapped in lockstep.
- **Status bar** — active dataset name + dimensions.

**View switching:** `server.R` observes `input$current_view` and calls
`nav_select("canvas_view", v)` + `nav_select("tools_view", v)`. All panels exist
at once (hidden); module servers are all bound once at startup. This is
deliberate — hand-rolled tab switching was the original bug (see
[MEMORY.md](MEMORY.md) gotcha #2).

---

## 4. State management

### 4.1 The four pools (owned by `server.R`)
Global state lives in `reactiveValues` pools, passed to modules as arguments
(never globals):

| Pool | Holds | Populated by |
|------|-------|--------------|
| `dataset_pool` | tabular `data.frame`s | tabular uploads, model outputs, extracted metrics |
| `raster_pool`  | `terra::SpatRaster` | `.tif/.img` uploads, raster ops, generated surfaces |
| `las_pool`     | LiDAR `LAS` / `LASheader` | `.las/.laz` uploads (decimated at read time) |
| `vector_pool`  | `sf` objects | `.shp/.gpkg/.geojson` uploads |

Plus: `raw_pool` (pristine upload copies, for "Reset to Upload"), `dataset_names`
(reactive), `active_ds` (reactiveVal set by rail clicks / newest upload),
`active_dataset()` (validated reactive — strips the `tab:` type prefix).

### 4.2 Upload routing
The single left-rail `fileInput` accepts many extensions; `server.R`'s handler
`switch(ext)` routes: tabular → `dataset_pool`, raster → `terra::rast()` →
`raster_pool`, LAS → decimated `readLAS()` → `las_pool`, vector →
`sf::st_read()` → `vector_pool`. Shapefiles are multi-file → written to a
`tempdir()` then read. Each pool item shows a small colour-coded dot per type in the
rail (NO emoji — see DESIGN.md visual language).

### 4.3 Module contract (canvas + tools split)
Every screen exposes THREE things and is wired once:

```r
<name>CanvasUI(id)   # center-canvas content, wrapped in .viewPanel("<view>", ...)
<name>ToolsUI(id)    # right-tools-panel content
<name>Server(id, dataset_pool, active_dataset, ...)   # called once in server.R
```

Namespace everything with `ns()`. Modules read the active dataset via
`active_dataset()` — **never** their own dataset picker (UX rule #10). Predictor
selectors use `selectizeInput(multiple=TRUE)` (rule #11). No per-module plot
download buttons — a global JS hover overlay handles PNG export (rule #12).

### 4.4 The Co-Pilot context bus
Every `mod_*.R` server RETURNS `list(context = <reactive>, plot = <function>)`.
`server.R` collects these into `module_ctx` keyed by view. The Co-Pilot
(`mod_chat.R`) reads the current screen's `context()` (dataset structure + fitted
results as text) and captures its `plot()` to PNG→base64 for vision. This same
bus is what the agent extends (§5).

---

## 5. The AI Co-Pilot agent

The Co-Pilot is an **agent**, not just a describer: it can RUN the app's analyses
via OpenAI tool-calling. Two files:

### 5.1 `agent_tools.R` — tools the model can call
- `.agent_tools_spec()` → the OpenAI `tools` array. Three tools:
  - `list_datasets` — names + dims of loaded datasets.
  - `describe_dataset(dataset)` — columns, types, NA counts, `summary()`.
  - `run_analysis(method, dataset, response, predictors, group, k, ntree)` —
    fits a model. Methods: `descriptive, lm, anova, ttest, lme, logistic, rf,
    clustering, pca`, each using the app's own fitting functions + `uef_evaluation()`.
- `.agent_exec_tool(name, args, dataset_pool)` — the dispatcher. **Never throws**;
  wraps failures as `"ERROR: ..."` strings so the model can self-correct and retry.

### 5.2 `mod_chat.R` — the agent loop + transport + UI
- `.ask_openai_agent(context, history, user_msg, key, dataset_pool, image_b64)` —
  runs up to 6 rounds: send messages + tools → if the model returns `tool_calls`,
  execute each against `dataset_pool`, append `role:"tool"` results, loop; stop on
  a plain-text answer. Returns `list(text, actions)`; `actions` is the trace shown
  under each answer (`[gear icon] ran run_analysis(...)`).
- `.http_post_json(url, bearer, body)` — **dual-mode transport**:
  - Server: `httr::POST` (libcurl).
  - Browser (`.is_wasm()`): synchronous `XMLHttpRequest` executed via
    `webr::eval_js()` in the webR worker (sync XHR is allowed in workers).
    Verified headlessly: `eval_js` exists and a sync XHR reaches external HTTPS.
- **API key**: no `.Renviron` in the browser, so the key is user-supplied via a
  `passwordInput` (gear icon), stored in a session `reactiveVal`, and falls back
  to `OPENAI_API_KEY` on a server. See §7 for hosting-time key options.
- `.CHAT_MODEL` must be **vision- AND tool-calling-capable**.

---

## 6. The browser (WebAssembly) build pipeline

`webapp_export.R` turns `webapp/` into `webapp_site/`. It is the single source of
truth for the build and encodes every hard-won constraint:

1. **Pin Shinylive assets to `0.10.10`** (`SHINYLIVE_ASSETS_VERSION`). Newer
   assets use webR 0.6 / the R 4.6 wasm channel, which lacks `rlas`/`deSolve`
   binaries and breaks lidR.
2. **Patch `WEBR_R_VERSION` to `4.5.0`** in-session — the shinylive R package
   hardcodes the package-download channel independently of the asset version.
3. **Wipe `webapp_site/` first** — the exporter reuses files already present,
   including truncated ones from interrupted downloads (this shipped a corrupt
   `mgcv` once).
4. `shinylive::export("webapp", "webapp_site")` — bundles ~193 wasm packages.
5. **Patch `webapp_site/shinylive/webr/R.js`** — the official `terra.so`
   imports 7 PROJ symbols renamed `internal_proj_*` that no shipped library
   exports, so `library(terra)` (and lidR, which imports it) dies with
   *"resolved is not a function"*. The patch supplies `()=>0` no-ops for exactly
   those symbols; real projection runs through GDAL's statically-linked PROJ
   inside `terra.so` (verified: `terra::project()` works).
6. **Bump the service-worker cache version** — so returning visitors never run a
   stale runtime from browser cache.
7. **Integrity check** — every bundled `.tgz` must be a valid gzip; report
   `BUILD OK` / `BUILD BAD`. `deSolve`/`quadprog` are known-missing (only the
   Bayesian/tseries methods degrade; boot is unaffected).

**Package coverage:** all 40+ hard dependencies have wasm builds, including lidR,
terra, sf, rgl, xgboost. Optional packages with no wasm build (`ggord`,
`heplots`) are accessed via string indirection (`.opt_pkg()`/`.opt_fun()` in
`webapp/helpers.R`) so the dependency scanner skips them.

**Serve/test locally:**
```sh
"C:/Program Files/R/R-4.5.3/bin/Rscript.exe" -e "httpuv::runStaticServer('webapp_site', port=8899)"
```

**Headless debugging:** Node + the `webr` npm package (`--ignore-scripts`, plus
`ws`) mounts `webapp/` and runs the exact browser boot with readable errors —
this is THE tool for wasm package issues, not the browser. See
`fullboot.js`-style harnesses in scratch.

---

## 7. Hosting the browser build

`webapp_site/` is **pure static files** (HTML/JS/wasm/tgz) — no R server, no
backend. Current build: **286 MB, 378 files**, largest file 17.9 MB. Those three
numbers decide which hosts work. It needs HTTPS; cross-origin isolation is handled
by Shinylive's own service worker (the same reason it runs under a plain
`httpuv::runStaticServer` locally), so no special header config is required.

| Host | Free-tier fit for 286 MB | Notes |
|------|--------------------------|-------|
| **Cloudflare Pages** | ✅ (25 MB/file, 20k files, **unlimited bandwidth**) | Best free option for the heavy static site. |
| **GitHub Pages** | ✅ (100 MB/file, 1 GB site, 100 GB/mo bw ≈ 350 cold loads) | Free; fine for modest audiences. |
| **Netlify** | ✅ (100 GB/mo bw) | Free tier OK; watch bandwidth. |
| **Vercel** | ❌ on Hobby (**100 MB static-upload cap** < 286 MB); ✅ on **Pro** (1 GB cap, 1 TB bw, ~$20/mo) | Verified 2026-07 at vercel.com/docs/limits. File-count fine (378 ≪ 15,000). |
| **S3 + CloudFront** | ✅ pay-per-use | Scales infinitely. |

### If you want Vercel
Vercel's free (Hobby) tier caps a deployment at **100 MB of static files**, and
this build is **286 MB**, so the pure-static site does not fit on the free tier.
Two ways forward:
1. **Vercel Pro (~$20/mo)** — 1 GB cap; hosts the static site *and* an OpenAI
   proxy function (ARCHITECTURE §7 key option 3) in one project. Simplest if paid.
2. **Hybrid (recommended, all free)** — heavy static site on **Cloudflare Pages**
   (free, unlimited bandwidth), and a **tiny Vercel serverless function** as the
   OpenAI key proxy. This uses Vercel for exactly what its free tier is good at (a
   small function well under limits) and Cloudflare for the bulk. The app calls the
   Vercel function URL instead of OpenAI directly; the function holds the key.

### API key at hosting time (three options)
The key is **not hardcoded**. Choose per audience:
1. **User-supplied (current default)** — each user pastes their own key (gear
   icon), stored only in their browser session. Zero cost/risk to you; users need
   their own OpenAI account.
2. **Persisted user key** — same, but save to `localStorage` so it survives
   reloads (small `mod_chat.R` change).
3. **Serverless proxy** — a tiny Cloudflare Worker / Vercel function holds YOUR
   key server-side; the app calls the proxy, not OpenAI directly. Users need no
   key; the key never reaches the client. Best for a public deployment you fund.
   (Add rate-limiting/auth on the proxy.)

---

## 8. Known constraints in the browser build
- **Single-threaded R per tab** — each user has their own webR instance, so no
  cross-user contention, but within a tab a long job blocks the UI.
- **No BayesFactor / tseries methods** — no wasm binaries (`deSolve`/`quadprog`
  missing). The screens load; those specific methods report unavailability.
- **rgee / Earth Engine** — excluded (needs Python + a GEE account; can't run in
  wasm or on shinyapps.io). `mod_gee.R` exists but is un-wired.
- **First load ~286 MB** — one-time; the service worker caches it for repeat visits.
- **rgl 3D** — interactive WebGL widget can't be server-screenshotted; a headless
  `scatterplot3d` static render is the AI-visible fallback.

---

## 9. Memory management

The app holds uploaded data in four in-RAM `reactiveValues` pools (§4.1). Because it
runs **locally** and is meant to let users work with **large files**, memory is actively
managed rather than left to grow unbounded — while still defaulting to "use your own RAM,
big files welcome" (management protects against runaway growth; it does not artificially
cap what fits).

### Done (v0.7.x)
- **Lifecycle `gc()`** — deleting a dataset (`input$delete_dataset`), closing/opening a
  project (`.clear_pools`), and disconnecting a session (`session$onSessionEnded`) all
  null the freed objects and call `gc(FALSE)`. Caveat: on **Windows the process RSS often
  does not shrink back to the OS** even after `gc()` — the memory is reusable by R, just
  not returned. This is an R/OS limitation, not a leak.
- **Memory meter** — the status bar shows the total in-RAM footprint of all loaded data
  (`sum(object.size)` across the four pools, `output$status_memory`), recomputed whenever
  a pool changes. **terra rasters are disk-backed**, so they read as small here — correct,
  they are not held in RAM.
- **Bounded, guarded LAS read** — `readLAS` decimates at read above a 5 M-point cap, and
  the read is fully guarded: a corrupt / unsupported / oversized `.laz` returns a clear
  error, never a process crash.

### Roadmap (not built — see MEMORY undone list)
- **Adaptive LAS cap** — size the point cap to *available* RAM instead of a fixed 5 M.
- **`LAScatalog` for large point clouds** — lidR's disk-backed catalog processes tiles
  chunk-by-chunk without holding the whole cloud in RAM. The proper LiDAR path.
- **Budget + LRU eviction over the pools** — the pools are effectively a **cache over the
  on-disk project** (every table is in `datasets.rds`; spatial layers are path
  references). So a memory budget can spill the least-recently-used items and lazy-reload
  them from the project on next access.

### How this is usually done (reference)
Standard approaches for R apps with heavy data: (1) explicit `rm()` + `gc()` on object
lifecycle and session end; (2) out-of-core / disk-backed objects (terra rasters,
`LAScatalog`, arrow/duckdb for huge tables) so the whole thing is never in RAM; (3) a
memory budget with **LRU eviction** (spill least-recently-used to disk, reload on demand);
(4) a visible memory meter; (5) restarting the process as the nuclear reset.

---

## 10. Security & data privacy (swept 2026-07-27)

**Posture: local-first. Your data stays on your machine unless you explicitly send it.**

| Check | Result |
|---|---|
| Hardcoded secrets in app code | none |
| `.Renviron` / secrets tracked by git | no (git-ignored) |
| User data files tracked by git | 0 |
| Where data can leave the machine | only the cases below |

**The only outbound calls, and when they happen**
- `api.openai.com` — **only** when you use the Co-Analyst. It sends the current screen's
  context text **and a PNG of the current plot**. The key is yours (gear icon, session-only)
  or `OPENAI_API_KEY`; it is never hardcoded. If you never open the Co-Analyst, nothing is sent.
- `cloud.r-project.org` / `cran.r-project.org` — package search/install (Packages menu).
- STAC / satellite endpoints (`earth-search.aws.element84.com`, Copernicus, NASA CMR) — only
  when you search or download satellite data.
- `doi.org`, `cs.uef.fi`, `r-spatial.github.io` — static reference links in the References screen.

**Code-execution surfaces (intentional, local-only)**
- `mod_rconsole.R` — the R console runs the user's own code on their own machine (that is the
  feature). It is not exposed to anyone else; the app binds to `127.0.0.1`.
- `mod_raster.R` band calculator — `eval(parse())` of a user-typed band formula.
- The abandoned `.ps_*` / `.native_*` PowerShell dialog helpers were **removed** (unused, and
  shelling out to PowerShell was a needless execution surface).

**If this is ever hosted for multiple users**, revisit: the R console and band-calc `eval`
become remote code execution, and the project store is a shared filesystem path.
