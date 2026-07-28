# ==========================================================================
# mod_docs.R  --  in-app Documentation / User Guide (static screen)
# Same static contract as references.R: docsCanvasUI / docsToolsUI, no server.
# Wired in ui.R's two navsets + a "Documentation" menu item; not bound in server.R.
# ==========================================================================

.doc_section <- function(anchor, title, ...) {
  tags$div(id = anchor, style = "scroll-margin-top:12px;margin-bottom:22px;",
    tags$h5(style = "color:#2e7d32;font-weight:700;margin-bottom:8px;", title),
    ...
  )
}
.doc_p <- function(...) tags$p(style = "font-size:13.5px;line-height:1.6;color:#374151;margin:0 0 8px;", ...)
.doc_li <- function(...) tags$li(style = "font-size:13.5px;line-height:1.55;color:#374151;margin-bottom:4px;", ...)
.doc_b  <- function(...) tags$b(style = "color:#1b5e20;", ...)

docsCanvasUI <- function(id) {
  ns <- NS(id)
  tags$div(style = "max-width:900px;margin:0 auto;padding:18px 10px;",
    tags$h4(style = "color:#2e7d32;font-weight:800;", "Documentation"),
    tags$p(style = "color:#6c757d;font-size:13.5px;",
      "A guide to running analyses in EasyAnalysis — no code required. Use the contents",
      "list on the right to jump to a section."),
    tags$hr(),

    .doc_section("doc-overview", "1. What EasyAnalysis is",
      .doc_p("EasyAnalysis is a platform for running ", .doc_b("basic-to-intermediate statistical, ",
        "machine-learning and spatial analysis by clicking, not coding"), ". Upload your data, pick",
        "what you want, and read the results in plain English."),
      .doc_p("It runs ", .doc_b("entirely in your browser"), " (compiled to WebAssembly). ",
        .doc_b("Your data never leaves your computer"), " — nothing is uploaded to a server. The first",
        "visit takes about 3–5 minutes to download the R environment into your browser; after that it",
        "loads instantly from cache.")),

    .doc_section("doc-interface", "2. The interface",
      tags$ul(
        .doc_li(.doc_b("Top menu bar"), " — analysis categories (Data, Statistical Models, Machine",
          "Learning, Spatial & LiDAR, and more), plus R Console, Documentation and References."),
        .doc_li(.doc_b("Left data rail"), " — ", .doc_b("Add Data"), " and ", .doc_b("New Dataset"),
          " buttons, your loaded datasets (click one to make it active), and ", .doc_b("View Data"), "."),
        .doc_li(.doc_b("Center canvas"), " — the active screen (results, plots, maps)."),
        .doc_li(.doc_b("Right tools panel"), " — the controls for the active screen."),
        .doc_li(.doc_b("Status bar"), " — the active dataset and its dimensions."),
        .doc_li(.doc_b("Settings (gear, top-right)"), " — your OpenAI key, About and Acknowledgements."))),

    .doc_section("doc-data", "3. Loading your data",
      tags$ul(
        .doc_li(.doc_b("Add Data"), " — upload ", .doc_b("CSV, Excel (.xlsx), text"), ", or spatial",
          "files: ", .doc_b("GeoTIFF (.tif), LAS/LAZ point clouds, GeoJSON, GeoPackage, Shapefile"),
          " (select all shapefile parts together)."),
        .doc_li(.doc_b("New Dataset"), " — build one from scratch in a spreadsheet grid, or paste",
          "straight from Excel."),
        .doc_li(.doc_b("Make a dataset active"), " — click it in the left rail. Every analysis uses the",
          "active dataset automatically (there is no per-screen dataset picker)."),
        .doc_li(.doc_b("View Data"), " — inspect and edit cells; ", .doc_b("×"), " removes a dataset."))),

    .doc_section("doc-explore", "4. Exploring & preparing data",
      .doc_p(.doc_b("Data & Exploration"), " is your ETL and EDA workbench: clean columns, transform",
        "variables (log / sqrt with bias-corrected back-transform), filter rows, aggregate, rename or",
        "merge levels, and handle missing values — with ", .doc_b("Undo"), " and ",
        .doc_b("Reset to Upload"), " at any time. It also draws quick exploratory plots."),
      .doc_p(.doc_b("Recommend"), " gives a plain-English read on what your data looks like and which",
        "methods suit it, before you model.")),

    .doc_section("doc-analysis", "5. Running an analysis",
      tags$ol(
        .doc_li("Open the screen you want from the top menu."),
        .doc_li("Make sure the right dataset is active (left rail)."),
        .doc_li("Choose the ", .doc_b("response (Y)"), " and ", .doc_b("predictors (X)"),
          " using the dropdown chip selectors."),
        .doc_li("Click ", .doc_b("Run"), ". A ", .doc_b("“Running… m:ss”"),
          " indicator shows elapsed time while it computes (nothing runs until you click)."),
        .doc_li("Read the results: tables, plots (hover a plot to download a PNG), metrics",
          "(RMSE / R² / accuracy where relevant), and a plain-English interpretation.")),
      .doc_p("Available families include ", .doc_b("Statistical models"),
        " (linear regression, ANOVA, mixed-effects, logistic, discriminant analysis, PCA, tests), ",
        .doc_b("Machine learning"), " (random forest, SVM, neural net, decision tree, XGBoost,",
        "classification, clustering), and ", .doc_b("Spatial & LiDAR"),
        " (point clouds, CHM & tree detection, raster, terrain, hydrology), plus time-series,",
        "survival, SEM, Bayesian and GAM screens."),
      .doc_p(style = "font-size:12.5px;color:#8a6d3b;background:#fcf8e3;border-radius:8px;padding:8px 11px;",
        "Note: a few compute-heavy methods are still being enabled in the browser build and may show a",
        "message on their screen. They are being brought online iteratively.")),

    .doc_section("doc-copilot", "6. The Co-Analyst",
      .doc_p("Open the ", .doc_b("Co-Analyst"), " from the top bar. You can ask about the current screen,",
        "ask it to ", .doc_b("run an analysis for you"), ", or ask it to ",
        .doc_b("explain a plot or result"), "."),
      tags$ul(
        .doc_li(.doc_b("Grounded, no hallucination"), " — it uses only your data, the screen context,",
          "and the tool's own methods. It will not invent numbers or column names."),
        .doc_li(.doc_b("It can run directly"), ": descriptive stats, linear regression, ANOVA, t-test,",
          "mixed-effects, logistic, random forest, clustering and PCA. For other methods it points you",
          "to the screen that does them."),
        .doc_li(.doc_b("API key"), " — the hosted app supplies a shared key; you can also paste your own",
          "OpenAI key via the gear icon. Your key is used only in your browser and is never stored on a",
          "server."))),

    .doc_section("doc-console", "7. R Console",
      .doc_p("Run any R code on your data. ", .doc_b("df"), " is the active dataset; other datasets are",
        "available by name. Assignments persist between runs, and base-R or ggplot2 plots render inline.")),

    .doc_section("doc-privacy", "8. Privacy",
      .doc_p("Everything — loading, cleaning, modelling, plotting — happens ", .doc_b("locally in your",
        "browser"), " via WebAssembly. No data is uploaded. Closing the tab clears the session.")),

    .doc_section("doc-faq", "9. Tips & FAQ",
      tags$ul(
        .doc_li(.doc_b("First load is slow (3–5 min)"), " — it downloads the R environment into your",
          "browser once, then loads instantly from cache. After an update, hard-refresh",
          "(Ctrl+Shift+R) to pick up the new version."),
        .doc_li(.doc_b("Large LiDAR files"), " are decimated for display so the viewer stays responsive."),
        .doc_li(.doc_b("Nothing computes until you press Run"), " — so you can set up a screen without",
          "waiting."))),

    tags$hr(),
    tags$p(style = "color:#adb5bd;font-size:11.5px;",
      "EasyAnalysis is an independent project. See the References screen for the published methods it",
      "implements, and Acknowledgements (in Settings) for contributors.")
  )
}

docsToolsUI <- function(id) {
  ns <- NS(id)
  jump <- function(anchor, label)
    tags$a(href = "#", style = "display:block;font-size:12.5px;color:#2e7d32;text-decoration:none;padding:3px 0;",
      onclick = sprintf("document.getElementById('%s').scrollIntoView({behavior:'smooth'});return false;", anchor),
      label)
  tags$div(
    tags$h6(class = "text-uppercase text-muted small", "Contents"),
    jump("doc-overview",  "1. What it is"),
    jump("doc-interface", "2. The interface"),
    jump("doc-data",      "3. Loading data"),
    jump("doc-explore",   "4. Explore & prepare"),
    jump("doc-analysis",  "5. Running an analysis"),
    jump("doc-copilot",   "6. Co-Analyst"),
    jump("doc-console",   "7. R Console"),
    jump("doc-privacy",   "8. Privacy"),
    jump("doc-faq",       "9. Tips & FAQ"),
    tags$hr(),
    tags$p(style = "font-size:12px;color:#adb5bd;",
      "This guide covers the whole app. For the published methods it implements, see References.")
  )
}
