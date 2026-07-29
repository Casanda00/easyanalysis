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
| [BACKLOG.md](BACKLOG.md) | **Open items reported after v0.8.1 testing** — 13 items, each with the reporter's own wording, what it implies, and what still has to be decided or verified. Read before starting any of them; several are entangled and two need scoping first. Also records that voice input is ruled out. |
| [UNIFIED_WORKSPACE.md](UNIFIED_WORKSPACE.md) | **Build spec for the one-workspace rebuild, and the record of every fix made in it** — including the `.ea-pop` reusable hover panel, the plot-appearance mechanism, R console write-back, the Co-Analyst driving the real screens, and the empty-selector fix — the two views (Map view + Data view), tool-as-panel contract, and the staged build plan. Read before building the unified workspace. |
| [DEPLOY.md](DEPLOY.md) | **Hosting**: the two Vercel projects, why there is no app zip, and how to verify a deploy. |

## Reference docs
| Doc | What it is |
|-----|------------|
| [README.md](README.md) | Public-facing overview of the app + how to launch. |
| [CHANGELOG.md](CHANGELOG.md) | Version history. |
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
