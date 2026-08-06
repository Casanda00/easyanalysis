# DOCS.md — Repository document index

**The single map to every document in this repo.** Start here (especially at the start of
a new session or after a context reset) to find where everything lives.

**Read order for a new session:** [CLAUDE.md](CLAUDE.md) → [ARCHITECTURE.md](ARCHITECTURE.md)
→ [DESIGN.md](DESIGN.md) → [MEMORY.md](MEMORY.md).

## Core working docs
| Doc | What it is |
|-----|------------|
| [CLAUDE.md](CLAUDE.md) | **Read first.** Anchor context + working rules, run/build commands, file layout, the hard-won gotchas that OVERRIDE default behaviour. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Technical structure: the persistent shell, the four typed data pools, the module contract, the Co-Analyst agent, and **§9 Memory management**. |
| **Two registries** | Operations are **data**, not modules. `algorithms.R` + `mod_algo.R` = one spec per **spatial operation** (33 entries). `statistics.R` + `mod_stat.R` = one spec per **statistical method**, declaring its variable roles. Adding either is a list entry — do NOT write a module for something that fits a spec. |
| [DESIGN.md](DESIGN.md) | Product & UX: audience, the GeoLibre north star, the **menu-free project → workspace flow**, the non-negotiable UX rules, Co-Analyst UX, visual language (no emojis). |
| [MEMORY.md](MEMORY.md) | Decision log, project timeline, and hard-won gotchas (quotes-in-`HTML()`, LAS/CRS traps, etc.). Human-facing — distinct from Claude's private per-session memory. |
| [BACKLOG.md](BACKLOG.md) | **THE list of open items from testing, in rounds — read before starting any work.** Each entry keeps the reporter's wording, the diagnosis and how the fix was verified, so a wrong early guess stays visible rather than being quietly overwritten. **Round 1** (13) done. **Round 2** (26) grouped by theme — 15 closed, 11 open (console C10-C13, model screens E19-E22, data B4/B7, chrome F24/F25). **Round 3** (16, numbering skips 6) — 5 closed. **Round 4** (items 18-36, from 2026-08-04; item 33's registry is **built** and all 9 spec-able screens are **migrated onto it**, which found 10 pre-existing faults — see item 33's migration log, and item 36 for the follow-up `tryCatch` sweep) — the `plotly` fresh-install crash, the global "Running…" pill and `color-scheme` are **done**; still open are Steps/Checkpoints, DA methods, data editing, auto-updating release notes, a black & white theme, the code-editor/RStudio menu, the Co-Analyst + multi-tool docking group (27-30), multi-language sync (31), 5-step undo (32), broader statistics + a possible `statistics.R` registry (33), a detailed GLMM (34), and one unresolved fragment to ask about (35). **Round 5** is a reconciliation table mapping a re-sent batch onto existing entries — use it before re-triaging anything. Also records that **voice input is ruled out**, and ends with a suggested order. **Round 6** (items 37-46, from 2026-08-05) is **GIS parity** — layer on/off (**already built**; the real ask was a **basemap** toggle, now done), delete features from the attribute table, symbology (a re-request of round-3 item 11, not new), and click-to-identify, all framed as "like arc and qgis". 38 and 40 are two directions of **one** missing primitive (a selection model linking feature ↔ attribute row) and the entry records the build order. Also: a global plot viewer (slider / RStudio-style zoom / dimensions); **item 41** data-source connectors (confirmed as databases/WMS/WFS/URL, *not* the file upload that exists — credentials-in-cleartext must be decided first); item 45 (theme in Settings, **done**); and **item 46, launching without a terminal** — the installer creates **no shortcut**, so the terminal is currently needed on *every* launch, not just the first. **26a** names the code-editor menu **"Write code"** in the top menu. Item 42 is not a task but the question of whether the platform has met its founding goal of analysing and mapping in one place — and the reporter has ruled that **the GIS side is fixed first, before that integration work starts**. |
| [UNIFIED_WORKSPACE.md](UNIFIED_WORKSPACE.md) | **Build spec for the one-workspace rebuild, and the record of every fix made in it** — including the `.ea-pop` reusable hover panel, the plot-appearance mechanism, R console write-back, the Co-Analyst driving the real screens, and the empty-selector fix — the two views (Map view + Data view), tool-as-panel contract, and the staged build plan. Read before building the unified workspace. |
| [DEPLOY.md](DEPLOY.md) | **Hosting**: the two Vercel projects, why there is no app zip, and how to verify a deploy. |

## User-facing docs on the website (deployed, not just in the repo)
These are **published pages**, so they are the docs actual users read — keep them in step
with the app. Deployed from `landing/` to **easyanalysis.dev** (see [DEPLOY.md](DEPLOY.md)).

| Page | What it is |
|------|------------|
| [landing/index.html](landing/index.html) | The landing page — what the app is, why, and the install one-liners. Nav links to the two pages below. |
| [landing/documentation.html](landing/documentation.html) | **Getting started** (URL still `/documentation` — deliberately unchanged, since the app's Docs button, llms.txt, the sitemap and the README all point at it). Install, workspace, menus, formats, projects, privacy, troubleshooting, citing. |
| [landing/reference.html](landing/reference.html) | **Method reference — GENERATED, do not hand-edit.** Built from the `statistics.R` / `algorithms.R` registries by `tools/build-reference.R`. States the R function each method actually calls, extracted by deparsing the spec's `fit()`/`run()`, so it cannot drift from the code. Hand-written notes live in `REFERENCE_NOTES` inside that script. **Not yet run in CI** (needs the full R app loaded) — rerun it after adding or changing a registry entry. |
| [landing/how-to-use.html](landing/how-to-use.html) | **Practical walkthrough** — the task-oriented companion to the reference. |
| [landing/release-notes.html](landing/release-notes.html) | **Published release notes — GENERATED, do not hand-edit.** Built from `CHANGELOG.md` by `landing/build-release-notes.mjs` and regenerated automatically by `.github/workflows/release-notes.yml` on any push to `main` that touches the changelog. Edit `CHANGELOG.md` instead; the page follows. One anchor per version (`#v0-10-4`). |
| [landing/install.ps1](landing/install.ps1) / [landing/install.sh](landing/install.sh) | Static copies of the installers, served with explicit MIME headers via `landing/vercel.json`. They must stay in sync with the repo-root originals. |
| [landing/llms.txt](landing/llms.txt) | **Machine-readable summary for LLMs / AI assistants** ([llmstxt.org](https://llmstxt.org) convention), served at `/llms.txt`. **This is the only copy** — a repo-root duplicate existed, was never served, and had gone stale describing the deprecated WebAssembly build; it was deleted rather than kept in sync. Keep it current with what the app actually is. |
| [landing/sitemap.xml](landing/sitemap.xml) | The four public URLs, hand-maintained. Uses the **extensionless** form because `vercel.json` sets `cleanUrls` — listing `.html` would point crawlers at a 308. |
| [landing/robots.txt](landing/robots.txt) | Allows everything and points at the sitemap. AI crawlers (GPTBot, ClaudeBot, PerplexityBot, Google-Extended, CCBot, …) are named **explicitly and allowed on purpose** — several ignore `User-agent: *`, and being findable by assistants is the goal. |

**Previously-recorded gaps, all now CLOSED (re-verified 2026-08-05):** the app links to these
pages (Docs button), the in-app tour runs **9 steps** (it was 6 when the note said 2 — the note
counted `data-tour` anchors, not steps), and the release-notes page exists and regenerates
itself (item 24).

## Reference docs
| Doc | What it is |
|-----|------------|
| [README.md](README.md) | Public-facing overview of the app + how to launch. |
| [CHANGELOG.md](CHANGELOG.md) | Version history — `## vMAJOR.MINOR.PATCH — date`, newest first, version single-sourced in `global.R` (`APP_VERSION`). **Must be updated as part of finishing work**, not in a batch later: it is the source a future release-notes page publishes from (BACKLOG item 24), and it has already drifted behind the fixes that landed after v0.8.1. |
| [dev_updates.md](dev_updates.md) | Dated developer action log (early history; not actively maintained). |
| [spatial_design_reference.md](spatial_design_reference.md) | Design reference for the spatial / remote-sensing / LiDAR screens (map-centric GeoLibre layout). |
| [papers/METHODS.md](papers/METHODS.md) | Papers-as-methods notes — published methods to implement and auto-cite. |

## Direction (important)
The app is **LOCAL-FIRST.** The **server build run via `launcher/run.R` (port 7788)** is THE
target — all feature/UI work goes there. The **browser / wasm (Shinylive) build is
DEPRECATED / being phased out** — do **not** invest in `webapp/` or re-sync into it. See
[ARCHITECTURE.md](ARCHITECTURE.md) §1 and [MEMORY.md](MEMORY.md) §2.

## Run it
```
& "C:\Program Files\R\R-4.5.3\bin\Rscript.exe" "<app>\launcher\run.R" "<app>"
```
Opens at http://127.0.0.1:7788 (stop any old instance first so the port is free). Build-check
without launching: see the one-liner in [CLAUDE.md](CLAUDE.md).

## Note on memory
Claude Code also keeps a **private, per-session memory store outside this repo** (with its own
`MEMORY.md` index) — that is separate from the human-facing repo docs listed above.
