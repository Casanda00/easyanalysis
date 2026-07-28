# DEPLOY.md — hosting EasyAnalysis

Two Vercel projects, both from this one repo (`github.com/Casanda00/easyanalysis`).

> `vercel.json` allows **no comment keys** — Vercel's schema rejects `"//"` with
> *"should NOT have additional property `//`"*. That is why the reasoning lives
> here instead of inside the config files.

| Project | URL | Root Directory | Serves |
|---|---|---|---|
| **App** | `easyanalysis.vercel.app` | *(repo root)* | `install.ps1`, `install.sh`; `/` redirects to the landing site |
| **Landing** | `easyanalysis-landing-page.vercel.app` | **`landing`** | the public site (landing, how-to-use, documentation) |

## Vercel dashboard setup

1. Point **both** projects at `Casanda00/easyanalysis`.
2. On the **Landing** project set **Settings → General → Root Directory = `landing`**
   so Vercel reads `landing/vercel.json`.
3. Leave the **App** project's Root Directory empty (repo root) so it reads the
   root `vercel.json`.
4. Redeploy both.

## Why the app project has a build step

`buildCommand` copies the two installers into `public/`, which is the
`outputDirectory`. That keeps these URLs — hardcoded in the installers and on
every page of the site — resolving:

```
https://easyanalysis.vercel.app/install.ps1
https://easyanalysis.vercel.app/install.sh
```

## There is no app zip to host (this was a real bug)

The installers used to download `https://easyanalysis.vercel.app/easyanalysis-app.zip`
and that **404'd for every user**, because nothing ever produced that file.

They now download **GitHub's archive of `main`**:

```
https://github.com/Casanda00/easyanalysis/archive/refs/heads/main.zip
```

It always exists, is always current, and needs no build step or upload. GitHub
nests everything in `easyanalysis-main/`; both installers already locate
`global.R` inside the extracted tree, so nothing else had to change.

**Consequence:** whatever is on `main` is what users install. Don't push a broken
`main`.

## Headers

- `install.sh` is served as `text/x-shellscript`, `install.ps1` as `text/plain`,
  both with a short (5 min) cache so a fix reaches users quickly.
- The old `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` headers
  were removed with the wasm build. Static pages don't need cross-origin
  isolation, and those headers block third-party map tiles.

## Verifying a deploy

```bash
curl -sI https://easyanalysis.vercel.app/install.sh | head -3     # expect 200
curl -sI https://easyanalysis.vercel.app/install.ps1 | head -3    # expect 200
curl -sIL https://github.com/Casanda00/easyanalysis/archive/refs/heads/main.zip | tail -3
```

## macOS: install CRAN binaries, never compile (fixed 2026-07-28)

**Symptom:** first run on a Mac died with `make: *** [classInt.ts] Error 1`, after
downloading `.tar.gz` sources (`lavaan_0.7-2.tar.gz`, ...). classInt is a hard
dependency of `sf`, so the CORE set failed and the app never launched.

**Cause:** `launcher/deps.R` picked `getOption("pkgType")` on non-Windows. On macOS
that is `"both"`, which silently prefers **source** whenever CRAN's source version is
newer than the published binary — so a Mac with no Xcode tools and no gfortran tried
to compile the whole spatial stack. (The `.ts` target in the error is R's parallel
install timestamp file, i.e. proof it was a source build.)

**Fix:** binaries are requested explicitly wherever CRAN publishes them.

- `type = "binary"` on **Windows and macOS**; `"source"` on Linux (CRAN has no Linux
  binaries — the installer now prints the `apt` line for the GDAL/PROJ/GEOS headers).
- `install.packages.compile.from.source = "never"` on those platforms, so R cannot
  quietly fall back to compiling.
- Third pass: anything with no binary for this R version/arch is retried from source,
  and is *allowed* to fail — the report names the package.
- **Presence is not proof it works.** A binary built for a different R build installs
  cleanly and then fails to load, which used to surface as a crash at boot. Core
  packages are now `requireNamespace()`-checked after install and reinstalled from
  source if they do not load. (`rgl.useNULL` is set first — CLAUDE.md gotcha 6.)

CRAN's macOS binaries cover arm64 and x86_64 and bundle their own GDAL/PROJ/GEOS, so
the "no toolchain, no admin" promise now holds on macOS as it already did on Windows.
