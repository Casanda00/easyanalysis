# MEMORY.md — SimpleAnalysis project memory

The decision log, timeline, and hard-won gotchas — the "why" behind the code that
isn't obvious from reading it. Pair with [ARCHITECTURE.md](ARCHITECTURE.md) (how
it's built) and [DESIGN.md](DESIGN.md) (what it should feel like).

> This is human-facing project documentation. It is distinct from Claude's
> private per-session memory store.

---

## 1. Project timeline / milestones

| Date | Milestone |
|------|-----------|
| — | Legacy monolith app (single-file `ui/server/global`). Preserved as `*_legacy.R`. |
| — | **GeoLibre rebuild** — UI rebuilt as one persistent shell; screens ported to the canvas+tools module contract one at a time. All 14 original screens live. |
| — | **Phase 2** — spatial/remote-sensing expansion (raster, vector, Sentinel/STAC, change detection, RS classification, XGBoost). |
| — | **Phase 3** — data creation, centralized uploads (4 pools), LiDAR crash fixes, Surface Models module, model-metric cards. |
| — | **Phase 4** — rename to SimpleAnalysis, DA decision-boundary plots, accuracy breakdowns, Co-Pilot moved to top bar. |
| 2026-07-09 | **Shinylive PoC** — proved the app can compile to WebAssembly and run in-browser (nlme LME + ggplot fully client-side). |
| 2026-07-10 | **Full browser build boots** — after solving the terra/PROJ wasm bug (see §3). All screens load in-browser. |
| 2026-07-14 | **AI Co-Pilot agent** — Co-Pilot can now run the app's analyses via OpenAI tool-calling; works in the browser build with a user-supplied key. |

---

## 2. Key architectural decisions (and why)

- **DIRECTION UPDATE (2026-07): LOCAL-FIRST.** The app is now built solely for the
  **server build run locally** (via `launcher/run.R`). The **browser (Shinylive/wasm)
  build is being phased out** — too slow and limited, poor tester feedback. The
  browser-build notes in this doc (§2–§3 wasm gotchas, §6/§7 in ARCHITECTURE) are kept
  for historical reference; do **not** invest in `webapp/` or re-sync into it.
- **One codebase, historically two builds.** The server app (root) and the browser app
  (`webapp/` → `webapp_site/`) shared source. The browser build WAS pitched as the
  strategic direction (server-free, compute on each user's machine, sidestepping
  shinyapps.io's ≤1 GB RAM / no-Python / no-WebGL limits) — now superseded by local-first.
- **`webapp/` is a separate, secrets-free copy.** `shinylive::export()` embeds
  *every* file in the app folder into the public site, so the browser build must
  never contain `.Renviron`, data files, or the `do not push/` folder. `webapp/`
  holds only the ~39 files sourced by `global.R`.
- **Distribute, don't tunnel.** An earlier idea (host on one PC, expose via
  Cloudflare Tunnel / Tailscale) was rejected: the user wanted each user's own PC
  to run the compute, not one shared machine. WebAssembly delivers exactly that.
- **Four typed pools, not one dataset list.** `dataset_pool` / `raster_pool` /
  `las_pool` / `vector_pool` keep incompatible object types separate while a
  single upload entry point routes by extension.
- **Modules return a context bus.** Every module returns
  `list(context, plot)` so the Co-Pilot — and now the agent — can see each
  screen's state uniformly. This made the agent a small addition, not a rewrite.
- **The agent reuses the app's own fitting functions.** `agent_tools.R` calls the
  same `nlme::lme`, `randomForest`, `uef_evaluation`, etc. that the manual screens
  use, so agent results are identical to hand-run ones.

---

## 3. Hard-won gotchas (the expensive lessons)

### Browser / Shinylive build

- **There is a hard BUDGET on how many compiled `.so` can dynamically link.**
  (v0.7.0.) The libc++ symbol `_ZTINSt3__216__owns_one_stateIcEE` becomes
  unavailable to side-modules after some number have loaded; past that, further
  compiled `.so` fail with the usual `bad export type` error. The lidR dep tree
  (loaded at boot) already consumes most of the budget. **Preloading the optional
  model packages (xgboost/glmnet/kernlab/mgcv/survival/rpart/car/klaR) on top of
  it pushed past the budget and broke even `base64enc` → the app failed to boot
  entirely** (`Error: object 'app_...' not found`). So you CANNOT simply preload
  every compiled package to dodge the late-link bug — there is a ceiling. Those
  optional ML/stats screens show "install package" in the browser build; making
  them work needs a slimmer boot set or the server build. Keep the model-package
  preload list EMPTY in global.R unless you re-measure the budget. Symptom to
  watch: base64enc (or another small early package) failing = you've over-spent.
- **Heavy C++ packages CANNOT be lazy-loaded in the browser build — attach them
  at boot.** (v0.5.0 regression, fixed v0.6.1.) Making `lidR` lazy to speed up
  first load broke `.laz` uploads: `lidR::readLAS` triggered a LATE load of
  `lidR.so`, which fails to dynamically link once the wasm module table has
  filled — the identical error as cairo/LAPACK:
  `bad export type for '_ZTINSt3__216__owns_one_stateIcEE': undefined`. Any heavy
  C++ side-module (terra/sf/lidR/rgl/stars) must be `library()`'d at boot, while
  the table is still empty. **This kills lazy-loading as a fast-start strategy for
  the spatial stack** — deferring their UI wouldn't help either, since the .so
  would still load late. terra/sf happen to load early via leaflet's imports;
  lidR/stars must be attached explicitly. **I made this mistake by "verifying"
  lazy lidR in the Node harness, which loaded it fine — Node does NOT reproduce
  the browser's dynamic-linking limits. Only the browser is ground truth for
  load-order/linking bugs. This is the THIRD time Node gave a false green.**
- **R's lazily-linked shared libs MUST be pre-loaded in the browser build.**
  (THE plot bug — cost hours.) R links `cairo.so` on the first plot and
  `libRlapack.so` on the first linear-algebra call — *lazily*. In this app that
  happens **after** ~40 packages incl. terra/sf/lidR/rgl are loaded, and in the
  **browser** that late link fails: `Could not load dynamic lib .../cairo.so` +
  `bad export type for '_ZTINSt3__216__owns_one_stateIcEE'` => **every plot blank**,
  and `LAPACK routines cannot be loaded` => **every model summary dead**. Two
  symptoms, one root cause. **Fix:** `global.R` opens a throwaway PNG device and
  runs a 2×2 `svd()`/`solve()` at the top, ABOVE `library(lidR)/sf/terra/rgl`.
  Load order is the whole point — never move those probes below the spatial libs.
- **Node CANNOT reproduce the browser's dynamic-linking limits.** The headless
  webR harness happily loads all 30 packages *then* plots. It is still the best
  tool for package/symbol issues, but for anything resource- or load-order
  related, only a real browser is ground truth.
- **Design control experiments to change ONE variable.** A "control" that used
  pristine R.js *and* a 2-package app "proved" the terra patch broke cairo. It
  proved nothing — the package set was the other variable, and the patch was in
  fact innocent. That wrong conclusion shipped as v0.2.1.
- **Keep the terra R.js patch SURGICAL — patch `resolveSymbol` ONLY** (still the
  right call, just not the plot bug): add a no-op inside `resolveSymbol()` only
  when a symbol is unresolved AND named `internal_proj_*`. No throw, nothing else.
  Sanity check: patched `R.js` ≈ +83 bytes vs pristine, not +2000.
- **Write patched build files with `writeBin`, never `writeLines`** — on Windows
  `writeLines` re-encodes every LF to CRLF, rewriting the whole file.
- **Local testing must be cross-origin isolated — use `serve_local.R`.**
  `httpuv::runStaticServer()` sends no COOP/COEP, so webR drops to its PostMessage
  channel (slow; "nested R REPLs are not available"). `serve_local.R` adds the two
  headers via `httpuv::staticPath` — and it must be `staticPath`, not a hand-rolled
  handler: webR fetches its VFS (fonts, cairo.so, libRlapack.so) lazily with
  Range/HEAD requests, and a naive always-200 handler breaks those loads
  ("Failed to load NotoSans-Regular.ttf").
- **terra "resolved is not a function" (THE big one).** The official `terra.so`
  on repo.r-wasm.org imports 7 PROJ symbols renamed `internal_proj_*` (a GDAL
  `PROJ_RENAME_SYMBOLS` build artifact) that **no shipped wasm library exports**.
  `library(terra)` crashes, and lidR with it (it imports terra) — always right
  after `factoextra` in load order, always with that cryptic message. **Fix:**
  `webapp_export.R` patches `webapp_site/shinylive/webr/R.js` to supply `()=>0`
  no-ops for exactly those symbols. Real projection runs through GDAL's
  statically-linked internal PROJ inside `terra.so` — verified: `terra::project()`
  works. This is NOT a channel/version mismatch; version juggling never fixes it.
- **Pin Shinylive assets to `0.10.10`.** Newer assets (0.10.11+) use webR 0.6 /
  the R 4.6 wasm channel, which lacks `rlas` and `deSolve` binaries → lidR breaks.
- **Also patch `WEBR_R_VERSION` to `4.5.0`.** The shinylive R package hardcodes
  the *package-download* channel separately from the asset version, so pinning
  assets alone isn't enough — runtime and packages must be the same channel.
- **Always wipe `webapp_site/` before export.** The exporter reuses files already
  present, including truncated ones from an interrupted download — this once
  shipped a corrupt `mgcv` that only failed at runtime.
- **Never mix r-universe wasm binaries into an r-wasm.org bundle** — Emscripten
  ABI mismatch, same "resolved is not a function" symptom.
- **Service-worker caching bites hard.** The SW caches `R.js` and the runtime
  under a fixed version key; a stale broken runtime survives even Ctrl+Shift+R.
  `webapp_export.R` now bumps the SW cache version every build so returning
  visitors self-invalidate.
- **Packages with no wasm build** (`ggord`, `heplots`): reference them via string
  indirection (`.opt_pkg()`/`.opt_fun()` in `webapp/helpers.R`) so the dependency
  scanner doesn't try to fetch them and abort the export.
- **`deSolve` / `quadprog` have no 4.5-channel wasm build.** Only the Bayesian
  (BayesFactor→hypergeo→deSolve) and tseries (→quadprog) methods degrade; boot is
  unaffected. `webapp_export.R` treats them as known-missing, not fatal.
- **Debug wasm issues headlessly with Node + `webr`.** `npm i webr ws
  --ignore-scripts`, mount `webapp/`, run the exact boot. Readable errors, no
  browser. On Windows, webr 0.6's worker needs a `pathToFileURL` patch. This is
  the tool that finally cracked the terra bug — the browser only showed a skull.

### Server / general

- **Quotes inside `tags$script`/`tags$style`.** A literal `"` inside an
  R-double-quoted `HTML("...")` silently breaks parsing of the whole file. Use
  single quotes / no quotes in CSS selectors (`a[data-bs-toggle=tab]`).
- **Don't hand-roll tab switching** (see DESIGN rule #6) — bslib does it natively;
  a custom `.hide()` handler leaves an uncleatable inline `display:none`.
- **LME non-convergence** (`iteration limit reached`): scale predictors or use
  `control = lmeControl(opt="optim", msMaxIter=1000)`. The agent's `lme` tool
  already applies this.
- **LiDAR OOM on shinyapps.io:** `readLASheader()` first, compute a sampling
  fraction to cap ~500k points, then `readLAS(filter="-keep_random_fraction X")`.
  Also `options(rgl.useNULL=TRUE)` **before** `library(rgl)`.
- **CRS detection:** `sf::st_crs(las)$epsg` is NULL for many valid CRS objects —
  check `is.na(sf::st_crs(las))`. Avoid `lidR::extent(las)@xmin` (fails on
  `terra::SpatExtent`); use `las@data$X` min/max.

---

## 4. The AI Co-Pilot agent — how it works

- **`agent_tools.R`** — tool registry `.agent_tools_spec()` + dispatcher
  `.agent_exec_tool(name, args, dataset_pool)`. Tools: `list_datasets`,
  `describe_dataset`, `run_analysis` (methods: descriptive, lm, anova, ttest,
  lme, logistic, rf, clustering, pca). The dispatcher **never throws** — it
  returns `"ERROR: ..."` strings so the model retries with corrected arguments.
  Verified end-to-end: all 9 methods + error paths return correct statistics.
- **`mod_chat.R`** — `.ask_openai_agent()` runs the tool loop (≤6 rounds).
  Transport `.http_post_json()` is dual-mode: `httr` on a server, synchronous XHR
  via `webr::eval_js()` in the browser (verified the bridge exists and reaches
  external HTTPS). `.CHAT_MODEL` must be vision- AND tool-calling-capable.
- **API key is NOT hardcoded.** User pastes it (gear icon) → session
  `reactiveVal`; falls back to `OPENAI_API_KEY` env on a server. For a hosted
  public deployment, proxy a shared key through a serverless function instead (see
  ARCHITECTURE §7).

### Divergence risk to watch
`webapp/` is a **hand-synced copy** of the root app. After editing
`agent_tools.R` / `mod_chat.R` / `global.R` in root, re-copy them into `webapp/`
and re-run `webapp_export.R`. Do **not** blanket-copy `helpers.R` / `mod_da.R`
into `webapp/` — those have browser-only `.opt_pkg`/`.opt_fun` edits the root
lacks. A future cleanup could make `webapp_export.R` generate `webapp/` from root
automatically, applying the wasm transforms programmatically.

---

## 5. Environment facts
- R at `C:\Program Files\R\R-4.5.3\bin\Rscript.exe` (R 4.5.3). `Rscript` is not on
  PATH — call the full path. In PowerShell, prefix the quoted path with `&`.
- Key package versions: **bslib 0.10.0**, **shiny 1.13.0** (Bootstrap 5).
- Build check (no launch):
  `Rscript -e "suppressMessages({library(shiny);library(bslib);library(shinyWidgets)}); source('global.R'); source('ui.R'); source('server.R'); cat('OK\n')"`
- Browser build: `Rscript webapp_export.R`, then
  `Rscript -e "httpuv::runStaticServer('webapp_site', port=8899)"`.
