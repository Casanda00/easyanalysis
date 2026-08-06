/* ---------------------------------------------------------------------------
   build-release-notes.mjs  --  RELEASE_NOTES.md  ->  landing/release-notes.html

   Backlog item 24. Approach C of the three that were considered: a GitHub
   Action regenerates this page whenever RELEASE_NOTES.md changes on main, and
   commits the result. The alternative approaches were rejected for reasons
   worth keeping:

     A. a Vercel buildCommand  -> gives up the pure-static deploy that makes the
        installer one-liners work (landing/vercel.json has buildCommand: null).
     B. fetch the raw file from GitHub in the browser -> the page then breaks
        whenever GitHub hiccups, and nobody would notice.

   So the OUTPUT is committed and the site stays static; only the generation
   moves to CI.

   The page is deliberately self-contained: the site's CSP allows no external
   host, so the tokens below are copied from landing/index.html rather than
   linked. They are the same values theme.R uses in the app.

   Usage:  node landing/build-release-notes.mjs
--------------------------------------------------------------------------- */

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { marked } from "marked";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..");

/* RELEASE_NOTES.md is the PUBLIC file. CHANGELOG.md is the internal engineering
   record and is deliberately NOT read here -- it carries root causes, file paths
   and gotcha numbers that mean nothing to a visitor. */
const md = readFileSync(join(repo, "RELEASE_NOTES.md"), "utf8");

/* The file's own preamble (who it is for, the format note) is instruction for
   whoever edits it, not something a user of the app needs. Drop everything
   before the first release heading and write a proper introduction instead. */
const firstRelease = md.search(/^## v/m);
const body = firstRelease > 0 ? md.slice(firstRelease) : md;

/* This page is PUBLIC, so a reporter's verbatim words must never reach it.
   Feedback quotes belong in BACKLOG.md, which is internal. Three of them
   were caught by eye on the way to the site once; a build that fails loudly is
   cheaper than noticing again. Only release bodies are checked -- the preamble
   above is already dropped, and editorial blockquotes that do not open with a
   quotation mark (corrections, "Changelog gap" notes) are legitimate. */
const quoted = body
  .split("\n")
  .map((l, i) => [i, l])
  .filter(([, l]) => /^>\s*["“]/.test(l));
if (quoted.length) {
  console.error(
    "\nERROR: RELEASE_NOTES.md contains verbatim quotes, and this file is published.\n" +
    "Move them to BACKLOG.md and describe the symptom in neutral language instead.\n" +
    quoted.map(([i, l]) => `  line ${i + 1}: ${l.trim()}`).join("\n") + "\n"
  );
  process.exit(1);
}

/* The same boundary, for INTERNAL VOCABULARY rather than quotes.
   BACKLOG.md and CHANGELOG.md are internal; RELEASE_NOTES.md is the published
   one. Cross-references to the internal notes ("BACKLOG item 24",
   "Round 4 (items 18-25)", "CLAUDE.md gotcha 27") had leaked onto the public
   page, where they read as jargon about tickets a reader cannot see — nine
   instances before this check existed. Technical detail belongs in the
   backlog; this file says what changed for someone using the app. */
const jargon = [
  [/\bBACKLOG(\.md)?\b/i,        "BACKLOG reference"],
  [/\bCLAUDE\.md\b/i,            "CLAUDE.md reference"],
  [/\bgotcha \d+/i,              "gotcha number"],
  [/\bround[- ]?\d+ item\b/i,    "round/item reference"],
  [/\bbacklog item \d+/i,        "backlog item number"],
  [/^\s*[-*]?\s*\(?item \d+[.)]/im, "bare item number"],
];
const found = [];
body.split("\n").forEach((l, i) => {
  for (const [re, what] of jargon)
    if (re.test(l)) found.push(`  line ${i + 1} (${what}): ${l.trim().slice(0, 90)}`);
});
if (found.length) {
  console.error(
    "\nERROR: RELEASE_NOTES.md refers to internal notes, and this file is published.\n" +
    "BACKLOG.md is the engineering log and stays private. Describe the change for a\n" +
    "user here, and keep the diagnosis, file paths and gotcha numbers in the backlog.\n" +
    found.join("\n") + "\n"
  );
  process.exit(1);
}

/* Newest version, for the header line. */
const latest = (body.match(/^## (v[\d.]+)/m) || [])[1] || "";
const releaseCount = (body.match(/^## v/gm) || []).length;

marked.setOptions({ gfm: true, breaks: false, headerIds: false, mangle: false });

/* Give every release an anchor so a support answer can point at one version,
   and wrap each release in a <section> so it can be styled as a card. */
let html = marked.parse(body);
html = html.replace(
  /<h2>(v[\d.]+)([^<]*)<\/h2>/g,
  (_m, ver, rest) =>
    `</section><section class="rel" id="${ver.replace(/\./g, "-")}">` +
    `<h2><a class="anchor" href="#${ver.replace(/\./g, "-")}">${ver}</a>` +
    `<span class="when">${rest.replace(/^\s*—\s*/, "")}</span></h2>`
);
html = html.replace(/^<\/section>/, "") + "</section>";

const page = `<!doctype html>
<html lang="en">

<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Release notes — EasyAnalysis</title>
  <meta name="description"
    content="What changed in each version of EasyAnalysis, newest first.">
  <link rel="canonical" href="https://easyanalysis.dev/release-notes">
  <meta name="robots" content="index, follow, max-snippet:-1">
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" href="/favicon.png">
  <link rel="apple-touch-icon" href="/favicon.png">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="EasyAnalysis">
  <meta property="og:url" content="https://easyanalysis.dev/release-notes">
  <meta property="og:title" content="Release notes — EasyAnalysis">
  <meta property="og:description"
    content="What changed in each version of EasyAnalysis, newest first.">
  <meta name="twitter:card" content="summary">
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    "headline": "EasyAnalysis release notes",
    "url": "https://easyanalysis.dev/release-notes",
    "description": "Version history for EasyAnalysis, newest first. Latest release ${latest}.",
    "about": { "@type": "SoftwareApplication", "name": "EasyAnalysis", "url": "https://easyanalysis.dev/" }
  }
  </script>
  <style>
    :root {
      --paper: #0F1310; --panel: #171C17; --sunk: #131813; --tint: #1D2A1E;
      --bar: #1B3A1D; --ink: #E8EDE4; --bark: #93A08C; --line: #2A322A;
      --forest: #5FBF62; --canopy: #7ED481; --onbrand: #08120A;
      --mono: ui-monospace, "Cascadia Code", Consolas, monospace;
      --ui: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      --wrap: 900px;
      color-scheme: dark;
    }
    @media (prefers-color-scheme: light) {
      :root {
        --paper: #F7F8F4; --panel: #FFFFFF; --sunk: #EEF1EA; --tint: #E7F0E7;
        --bar: #2E7D32; --ink: #10150F; --bark: #5C6657; --line: #DCE1D6;
        --forest: #2E7D32; --canopy: #3E9B44; --onbrand: #FFFFFF;
        color-scheme: light;
      }
    }
    * { box-sizing: border-box; }
    body { margin:0; background:var(--paper); color:var(--ink);
           font-family:var(--ui); line-height:1.6; -webkit-font-smoothing:antialiased; }
    .wrap { max-width:var(--wrap); margin:0 auto; padding:0 20px; }
    nav { position:sticky; top:0; z-index:10; background:color-mix(in srgb,var(--paper) 88%,transparent);
          backdrop-filter:blur(10px); border-bottom:1px solid var(--line); }
    nav .wrap { display:flex; align-items:center; gap:18px; height:56px; }
    .brand { font-weight:700; letter-spacing:-.01em; display:flex; align-items:center; gap:9px; }
    .mk { width:24px; height:24px; border-radius:7px; background:var(--forest);
          display:grid; place-items:center; }
    .mk svg { width:13px; height:13px; fill:var(--onbrand); }
    nav a { color:var(--bark); text-decoration:none; font-size:14px; }
    nav a:hover { color:var(--ink); }
    nav .links { margin-left:auto; display:flex; align-items:center; gap:18px; }
    header { padding:52px 0 26px; border-bottom:1px solid var(--line); }
    h1 { margin:0 0 8px; font-size:34px; letter-spacing:-.02em; }
    .lede { color:var(--bark); margin:0; max-width:62ch; }
    .meta { margin-top:14px; font-family:var(--mono); font-size:12.5px; color:var(--bark); }
    .meta b { color:var(--forest); }
    main { padding:8px 0 60px; }
    .rel { border-bottom:1px solid var(--line); padding:26px 0; }
    .rel:last-child { border-bottom:0; }
    .rel h2 { font-size:22px; margin:0 0 4px; display:flex; align-items:baseline;
              gap:12px; flex-wrap:wrap; }
    .rel h2 .anchor { color:var(--forest); text-decoration:none; font-family:var(--mono); }
    .rel h2 .anchor:hover { text-decoration:underline; }
    .rel h2 .when { font-size:13px; color:var(--bark); font-weight:400; }
    .rel h3 { font-size:13px; text-transform:uppercase; letter-spacing:.08em;
              color:var(--bark); margin:20px 0 6px; font-weight:700; }
    .rel h4 { font-size:15px; margin:18px 0 6px; color:var(--ink); }
    .rel ul { margin:0; padding-left:20px; }
    .rel li { margin:7px 0; }
    .rel p { margin:10px 0; }
    code { font-family:var(--mono); font-size:.9em; background:var(--sunk);
           color:var(--canopy); padding:1.5px 5px; border-radius:4px; }
    pre { background:var(--sunk); border:1px solid var(--line); border-radius:8px;
          padding:12px 14px; overflow-x:auto; }
    pre code { background:none; padding:0; color:var(--ink); }
    blockquote { margin:12px 0; padding:10px 14px; border-left:3px solid var(--forest);
                 background:var(--sunk); border-radius:0 8px 8px 0; color:var(--bark); }
    blockquote p { margin:0; }
    a { color:var(--canopy); }
    /* Wide tables scroll inside their own box; the page must never scroll sideways. */
    .tw { overflow-x:auto; margin:12px 0; }
    table { border-collapse:collapse; width:100%; font-size:14px; }
    th, td { border:1px solid var(--line); padding:7px 10px; text-align:left; vertical-align:top; }
    th { background:var(--sunk); font-size:12.5px; text-transform:uppercase;
         letter-spacing:.04em; color:var(--bark); }
    footer { border-top:1px solid var(--line); padding:22px 0 40px; color:var(--bark);
             font-size:13.5px; }
    footer .wrap { display:flex; gap:18px; flex-wrap:wrap; align-items:center; }
    footer a { color:var(--bark); text-decoration:none; }
    footer a:hover { color:var(--ink); }
  </style>
</head>

<body>
  <nav>
    <div class="wrap">
      <a class="brand" href="index.html" style="color:inherit;text-decoration:none;">
        <span class="mk"><svg viewBox="0 0 24 24">
            <path d="M9 21h6v-1H9v1zm3-19a7 7 0 0 0-4 12.7V17a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1v-2.3A7 7 0 0 0 12 2z" />
          </svg></span>
        EasyAnalysis
      </a>
      <span class="links">
        <a href="how-to-use.html">How to use</a>
        <a href="documentation.html">Getting started</a>
        <a href="reference.html">Reference</a>
        <a href="release-notes.html" style="color:var(--ink)">Release notes</a>
      </span>
    </div>
  </nav>

  <header>
    <div class="wrap">
      <h1>Release notes</h1>
      <p class="lede">What changed in each version, newest first. Every entry says what
        was actually fixed and why it mattered — not just that something changed.</p>
      <p class="meta">Latest: <b>${latest}</b> · ${releaseCount} releases ·
        generated from CHANGELOG.md</p>
    </div>
  </header>

  <main>
    <div class="wrap">
${html}
    </div>
  </main>

  <footer>
    <div class="wrap">
      <a href="index.html">Home</a>
      <a href="how-to-use.html">How to use</a>
      <a href="documentation.html">Getting started</a>
      <span style="margin-left:auto">Local-first · your data never leaves your machine.</span>
    </div>
  </footer>
</body>

</html>
`;

/* Wrap tables so a wide one scrolls in its own box rather than the page. */
const final = page.replace(/<table>/g, '<div class="tw"><table>')
                  .replace(/<\/table>/g, "</table></div>");

writeFileSync(join(here, "release-notes.html"), final);
console.log(`release-notes.html written — ${releaseCount} releases, latest ${latest}`);
