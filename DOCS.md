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
| [DESIGN.md](DESIGN.md) | Product & UX: audience, the GeoLibre north star, the **menu-free project → workspace flow**, the non-negotiable UX rules, Co-Analyst UX, visual language (no emojis). |
| [MEMORY.md](MEMORY.md) | Decision log, project timeline, and hard-won gotchas (quotes-in-`HTML()`, LAS/CRS traps, etc.). Human-facing — distinct from Claude's private per-session memory. |
| [BACKLOG.md](BACKLOG.md) | **THE list of open items from testing, in rounds — read before starting any work.** Each entry keeps the reporter's wording, the diagnosis and how the fix was verified, so a wrong early guess stays visible rather than being quietly overwritten. **Round 1** (13) done. **Round 2** (26) grouped by theme — 15 closed, 11 open (console C10-C13, model screens E19-E22, data B4/B7, chrome F24/F25). **Round 3** (16, numbering skips 6) — 5 closed. **Round 4** (items 18-35, from 2026-08-04) — the `plotly` fresh-install crash, the global "Running…" pill and `color-scheme` are **done**; still open are Steps/Checkpoints, DA methods, data editing, auto-updating release notes, a black & white theme, the code-editor/RStudio menu, the Co-Analyst + multi-tool docking group (27-30), multi-language sync (31), 5-step undo (32), broader statistics + a possible `statistics.R` registry (33), a detailed GLMM (34), and one unresolved fragment to ask about (35). **Round 5** is a reconciliation table mapping a re-sent batch onto existing entries — use it before re-triaging anything. Also records that **voice input is ruled out**, and ends with a suggested order. |
| [UNIFIED_WORKSPACE.md](UNIFIED_WORKSPACE.md) | **Build spec for the one-workspace rebuild, and the record of every fix made in it** — including the `.ea-pop` reusable hover panel, the plot-appearance mechanism, R console write-back, the Co-Analyst driving the real screens, and the empty-selector fix — the two views (Map view + Data view), tool-as-panel contract, and the staged build plan. Read before building the unified workspace. |
| [DEPLOY.md](DEPLOY.md) | **Hosting**: the two Vercel projects, why there is no app zip, and how to verify a deploy. |

## User-facing docs on the website (deployed, not just in the repo)
These are **published pages**, so they are the docs actual users read — keep them in step
with the app. Deployed from `landing/` to **easyanalysis.dev** (see [DEPLOY.md](DEPLOY.md)).

| Page | What it is |
|------|------------|
| [landing/index.html](landing/index.html) | The landing page — what the app is, why, and the install one-liners. Nav links to the two pages below. |
| [landing/documentation.html](landing/documentation.html) | **User documentation.** The detailed reference users are pointed at. |
| [landing/how-to-use.html](landing/how-to-use.html) | **Practical walkthrough** — the task-oriented companion to the reference. |
| [landing/install.ps1](landing/install.ps1) / [landing/install.sh](landing/install.sh) | Static copies of the installers, served with explicit MIME headers via `landing/vercel.json`. They must stay in sync with the repo-root originals. |

**Known gaps (BACKLOG item 17, verified 2026-08-04):** nothing in the *app* links to these
pages, the in-app tour has **2 steps of the 8+** asked for, and there is no release-notes
page yet (BACKLOG item 24).

## Reference docs
| Doc | What it is |
|-----|------------|
| [README.md](README.md) | Public-facing overview of the app + how to launch. |
| [CHANGELOG.md](CHANGELOG.md) | Version history — `## vMAJOR.MINOR.PATCH — date`, newest first, version single-sourced in `global.R` (`APP_VERSION`). **Must be updated as part of finishing work**, not in a batch later: it is the source a future release-notes page publishes from (BACKLOG item 24), and it has already drifted behind the fixes that landed after v0.8.1. |
| [dev_updates.md](dev_updates.md) | Dated developer action log (early history; not actively maintained). |
| [spatial_design_reference.md](spatial_design_reference.md) | Design reference for the spatial / remote-sensing / LiDAR screens (map-centric GeoLibre layout). |
| [papers/METHODS.md](papers/METHODS.md) | Papers-as-methods notes — published methods to implement and auto-cite. |
| [llms.txt](llms.txt) | Machine-readable project summary for LLM tools. |

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
