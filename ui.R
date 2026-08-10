# ==========================================================================
# ui.R  --  GeoLibre-inspired shell
# --------------------------------------------------------------------------
# One persistent frame:
#   - top menubar       : Data / Models / Machine Learning / Spatial + right-side
#                         quick actions (Undo, Reset) and Settings gear
#   - left Datasets rail : upload + clickable list, sets the active dataset
#   - center canvas      : navset_hidden swapped by the menubar (current_view)
#   - right tools panel  : navset_hidden swapped in lockstep with the canvas
#   - bottom status bar  : active dataset + dimensions
#   - settings drawer    : slide-over panel from the right (Ctrl+, or gear icon)
# ==========================================================================

.topMenu <- function(label, items) {
  tags$li(class = "nav-item dropdown",
    tags$a(class = "nav-link dropdown-toggle app-menu", href = "#",
      `data-bs-toggle` = "dropdown", role = "button", label),
    tags$ul(class = "dropdown-menu",
      lapply(items, function(it) {
        tags$li(tags$a(class = "dropdown-item", href = "#",
          onclick = sprintf(
            "Shiny.setInputValue('current_view','%s',{priority:'event'});return false;",
            it[["value"]]),
          it[["label"]]))
      })
    )
  )
}

.topItem <- function(label, value) {
  tags$li(class = "nav-item",
    tags$a(class = "nav-link app-menu", href = "#",
      onclick = sprintf(
        "Shiny.setInputValue('current_view','%s',{priority:'event'});return false;",
        value),
      label))
}

.topFeatured <- function(icon_name, label, value) {
  tags$li(class = "nav-item",
    tags$a(class = "nav-link app-menu rec-featured", href = "#",
      onclick = sprintf(
        "Shiny.setInputValue('current_view','%s',{priority:'event'});return false;",
        value),
      icon(icon_name, style = "font-size:11px;margin-right:5px;"),
      label))
}

.viewPanel <- function(value, ...) nav_panel(title = value, value = value, ...)

.todo <- function(name) div(
  class = "p-5 text-center text-muted",
  h5(name), p("Coming back next — being ported into the new shell.")
)

# Settings panel keyboard shortcut row helper
.kbdRow <- function(keys, desc) {
  tags$div(
    style = paste0(
      "display:flex; align-items:center; justify-content:space-between;",
      " padding:5px 0; border-bottom:1px solid var(--line); font-size:12px;"
    ),
    tags$span(style = "display:flex; align-items:center; gap:3px; flex-shrink:0;",
      lapply(strsplit(keys, "\\+")[[1]], function(k)
        tags$kbd(style = paste0(
          "background: var(--sunk); border:1px solid var(--line); border-radius:3px;",
          " padding:1px 5px; font-size:10px; font-family:monospace; color: var(--bark);"),
          trimws(k)
        )
      )
    ),
    tags$span(style = "color: var(--bark);", desc)
  )
}

# A FUNCTION, not a value: Shiny rebuilds it on every page request, so the
# Projects screen can be pre-rendered with the user's actual projects (see
# projectsCanvasUI). As a static object it would be frozen at app startup.
# NOTE: anything checking the UI must now call ui(NULL), not use `ui` directly.
ui <- function(request) {

# Chrome for the FIRST paint. Projects with nothing in it is a clean welcome
# (no panels at all); once projects exist it becomes a workspace and the tools
# panel returns to show project info.
.n_proj <- tryCatch(length(ea_project_list()), error = function(e) 0L)
.main_class <- paste("app-main view-projects",
                     if (.n_proj == 0L) "projects-empty" else "")

page_fillable(
  theme   = app_theme,
  padding = 0,
  gap     = 0,

  tags$head(
    # Browser tab title. shinylive runs the app in an iframe and sets the parent
    # tab title from the app's own <title> (falling back to "Shiny App"). Set our
    # <title> so shinylive picks it up, AND force the parent tab title directly
    # (same-origin) so it wins even if shinylive re-applies its default.
    tags$title("EasyAnalysis"),
    tags$script(HTML(paste0(
      "(function(){function setT(){try{window.parent.document.title='EasyAnalysis';}catch(e){}}",
      "setT();document.addEventListener('DOMContentLoaded',setT);setInterval(setT,2000);",
      # Tell the loading splash (in the parent shell) that the app UI is up so it
      # can fade out. This script runs only after webR has rendered the ui, so a
      # short delay for layout is enough; also fire on shiny:connected.
      "function ready(){try{window.parent.postMessage('ea-app-ready','*');}catch(e){}}",
      "if(window.jQuery){jQuery(document).on('shiny:connected',ready);}",
      "setTimeout(ready,1200);",
      # Clear the file-upload widget's shown filename after a dataset is deleted.
      "if(window.Shiny){Shiny.addCustomMessageHandler('ea-reset-upload',function(m){",
      "var el=document.getElementById('upload_files'); if(el){el.value='';",
      "var g=el.closest('.shiny-input-container,.input-group,.form-group');",
      "if(g){var t=g.querySelector('input[type=text].form-control'); if(t)t.value='';",
      "var pb=g.querySelector('.progress-bar'); if(pb){pb.style.width='0%';pb.textContent='';}}}});}",
      # Report a file selection the moment it happens. A multi-GB upload takes
      # minutes, during which Shiny shows only a thin progress bar -- and the
      # report was "no failure but i did not see it". Silence is indistinguishable
      # from a hang, so say what was picked, and how big, before the wait starts.
      # DELEGATED on document, NOT getElementById. This script lives in <head>, so
      # it runs BEFORE the body is parsed -- getElementById('upload_files')
      # returned null, `if(fi)` skipped, and the listener never attached. The
      # feedback shipped in v0.11.16 was dead code, which is exactly why a 4 GB
      # upload produced no message at all. Delegation cannot have that bug.
      # Opens the fallback file input when there is no native dialog. Delegated
      # lookup at CALL time, not at script time -- the element may not exist yet.
      "if(window.Shiny){Shiny.addCustomMessageHandler('ea_click_upload',function(){",
      "var el=document.getElementById('upload_files'); if(el)el.click();});}",
      "if(window.Shiny){document.addEventListener('change',function(e){",
      "var el=e.target; if(!el||el.id!=='upload_files') return;",
      "var fs=el.files; if(!fs||!fs.length) return;",
      "var tot=0, nm=[]; for(var i=0;i<fs.length;i++){tot+=fs[i].size; nm.push(fs[i].name);}",
      "Shiny.setInputValue('upload_selected',",
      "{n:fs.length, bytes:tot, names:nm.slice(0,6), t:Date.now()},{priority:'event'});",
      "});}",
      "})();"))),
    # Browser-tab icon. Shiny serves www/ at the app root, so these resolve
    # without any extra resource handler. The app had no favicon at all, so the
    # tab showed the browser's blank-page glyph — the same artwork now used for
    # the Desktop shortcut (launcher/easyanalysis.ico).
    tags$link(rel = "icon", href = "favicon.ico", sizes = "any"),
    tags$link(rel = "icon", type = "image/png", href = "favicon.png"),
    # Design tokens, generated from ea_palette in theme.R — the single source of
    # truth for colour. Never hardcode a hex below; use var(--token).
    tags$style(HTML(ea_css_vars())),
    # Colour sets (Forest / Light / Midnight / Ocean / Plum / Paper). Applied by
    # setting <html data-ea-theme="...">; remembered in localStorage.
    tags$style(HTML(ea_theme_css())),
    tags$script(HTML(paste0(
      "(function(){try{var t=localStorage.getItem('ea-theme');",
      "if(t) document.documentElement.setAttribute('data-ea-theme',t);}catch(e){}",
      # Marks the chosen swatch in Settings. The active theme lives in
      # localStorage / the data-ea-theme attribute, which the SERVER cannot know
      # at render time (ui.R only sets the attribute when localStorage already
      # holds one), so the selected state has to be resolved client-side. The
      # default name is injected from R so it cannot drift from ea_palettes.
      "window.eaMarkTheme=function(){",
      "var cur=document.documentElement.getAttribute('data-ea-theme')||'",
      names(ea_palettes)[1], "';",
      "var g=document.querySelectorAll('.set-theme-sw');",
      "for(var i=0;i<g.length;i++){",
      "g[i].classList.toggle('on', g[i].getAttribute('data-theme-name')===cur);}};",
      "window.eaSetTheme=function(name){try{",
      "document.documentElement.setAttribute('data-ea-theme',name);",
      "localStorage.setItem('ea-theme',name);}catch(e){}",
      "if(window.eaMarkTheme) window.eaMarkTheme();",
      "if(window.Shiny) setTimeout(function(){window.dispatchEvent(new Event('resize'));},60);};",
      "document.addEventListener('DOMContentLoaded',function(){",
      "if(window.eaMarkTheme) window.eaMarkTheme();});",
      "})();"))),

    tags$style(HTML("
    /* ROOT CAUSE of the app 'going dim' while it loads: Shiny's own rule
         .recalculating { opacity: .3; transition: opacity 250ms ease 500ms }
       fades EVERY output while it recomputes, and at startup ~40 modules
       recalculate at once, so the whole page greys out for seconds.
       --shiny-fade-opacity is Shiny's supported knob for this: keep outputs at
       full opacity and give feedback with the boot overlay + Running pill
       instead of dimming the entire UI. */
    :root { --shiny-fade-opacity: 1; }
    .recalculating { opacity: 1 !important; }

    /* ---- Loading + reveal motion (pure CSS; no animation library) ----
       We deliberately did NOT add anime.js/Motion: everything we wanted from
       them here (skeleton loaders, result reveals) is a few CSS keyframes, and
       a JS engine would be weight for no gain. */

    /* RUNNING PILL: the global 'something is happening' signal. Driven purely
       by the `shiny-busy` class Shiny sets on <html> while a request is in
       flight -- no server involvement, because a single-threaded R session that
       is busy computing cannot send anything to animate itself.

       The 400ms transition-delay applies only on the way IN, so a fast
       round-trip never flashes the pill, while hiding stays instant (the delay
       lives on the .shiny-busy rule, so it stops applying the moment the class
       is removed). Net effect: it appears only when something is genuinely
       taking long enough to look broken. */
    #ea-busy {
      position: fixed; left: 14px; bottom: 36px; z-index: 2000;
      display: flex; align-items: center; gap: 8px;
      padding: 7px 13px 7px 11px; border-radius: 999px;
      background: color-mix(in srgb, var(--panel) 92%, transparent);
      border: 1px solid var(--line); color: var(--ink);
      font: 600 12px var(--ui); letter-spacing: .01em;
      box-shadow: 0 6px 22px rgba(0,0,0,.28);
      -webkit-backdrop-filter: blur(10px); backdrop-filter: blur(10px);
      opacity: 0; transform: translateY(4px);
      pointer-events: none;               /* never intercepts a click */
      transition: opacity .18s ease, transform .18s ease;
    }
    html.shiny-busy #ea-busy {
      opacity: 1; transform: none;
      transition: opacity .18s ease .4s, transform .18s ease .4s;
    }
    /* Boot overlay owns the screen during startup; two spinners is noise. */
    #ea-boot:not(.gone) ~ #ea-busy { opacity: 0 !important; }
    .ea-busy-spin {
      width: 12px; height: 12px; border-radius: 50%; flex: 0 0 auto;
      border: 2px solid color-mix(in srgb, var(--forest) 35%, transparent);
      border-top-color: var(--forest);
      animation: eaBusySpin .7s linear infinite;
    }
    @keyframes eaBusySpin { to { transform: rotate(360deg); } }

    /* SKELETON: a recomputing output shimmers instead of dimming, so you can
       see WHERE work is happening now that --shiny-fade-opacity is 1.
       `.ea-wsx-modcanvas` is where the model screens render, so without it the
       30 screens that have no withProgress() showed nothing at all. */
    .ea-wsx-canvas .shiny-plot-output.recalculating,
    .ea-wsx-canvas .shiny-html-output.recalculating,
    .ea-wsx-modcanvas .shiny-plot-output.recalculating,
    .ea-wsx-modcanvas .shiny-html-output.recalculating,
    .ea-wsx-dplot .recalculating {
      position: relative; border-radius: 8px;
      background-image: linear-gradient(100deg,
        transparent 30%, color-mix(in srgb, var(--canopy) 12%, transparent) 50%, transparent 70%);
      background-size: 220% 100%;
      animation: eaShimmer 1.2s ease-in-out infinite;
    }
    @keyframes eaShimmer { 0% { background-position: 120% 0; } 100% { background-position: -40% 0; } }

    /* REVEAL: results (pop-out panels, metric tiles, the centre result view)
       rise in rather than snapping. Short and once — motion should not nag. */
    .ea-wsx-panel, .ea-wsx-modcanvas, .ea-wsx-pmet, .ea-wsx-resulthead {
      animation: eaRise .22s cubic-bezier(.2,.7,.3,1) both;
    }
    @keyframes eaRise { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }

    @media (prefers-reduced-motion: reduce) {
      .ea-wsx-canvas .shiny-plot-output.recalculating,
      .ea-wsx-canvas .shiny-html-output.recalculating,
      .ea-wsx-modcanvas .shiny-plot-output.recalculating,
      .ea-wsx-modcanvas .shiny-html-output.recalculating,
      .ea-wsx-dplot .recalculating { animation: none; }
      .ea-wsx-panel, .ea-wsx-modcanvas, .ea-wsx-pmet, .ea-wsx-resulthead { animation: none; }
      /* The pill still APPEARS -- it is the whole signal. Only the spin stops,
         and the fade becomes instant. */
      .ea-busy-spin { animation: none; }
      #ea-busy { transition: none; transform: none; }
      html.shiny-busy #ea-busy { transition: none; }
    }

    /* ---- Text legibility across ALL colour sets ----
       bslib's theme is generated ONCE from the default (dark) palette, so its
       baked-in body/heading/link colours stay light-tuned and go invisible on
       the light sets. Drive every text colour from the tokens instead, so text
       and background always come from the same system. */
    body, .app-shell, .modal-content, .card, .bslib-card,
    h1, h2, h3, h4, h5, h6, p, label, .form-label, td, th, li, dt, dd {
      color: var(--ink);
    }
    small, .small, .text-muted, .help-block, .form-text { color: var(--bark) !important; }
    a:not(.btn):not(.gm-item):not(.ea-proj-open a) { color: var(--canopy); }
    a:not(.btn):hover { color: var(--forest); }
    .shiny-download-link { color: var(--canopy) !important; }
    /* project cards + chips read from tokens in every set */
    .ea-proj-body .when, .ea-proj-body .chip, .ea-proj-open a.muted { color: var(--bark) !important; }
    .ea-ws-head h3, .ea-firstrun h3 { color: var(--ink) !important; }

    /* ---- Surfaces across ALL colour sets ----
       Same root cause as the block above, one level deeper: bslib bakes the
       DEFAULT (dark) palette into Bootstrap's own component variables, so a
       DT table or an accordion stays near-black on the light sets. Bootstrap
       declares those vars ON the component class, so a :root override never
       reaches them -- each component has to be restated. */
    :root, html[data-ea-theme] {
      --bs-body-bg: var(--paper);
      --bs-body-color: var(--ink);
      --bs-emphasis-color: var(--ink);
      --bs-heading-color: var(--ink);
      --bs-secondary-bg: var(--sunk);
      --bs-tertiary-bg: var(--sunk);
      --bs-secondary-color: var(--bark);
      --bs-tertiary-color: var(--bark);
      --bs-border-color: var(--line);
    }
    .table, table.dataTable {
      --bs-table-bg: transparent;
      --bs-table-color: var(--ink);
      --bs-table-border-color: var(--line);
      --bs-table-accent-bg: transparent;
      --bs-table-striped-bg: rgba(128,128,128,.07);
      --bs-table-striped-color: var(--ink);
      --bs-table-hover-bg: rgba(128,128,128,.14);
      --bs-table-hover-color: var(--ink);
      color: var(--ink);
    }
    table.dataTable th, table.dataTable td,
    .table > :not(caption) > * > * {
      background-color: transparent; color: var(--ink); border-color: var(--line);
    }
    /* A results caption is secondary text by design, which is right for a label
       and WRONG for a statement that the number beside it was computed from less
       data than it claims. The caveat keeps its position next to the accuracy --
       a caveat moved elsewhere is a caveat nobody reads -- but not the weight.
       Translucent color-mix so it takes its lightness from whatever is behind it
       in every theme, rather than a fixed tint that only suits one. */
    caption .ea-cv-note {
      display: inline-block; margin-left: 8px; padding: 1px 8px;
      border: 1px solid var(--warn); border-radius: 5px;
      background: color-mix(in srgb, var(--warn) 18%, transparent);
      color: var(--ink); font-weight: 600; white-space: normal;
    }
    .dataTables_wrapper, .dt-container, .dataTables_info, .dt-info,
    .dataTables_length, .dt-length, .dataTables_filter, .dt-search,
    .dataTables_paginate, .dt-paging { color: var(--ink); }
    .dataTables_paginate .paginate_button, .dt-paging .page-link {
      color: var(--ink) !important; background: transparent; border-color: var(--line);
    }
    /* ---- Table readability (backlog F23) --------------------------------------
       Reported: the horizontal scrollbar is only at the bottom, the header is not
       sticky, the columns are too wide and the text too big. So: a STICKY header
       inside the scroll body, tighter cells, smaller type, and a scrollbar that is
       thick enough to grab without hunting for it.
       These target DataTables' own scroll wrapper, which is what `scrollX`/`scrollY`
       create -- styling `table.dataTable` alone cannot make a header stick,
       because the header lives in a SEPARATE table element above the body. */
    /* !important throughout: DataTables ships its own stylesheet as an htmlwidget
       DEPENDENCY, injected when a table first renders -- i.e. AFTER these head
       styles -- and it sets both the header font size and position:relative on the
       scroll head. Source order cannot win, exactly as with the date picker.
       Measured before/after: header font 14px -> 11.5px, scroll head
       position relative -> sticky. */
    table.dataTable th, table.dataTable td { padding: 4px 8px !important;
                  font-size: 12px !important; line-height: 1.35 !important; }
    table.dataTable thead th { font-weight: 600 !important; font-size: 11.5px !important;
                  letter-spacing: .01em; white-space: nowrap; }
    /* Sticky header: DataTables splits head and body into two tables when
       scrollY is set, so pinning the head wrapper keeps it above the body. When
       scrollY is NOT set (plain scrollX), the thead rule below pins the real one. */
    .dataTables_scrollHead, .dt-scroll-head {
                  position: sticky !important; top: 0; z-index: 3;
                  background: var(--panel); }
    .dataTables_wrapper table.dataTable:not(.no-sticky) thead th {
                  position: sticky; top: 0; z-index: 2; background: var(--panel); }
    /* Reachable horizontal scrollbar: make it chunky and always visible rather
       than a hairline at the very bottom of a long table. */
    .dataTables_scrollBody, .dt-scroll-body, .ea-dt-scroll {
                  scrollbar-width: auto; }
    .dataTables_scrollBody::-webkit-scrollbar,
    .dt-scroll-body::-webkit-scrollbar { height: 12px; width: 12px; }
    .dataTables_scrollBody::-webkit-scrollbar-thumb,
    .dt-scroll-body::-webkit-scrollbar-thumb {
                  background: var(--bark); border-radius: 6px; }
    .dataTables_scrollBody::-webkit-scrollbar-track,
    .dt-scroll-body::-webkit-scrollbar-track { background: var(--sunk); }
    /* Stop a long text cell from stretching a column across the screen. */
    table.dataTable td { max-width: 260px; overflow: hidden; text-overflow: ellipsis;
                  white-space: nowrap; }
    table.dataTable.ea-dt { width: 100% !important; }
    .accordion {
      --bs-accordion-bg: var(--panel);
      --bs-accordion-color: var(--ink);
      --bs-accordion-btn-bg: var(--panel);
      --bs-accordion-btn-color: var(--ink);
      --bs-accordion-active-bg: var(--sunk);
      --bs-accordion-active-color: var(--ink);
      --bs-accordion-border-color: var(--line);
    }
    .card, .bslib-card {
      --bs-card-bg: var(--panel);
      --bs-card-color: var(--ink);
      --bs-card-border-color: var(--line);
      --bs-card-cap-bg: var(--sunk);
      --bs-card-cap-color: var(--ink);
    }
    .modal { --bs-modal-bg: var(--panel); --bs-modal-color: var(--ink);
             --bs-modal-border-color: var(--line); }
    .dropdown-menu { --bs-dropdown-bg: var(--panel); --bs-dropdown-color: var(--ink);
             --bs-dropdown-link-color: var(--ink); --bs-dropdown-link-hover-bg: var(--sunk);
             --bs-dropdown-link-hover-color: var(--ink); --bs-dropdown-border-color: var(--line); }
    .nav-tabs { --bs-nav-tabs-link-active-bg: var(--panel);
             --bs-nav-tabs-link-active-color: var(--ink);
             --bs-nav-tabs-border-color: var(--line); }
    /* Linear regression: one output area chosen from a dropdown (backlog 12) */
    .lm-view-label { font: 600 9px var(--mono); text-transform: uppercase;
                  letter-spacing: .08em; color: var(--bark); }
    .lm-viewport { padding: 10px 12px; min-height: 320px; display: flex; flex-direction: column; }
    /* 2+ selected: stacked panes with a draggable divider between them */
    .lm-panes { display: flex; flex-direction: column; flex: 1 1 auto; min-height: 460px; }
    .lm-pane { display: flex; flex-direction: column; min-height: 60px; overflow: hidden;
                  flex: 1 1 0; }
    .lm-pane-h { flex: none; font: 600 8.5px var(--mono); text-transform: uppercase;
                  letter-spacing: .08em; color: var(--bark); padding: 2px 0 4px; }
    .lm-pane-b { flex: 1 1 auto; min-height: 0; overflow: auto; }
    .lm-split { flex: none; height: 7px; margin: 2px 0; cursor: row-resize;
                  border-top: 1px solid var(--line); position: relative; }
    .lm-split:hover, .lm-split.dragging { border-top-color: var(--forest); }
    .lm-split::after { content: ''; position: absolute; left: 50%; top: 1px;
                  width: 34px; height: 3px; margin-left: -17px; border-radius: 2px;
                  background: var(--line); }
    .lm-split:hover::after, .lm-split.dragging::after { background: var(--forest); }
    .lm-scroll { overflow: auto; max-height: 60vh; }
    .lm-formula-box { padding: 7px 10px; margin-bottom: 8px; font-size: 12px;
                  background: var(--sunk); color: var(--ink);
                  border: 1px solid var(--line); border-radius: 6px; }
    .card-header .shiny-input-container { margin-bottom: 0; }
    /* Bootstrap UTILITY colour classes. ~51 card headers across the modules use
       .bg-light, which bslib compiles from the DEFAULT (dark) palette — so it is
       a near-black that never follows the theme. That is the black bar reported
       in the 3D view, and the same bar on every other screen. Fixing it here covers
       every module at once, including ones not yet looked at. */
    .bg-light, .card-header.bg-light { background-color: var(--sunk) !important;
                  color: var(--ink) !important; }
    .bg-white { background-color: var(--panel) !important; color: var(--ink) !important; }
    .bg-dark  { background-color: var(--sunk)  !important; color: var(--ink) !important; }
    .bg-body, .bg-body-tertiary, .bg-body-secondary {
                  background-color: var(--panel) !important; color: var(--ink) !important; }
    /* The SAME trap as .bg-light, in the other places bslib compiled a literal
       dark hex instead of a variable. Found by scanning the compiled
       bootstrap.min.css for rules whose background-color is a literal rgb() dark
       enough to read as black: 30 of them. These are the ones on surfaces this app
       actually renders.
         .modal-footer      rgb(37,41,37) -- the black strip under every dialog,
                            which is the 'black on the packages page' and the same
                            bar in Share project. Transparent, so the frosted
                            .modal-content shows through.
         .input-group-text  rgb(37,41,37)
         .btn-light hover   rgb(33,37,33)
       (The rest were .carousel-indicators and .progress-bar-light, which this app
       never renders, plus the .datepicker family handled further down.) */
    .modal-footer { background-color: transparent; }
    .input-group-text { background-color: var(--sunk); color: var(--ink);
                  border-color: var(--line); }
    .btn-light:hover, .btn-light:active, .btn-outline-light:hover,
    .btn-outline-light:active { background-color: var(--tint); color: var(--ink); }
    /* DATASET SUMMARY TILES (the six value_box()es on Dataset Overview).
       Two things were wrong, both measured in light mode. value_box(theme=) goes
       through Bootstrap's .bg-* utilities, which bslib compiled ONCE from the
       dark palette -- and theme.R maps secondary, success AND info all to
       `canopy`. So every tile came out the same loud mint rgb(126,212,129)
       regardless of its theme, in every app theme: six identical blocks, and the
       distinction between a plain count and a warning was lost entirely -- a
       non-zero NA count looked exactly like the row count.
       Neutral surface now, with colour kept for the tile that is actually saying
       something: an amber edge when there are NAs. An inset box-shadow rather
       than a tinted background, so it needs no color-mix() and cannot fall back
       to Bootstrap's green if that is unsupported.
       .bg-* are !important in Bootstrap, so these have to be too; scoped to
       .bslib-value-box so buttons and badges elsewhere keep their colours. */
    .bslib-value-box.bg-secondary, .bslib-value-box.bg-success,
    .bslib-value-box.bg-info, .bslib-value-box.bg-warning {
                  background-color: var(--sunk) !important;
                  color: var(--ink) !important;
                  border: 1px solid var(--line); }
    .bslib-value-box.bg-warning { box-shadow: inset 3px 0 0 var(--warn); }
    .bslib-value-box .value-box-title { color: var(--bark) !important; }
    .bslib-value-box .value-box-showcase { color: var(--forest); }
    /* DATE PICKER (dateInput -- Download spatial data uses two). bslib compiled
       bootstrap-datepicker.css from the DEFAULT (dark) palette too, so ALL 32 of
       its state backgrounds are dark greens: on a light theme the hovered day,
       the selected day and the range fill read as black blobs.
       !important is needed here and not elsewhere: that stylesheet is injected as
       a Shiny DEPENDENCY the first time a dateInput renders, which is AFTER these
       head styles, so source order cannot win. */
    .datepicker { background: var(--panel); color: var(--ink);
                  border: 1px solid var(--line); }
    .datepicker table tr td, .datepicker table tr th { color: var(--ink); }
    .datepicker table tr td.old, .datepicker table tr td.new { color: var(--bark) !important; }
    .datepicker table tr td.day:hover, .datepicker table tr td.focused,
    .datepicker table tr td span:hover, .datepicker table tr td span.focused,
    .datepicker .datepicker-switch:hover, .datepicker .prev:hover,
    .datepicker .next:hover, .datepicker tfoot tr th:hover {
                  background: var(--tint) !important; color: var(--ink) !important; }
    .datepicker table tr td.highlighted, .datepicker table tr td.today,
    .datepicker table tr td.range, .datepicker table tr td.range.highlighted,
    .datepicker table tr td.range:hover {
                  background: var(--sunk) !important; color: var(--ink) !important; }
    .datepicker table tr td.selected, .datepicker table tr td.selected:hover,
    .datepicker table tr td.active, .datepicker table tr td.active:hover,
    .datepicker table tr td span.active, .datepicker table tr td span.active:hover {
                  background: var(--forest) !important; color: var(--onbrand) !important; }
    /* Inputs: Bootstrap compiles these to literal hex, not vars -- state them. */
    .form-control, .form-select, textarea.form-control,
    .selectize-input, .selectize-dropdown {
      background-color: var(--panel); color: var(--ink); border-color: var(--line);
    }
    .selectize-dropdown .active { background: var(--sunk); color: var(--ink); }
    .form-control::placeholder { color: var(--bark); }

    /* Boot overlay — one calm screen instead of a dimming, half-drawn app. */
    #ea-boot { position: fixed; inset: 0; z-index: 4000; background: var(--paper);
               display: flex; align-items: center; justify-content: center;
               transition: opacity .3s ease; }
    #ea-boot.gone { opacity: 0; pointer-events: none; }
    .ea-boot-inner { display: flex; flex-direction: column; align-items: center; gap: 12px; }
    .ea-boot-mark { width: 46px; height: 46px; border-radius: 12px; background: var(--forest);
               color: var(--onbrand); display: grid; place-items: center; font-size: 20px; }
    .ea-boot-name { font: 650 17px var(--ui); color: var(--ink); letter-spacing: -.01em; }
    .ea-boot-bar { width: 190px; height: 3px; border-radius: 2px; background: var(--line);
               overflow: hidden; }
    .ea-boot-bar i { display: block; width: 40%; height: 100%; border-radius: 2px;
               background: var(--forest); animation: eaBoot 1.1s ease-in-out infinite; }
    @keyframes eaBoot { 0% { transform: translateX(-100%); } 100% { transform: translateX(350%); } }
    .ea-boot-msg { font: 500 11.5px var(--mono); color: var(--bark); letter-spacing: .04em; }
    @media (prefers-reduced-motion: reduce) { .ea-boot-bar i { animation: none; width: 100%; } }

    html, body { height: 100%; }
    body { background: var(--paper); color: var(--ink); }
    .app-shell { display: grid; grid-template-rows: auto 1fr auto; height: 100vh; }

    /* ---- Top menubar ---- */
    .app-topbar {
      background: var(--forest); color: #fff;
      display: flex; align-items: center; gap: 6px;
      padding: 0 8px; height: 40px;
      box-shadow: 0 1px 4px rgba(0,0,0,.18);
    }
    .app-topbar .brand {
      font-weight: 700; font-size: 15px; letter-spacing: .4px;
      margin-right: 6px; white-space: nowrap;
      display: flex; align-items: center; gap: 6px;
    }
    /* the app icon in the brand (lightbulb, for now) */
    .app-topbar .brand-icon { color: var(--canopy); font-size: 14px; }
    .app-topbar .brand-dot {
      width: 8px; height: 8px; border-radius: 50%;
      background: #a5d6a7; display: inline-block;
    }
    .app-topbar .navbar-nav, .app-topbar ul.nav {
      display: flex; flex-direction: row;
      margin: 0; padding: 0; list-style: none; height: 100%;
    }
    .app-topbar .nav-link.app-menu {
      color: rgba(255,255,255,.88) !important;
      padding: 0 11px; font-size: 13px; cursor: pointer;
      display: flex; align-items: center; height: 100%;
      border-bottom: 2px solid transparent;
      transition: background .12s, color .12s, border-color .12s;
    }
    .app-topbar .nav-link.app-menu:hover {
      color: #fff !important;
      background: rgba(255,255,255,.1);
      border-bottom-color: rgba(255,255,255,.5);
    }
    .app-topbar .dropdown-menu {
      font-size: 13px; min-width: 210px;
      box-shadow: 0 4px 16px rgba(0,0,0,.15);
      border: 1px solid rgba(0,0,0,.08);
    }
    .app-topbar .dropdown-item { padding: 7px 14px; }
    .app-topbar .dropdown-item:hover { background: var(--tint); color: var(--forest); }
    .app-topbar .dropdown-item.active,
    .app-topbar .dropdown-item:active { background: var(--forest); color: #fff; }

    /* ---- Topbar right-side quick actions ---- */
    .topbar-right { margin-left: auto; display: flex; align-items: center; gap: 2px; }
    .topbar-action-btn {
      background: transparent; border: none;
      color: rgba(255,255,255,.82);
      padding: 4px 9px; font-size: 12px; cursor: pointer;
      border-radius: 4px;
      display: flex; align-items: center; gap: 5px;
      transition: background .15s, color .15s;
      white-space: nowrap; height: 30px;
    }
    .topbar-action-btn:hover {
      background: rgba(255,255,255,.15); color: #fff;
    }
    /* Quit reads as destructive only on hover, so it does not shout from the
       bar the whole time -- it is used once per session, not constantly. */
    .topbar-action-btn.tb-quit:hover {
      background: color-mix(in srgb, var(--danger) 82%, transparent); color: #fff;
    }
    /* Post-quit veil. Tokenised so it matches whatever theme is active. */
    #ea-quit-veil {
      position: fixed; inset: 0; z-index: 100000; display: none;
      align-items: center; justify-content: center;
      background: color-mix(in srgb, var(--paper) 94%, transparent);
      -webkit-backdrop-filter: blur(6px); backdrop-filter: blur(6px);
    }
    #ea-quit-veil.on { display: flex; }
    /* Disconnect panel. Replaces Shiny's own grey veil, which is hidden below —
       two overlays would stack, and Shiny's offers no way to recover. */
    #shiny-disconnected-overlay { display: none !important; }
    #ea-disconnect {
      position: fixed; inset: 0; z-index: 100001; display: none;
      align-items: center; justify-content: center;
      background: color-mix(in srgb, var(--paper) 92%, transparent);
      -webkit-backdrop-filter: blur(6px); backdrop-filter: blur(6px);
    }
    #ea-disconnect.on { display: flex; }
    .ea-dc-card {
      text-align: center; max-width: 460px; padding: 30px 34px;
      background: var(--panel); border: 1px solid var(--line);
      border-radius: 14px; box-shadow: 0 18px 50px rgba(0,0,0,.32);
      color: var(--ink); font-family: var(--ui);
    }
    .ea-dc-card h3 { margin: 14px 0 8px; font-size: 17px; }
    .ea-dc-card p { margin: 0 0 6px; font-size: 13px; color: var(--bark); }
    .ea-dc-sub { font-size: 12px !important; opacity: .8; margin-top: 10px !important; }
    .ea-dc-mark {
      width: 46px; height: 46px; margin: 0 auto; border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      background: color-mix(in srgb, var(--warn) 18%, transparent);
      color: var(--warn); font-size: 19px;
    }
    .ea-dc-actions { margin: 16px 0 4px; }
    .ea-dc-btn {
      background: var(--forest); color: var(--onbrand); border: none;
      border-radius: 8px; padding: 9px 18px; font-size: 13px; font-weight: 600;
      cursor: pointer; font-family: var(--ui);
    }
    .ea-dc-btn:hover { background: var(--canopy); }
    .ea-dc-btn[disabled] { opacity: .5; cursor: default; }
    .ea-quit-card {
      text-align: center; max-width: 420px; padding: 30px 34px;
      background: var(--panel); border: 1px solid var(--line);
      border-radius: 14px; box-shadow: 0 18px 50px rgba(0,0,0,.32);
      color: var(--ink); font-family: var(--ui);
    }
    .ea-quit-card h3 { margin: 14px 0 8px; font-size: 17px; }
    .ea-quit-card p { margin: 0 0 6px; font-size: 13px; color: var(--bark); }
    .ea-quit-sub { font-size: 12px !important; opacity: .8; }
    .ea-quit-mark {
      width: 46px; height: 46px; margin: 0 auto; border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      background: color-mix(in srgb, var(--forest) 16%, transparent);
      color: var(--forest); font-size: 19px;
    }
    .topbar-sep {
      width: 1px; height: 20px;
      background: rgba(255,255,255,.28); margin: 0 4px;
    }

    /* ---- Menu-free chrome ----
       On the Projects landing and the inside-a-project Overview, the analysis
       menubar, the tool search and the data-only actions (Undo/Reset) are
       hidden: you are choosing/opening a project, not analysing yet. They come
       back the moment you enter the workspace (any analysis view). Toggled by
       the ea-view handler; shipped in the initial markup because the app starts
       on Projects. */
    .app-topbar.menufree > .nav,
    .app-topbar.menufree .ea-toolsearch,
    .app-topbar.menufree .tb-ws { display: none !important; }
    /* Co-Analyst is hidden on BOTH menu-free screens (Projects welcome-back and
       the project Overview) — you're picking/opening a project, not analysing.
       It returns only inside the workspace. */
    .app-topbar.menufree .tb-coanalyst { display: none !important; }
    /* ...and the green bar itself goes away: Projects and Overview are just an
       identity line (brand + a couple of quiet actions) on the page background,
       like the sandbox: no menubar, just identity. The green menubar returns
       only in the workspace. */
    .app-topbar.menufree {
      background: var(--paper) !important;
      border-bottom: none !important;
      box-shadow: none !important;
      height: 54px; padding: 0 22px;
    }
    .app-topbar.menufree .brand { color: var(--ink); }
    .app-topbar.menufree .topbar-action-btn { color: var(--bark); }
    .app-topbar.menufree .topbar-action-btn:hover { background: var(--tint); color: var(--ink); }

    /* ---- Tool search (workspace menubar) ----
       One box that indexes every menu item so users don't hunt through menus.
       Index is built from the live menu DOM, so it never drifts. */
    .ea-toolsearch { position: relative; margin-right: 8px; }
    .ea-toolsearch-input {
      width: 200px; height: 30px;
      background: rgba(255,255,255,.14);
      border: 1px solid rgba(255,255,255,.28); border-radius: 6px;
      color: #fff; font-size: 12.5px; padding: 5px 10px; outline: none;
      transition: width .15s, background .15s, border-color .15s;
    }
    .ea-toolsearch-input::placeholder { color: rgba(255,255,255,.62); }
    .ea-toolsearch-input:focus {
      width: 250px; background: rgba(255,255,255,.22);
      border-color: rgba(255,255,255,.55);
    }
    .ea-toolsearch-results {
      position: absolute; top: 100%; right: 0; margin-top: 7px; width: 300px;
      max-height: 340px; overflow: auto;
      background: var(--panel); border: 1px solid var(--line); border-radius: 9px;
      box-shadow: 0 14px 34px rgba(0,0,0,.4); padding: 6px; display: none; z-index: 1200;
    }
    .ea-toolsearch-results.open { display: block; }
    .ea-toolsearch-results a {
      display: flex; align-items: center; gap: 8px; padding: 8px 10px;
      border-radius: 6px; font-size: 13px; color: var(--ink);
      text-decoration: none; cursor: pointer;
    }
    .ea-toolsearch-results a:hover { background: var(--tint); }
    .ea-toolsearch-results a .grp {
      margin-left: auto; font-family: var(--mono); font-size: 10px;
      color: var(--bark); white-space: nowrap;
    }
    .ea-toolsearch-results .none { padding: 11px; color: var(--bark); font-size: 12.5px; }
    .ea-ts-head { padding: 7px 11px 4px; font: 700 9.5px var(--ui); letter-spacing: .12em;
                  text-transform: uppercase; color: var(--bark);
                  border-top: 1px solid var(--line); }
    .ea-ts-act { margin-left: auto; font: 600 10px var(--ui); padding: 1px 8px;
                  border-radius: 999px; border: 1px solid var(--forest);
                  color: var(--forest);
                  background: color-mix(in srgb, var(--forest) 12%, transparent); }
    .ea-toolsearch-results .ea-ts-extra a { display: flex; align-items: center; gap: 8px; }
    .ea-ts-act.off { border-color: var(--line); color: var(--bark); background: none; }
    .ea-toolsearch-results a.ea-ts-dim { opacity: .62; cursor: default; }

    /* ---- Body layout ---- */
    .app-main {
      display: grid;
      --left-w: 240px; --right-w: 350px;
      grid-template-columns: var(--left-w) 5px minmax(0,1fr) 5px var(--right-w);
      min-height: 0;
      transition: grid-template-columns .12s ease;
    }
    .app-main.left-collapsed  { --left-w: 36px; }
    .app-main.right-collapsed { --right-w: 36px; }
    /* project-left nav is only relevant to the Projects screen; keep it hidden
       everywhere else (it lives inside the shared .app-left). */
    .ea-projleft { display: none; }
    /* Projects screen = a clean, full-width page (both empty AND populated).
       The card-grid canvas already carries everything the mockup needs: the
       page bar (New project / Tour / Import .eap), the Welcome-back header, and
       per-card Open / Rename / Delete actions. So BOTH rails are hidden and the
       canvas spans the full width -- exactly like the sandbox welcome-back.
       Hiding the panels AND single-columning together avoids the old pile-up
       (forcing one column while the panels were still visible stacked them). */
    .app-main.view-projects { grid-template-columns: minmax(0,1fr); }
    .app-main.view-projects .app-left,
    .app-main.view-projects .app-right,
    .app-main.view-projects .app-divider { display: none !important; }
    /* the collapse chevron is for the data rail; hide it on the projects nav */
    .app-main.view-projects .app-left .rail-toggle { display: none; }
    .ea-projleft h6 { font-size: 11px; font-weight: 600; letter-spacing: .12em;
                      text-transform: uppercase; color: var(--bark);
                      font-family: var(--mono); margin-bottom: 10px; }
    /* Inside a project (Overview): 3-column frame (base .app-main grid). The left
       rail shows an INFORMATIONAL Project-data list (.ea-project-left), NOT the
       interactive Datasets rail — so on this view hide .rail-body and show the
       informational panel instead. */
    .ea-project-left { display: none; }
    .app-main.view-project .app-left .rail-body     { display: none; }
    .app-main.view-project .app-left .ea-project-left { display: block; }
    .ea-project-left h6 { color: var(--bark); border-bottom: 1px solid var(--line);
                          padding-bottom: 10px; margin-bottom: 12px; }
    .ea-pd-list { display: flex; flex-direction: column; gap: 6px; }
    .ea-pd-item { display: flex; align-items: center; gap: 8px; padding: 6px 8px;
                  border: 1px solid var(--line); border-radius: 6px;
                  background: var(--panel); color: var(--ink); font-size: 12.5px;
                  margin-bottom: 6px; }
    .ea-pd-dot { width: 9px; height: 9px; border-radius: 2px; flex: 0 0 auto; }
    .ea-pd-nm  { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    /* Categorised data list (left rail): a section per type, items beneath. */
    .ea-pd-cats { display: flex; flex-direction: column; gap: 14px; }
    .ea-pd-cat-h { display: flex; align-items: center; gap: 6px; margin-bottom: 6px;
                   font: 600 10px var(--mono); letter-spacing: .1em; text-transform: uppercase;
                   color: var(--bark); }
    .ea-pd-cat-n { margin-left: auto; font-family: var(--mono); color: var(--bark); }
    .app-left, .app-right {
      background: var(--sunk); overflow-y: auto; padding: 10px; position: relative;
    }
    .app-left  { border-right: 1px solid var(--line); }
    .app-right { border-left:  1px solid var(--line); }
    .app-center { overflow: auto; padding: 10px; min-width: 0; }
    .app-left h6 {
      text-transform: uppercase; font-size: 11px;
      letter-spacing: .6px; color: var(--bark);
    }
    .app-main.left-collapsed  .app-left  .rail-body,
    .app-main.right-collapsed .app-right .rail-body { display: none; }
    .app-main.left-collapsed  .app-left,
    .app-main.right-collapsed .app-right { padding: 8px 2px; overflow: hidden; }

    /* ---- Resize dividers ---- */
    .app-divider { cursor: col-resize; background: transparent; transition: background .1s; }
    .app-divider:hover, .app-divider.dragging { background: var(--canopy); }
    .app-main.left-collapsed  .app-divider.left,
    .app-main.right-collapsed .app-divider.right { pointer-events: none; }

    /* ---- Rail collapse toggles ---- */
    .rail-toggle {
      border: none; background: transparent; color: var(--bark);
      cursor: pointer; font-size: 13px; padding: 0 4px; line-height: 1.4;
    }
    .rail-toggle:hover { color: var(--forest); }
    .app-left  .rail-toggle { float: right; }
    .app-right .rail-toggle { float: left; }
    .rail-toggle .chev { display: inline-block; transition: transform .12s; }
    .app-main.left-collapsed  .app-left  .rail-toggle .chev,
    .app-main.right-collapsed .app-right .rail-toggle .chev { transform: rotate(180deg); }

    /* ---- Datasets list ---- */
    .ds-item {
      display: flex; align-items: center; gap: 6px;
      padding: 6px 8px; border-radius: 6px; cursor: pointer; font-size: 13px;
    }
    .ds-item:hover { background: var(--tint); }
    .ds-item.active { background: var(--forest); color: #fff; }
    .ds-item .dot {
      width: 8px; height: 8px; border-radius: 50%;
      background: var(--canopy); flex: 0 0 auto;
    }
    .ds-item.active .dot { background: var(--panel); }

    /* ---- Status bar ---- */
    .app-status {
      background: var(--sunk); border-top: 1px solid var(--line);
      font-size: 12px; color: var(--bark);
      display: flex; align-items: center; gap: 18px; padding: 3px 14px;
    }
    .app-status .sep { color: var(--bark); }
    /* Project location shows in FULL (no truncation). */
    .app-status .status-loc { display: inline-flex; align-items: center; gap: 4px;
                              white-space: nowrap; }
    .app-status .status-loc strong { white-space: nowrap; }

    /* ===== UNIFIED WORKSPACE (BETA) — two views; see UNIFIED_WORKSPACE.md ===== */
    .app-main.view-workspace { grid-template-columns: minmax(0,1fr); }
    .app-main.view-workspace .app-left,
    .app-main.view-workspace .app-right,
    .app-main.view-workspace .app-divider { display: none !important; }
    .app-main.view-workspace .app-center { padding: 0; }
    /* The workspace must FILL the shell. bslib nests the panes as
       .app-center > div.tabbable > (ul.nav + div.tab-content > div.tab-pane),
       so use DESCENDANT selectors — a direct-child chain silently fails to match
       and the whole workspace collapses to its content size (top-left corner). */
    .app-main.view-workspace { min-height: 0; }
    .app-main.view-workspace .app-center {
      display: flex; flex-direction: column; min-height: 0; padding: 0; overflow: hidden; }
    /* :not(.tab-pane) matters. Every tab-pane also carries .html-fill-container,
       so without it this rule set display:flex on INACTIVE panes too — it is more
       specific than Bootstrap's .tab-content > .tab-pane { display: none }, which
       stopped hiding them. Every tab of a screen rendered at once, stacked, and
       clicking a tab looked like it did nothing because the pane it selected was
       already on screen. Active panes are covered by .tab-pane.active above. */
    .app-main.view-workspace .app-center .tabbable,
    .app-main.view-workspace .app-center .tab-content,
    .app-main.view-workspace .app-center .tab-pane.active,
    .app-main.view-workspace .app-center .html-fill-container:not(.tab-pane) {
      flex: 1 1 auto; min-height: 0; width: 100%; display: flex; flex-direction: column; }
    .ea-wsx { display: flex; flex-direction: column; flex: 1 1 auto;
              width: 100%; height: 100%; min-height: 0; }
    .ea-wsx-bar { display: flex; align-items: center; gap: 12px; padding: 8px 12px;
                  border-bottom: 1px solid var(--line); background: var(--sunk); }
    .ea-wsx-tabs { display: inline-flex; border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
    .ea-wsx-tab { font: 600 12.5px var(--ui); border: none; background: transparent; color: var(--bark);
                  padding: 6px 15px; cursor: pointer; }
    .ea-wsx-tab.on { background: var(--forest); color: var(--onbrand); }
    /* Plot appearance controls: a stacked block in the tool panel, a compact
       inline strip in the chart bar. */
    .ea-wsx-popts { margin-top: 10px; border-top: 1px solid var(--line); padding-top: 8px; }
    .ea-wsx-popts label { display: block; font: 600 8.5px var(--mono); color: var(--bark);
                  text-transform: uppercase; letter-spacing: .08em; margin: 6px 0 2px; }
    .ea-wsx-popts .shiny-input-container { margin-bottom: 0; width: 100% !important; }
    .ea-wsx-popts.inline { display: contents; }
    .ea-wsx-popts.inline label { display: inline-block; margin: 0 0 0 4px; }
    /* ---- .ea-pop : a hover panel behind one icon (REUSABLE) ----------------
       Use anywhere a group of occasional settings would otherwise take a whole
       row. Hover opens it; clicking the icon PINS it open (so it cannot vanish
       mid-edit); Escape or a click outside closes it. Markup:
         div.ea-pop > button.ea-pop-btn[onclick=eaPop(this)] + div.ea-pop-body  */
    .ea-pop { position: relative; display: inline-flex; margin-left: auto; }
    .ea-pop.block { display: block; margin-left: 0; margin-top: 10px; }
    /* The map's own controls button sits at the right of the map strip, before the
       3D toggle, and its panel must clear the leaflet canvas. */
    .ea-pop.ea-pop-map { margin-left: auto; }
    .ea-pop.ea-pop-map .ea-pop-body { z-index: 1200; min-width: 190px; }
    .ea-pop.ea-pop-map .ea-ctx-item { font: 400 12.5px var(--ui); }
    /* Right-click menu on a layer row (built by eaLayerMenu). Fixed position at
       the cursor, so it must sit above the panels and the leaflet map. */
    .ea-ctxmenu { position: fixed; z-index: 4000; min-width: 186px; padding: 5px;
                  background: var(--panel); color: var(--ink);
                  border: 1px solid var(--line); border-radius: 9px;
                  box-shadow: 0 14px 38px rgba(0,0,0,.34); font: 400 12.5px var(--ui); }
    .ea-ctx-item { display: block; padding: 7px 10px; border-radius: 6px;
                   color: var(--ink); text-decoration: none; cursor: pointer;
                   white-space: nowrap; }
    .ea-ctx-item:hover { background: var(--tint); color: var(--ink); text-decoration: none; }
    .ea-ctx-item.danger { color: var(--danger); }
    .ea-ctx-item.danger:hover { background: var(--danger); color: #fff; }
    .ea-ctx-sep { height: 1px; margin: 4px 6px; background: var(--line); }
    .ea-pop-btn { font: 500 11px var(--ui); border: 1px solid var(--line);
                  background: var(--panel); color: var(--bark); border-radius: 6px;
                  padding: 4px 9px; cursor: pointer; white-space: nowrap;
                  display: inline-flex; align-items: center; gap: 6px; }
    .ea-pop-btn:hover { border-color: var(--forest); color: var(--forest); }
    .ea-pop-btn.set  { border-color: var(--forest); color: var(--forest);
                  background: color-mix(in srgb, var(--forest) 12%, transparent); }
    .ea-pop-body { display: none; position: absolute; top: calc(100% + 6px); right: 0;
                  z-index: 1400; width: 232px; padding: 10px 11px 9px;
                  background: var(--panel); border: 1px solid var(--line);
                  border-radius: 9px; box-shadow: 0 14px 34px rgba(0,0,0,.32); }
    .ea-pop.block .ea-pop-body { left: 0; right: auto; width: 100%; }
    /* a hover bridge, so moving the pointer to the panel does not close it */
    .ea-pop-body::before { content: ''; position: absolute; top: -8px; left: 0;
                  right: 0; height: 8px; }
    .ea-pop:hover .ea-pop-body, .ea-pop.open .ea-pop-body { display: block; }
    .ea-pop-h { font: 600 8.5px var(--mono); text-transform: uppercase;
                  letter-spacing: .08em; color: var(--bark); margin-bottom: 8px;
                  display: flex; align-items: center; gap: 6px; }
    .ea-pop-row { margin-bottom: 7px; }
    .ea-pop-row > label { display: flex; align-items: center; gap: 5px;
                  font: 500 10.5px var(--ui); color: var(--bark); margin-bottom: 2px; }
    .ea-pop-row .shiny-input-container { margin-bottom: 0; width: 100% !important; }
    .ea-pop-row .form-control { font-size: 11.5px; padding: 3px 7px;
                  background: var(--sunk); color: var(--ink); border-color: var(--line); }
    .ea-pop-row svg, .ea-pop-row .fa, .ea-pop-h svg, .ea-pop-h .fa { font-size: 9px; }
    .ea-pop-note { font-size: 9.5px; color: var(--bark); margin-top: 6px; }
    .ea-wsx-colpick { width: 30px; height: 26px; padding: 0; border: 1px solid var(--line);
                  border-radius: 6px; background: var(--panel); cursor: pointer; }
    .ea-wsx-chartbar .shiny-input-container { margin-bottom: 0; }
    .ea-wsx-3dbtn { margin-left: auto; font: 600 11px var(--ui); border: 1px solid var(--line);
                  background: var(--panel); color: var(--ink); border-radius: 7px;
                  padding: 4px 10px; cursor: pointer; display: inline-flex;
                  align-items: center; gap: 5px; }
    .ea-wsx-3dbtn:hover { border-color: var(--forest); color: var(--forest); }
    .ea-wsx-3dbtn.on { background: var(--forest); border-color: var(--forest); color: var(--onbrand); }
    .ea-wsx-3dbtn svg, .ea-wsx-3dbtn .fa { font-size: 10px; }
    .ea-wsx-threewrap { flex: 1 1 auto; min-height: 0; overflow: auto; padding: 8px 10px; }
    /* Point-density control, floating over the map (LAZ layers only) */
    .ea-wsx-lasctl { position: absolute; left: 12px; bottom: 14px; z-index: 620;
                  background: var(--panel); border: 1px solid var(--line); border-radius: 8px;
                  padding: 7px 10px 0; box-shadow: 0 6px 18px rgba(0,0,0,.28); }
    .ea-wsx-lasctl-h { font: 600 8.5px var(--mono); text-transform: uppercase;
                  letter-spacing: .08em; color: var(--bark); }
    .ea-wsx-lasctl-n { font-size: 9.5px; color: var(--bark); margin: -6px 0 6px; }
    .ea-wsx-lasctl .form-group, .ea-wsx-lasctl .shiny-input-container { margin-bottom: 0; }
    .ea-wsx-lasctl .irs { min-height: 34px; }
    .ea-wsx-lasctl .irs-bar, .ea-wsx-lasctl .irs-single { background: var(--forest);
                  border-color: var(--forest); }
    .ea-wsx-lasctl .irs-line { background: var(--sunk); }
    .ea-wsx-lasctl .irs-min, .ea-wsx-lasctl .irs-max { display: none; }
    .ea-wsx-note { font: 500 11px var(--mono); color: var(--bark); margin-left: auto; }
    /* ---- GeoLibre-style menubar (Project | Edit | View | … | Help) ---- */
    .legacy-nav { display: none !important; }
    /* Hosted in the app top bar: transparent bar, light text on the green. */
    .app-topbar .gm-host { display: flex; align-items: stretch; min-width: 0; }
    .app-topbar .gm-bar { background: transparent; border-bottom: none; padding: 0; }
    .app-topbar .gm-btn { color: rgba(255,255,255,.92); height: 34px; font-size: 12.5px; }
    .app-topbar .gm-btn svg, .app-topbar .gm-btn .fa { color: rgba(255,255,255,.72); }
    .app-topbar .gm-btn:hover { background: rgba(255,255,255,.12); }
    .app-topbar .gm.open > .gm-btn { background: rgba(255,255,255,.18); border-color: rgba(255,255,255,.4); }
    .app-topbar.menufree .gm-host { display: none !important; }
    .gm-bar { display: flex; align-items: stretch; gap: 2px; background: var(--panel);
              border-bottom: 1px solid var(--line); padding: 0 8px; flex: none; }
    .gm { position: relative; }
    .gm-btn { display: flex; align-items: center; gap: 7px; height: 36px; padding: 0 12px;
              background: transparent; border: 1px solid transparent; border-radius: 7px;
              color: var(--ink); font: 550 12.5px var(--ui); cursor: pointer; white-space: nowrap; }
    .gm-btn:hover { background: var(--tint); }
    .gm.open > .gm-btn { background: var(--tint); border-color: var(--forest); }
    .gm-btn svg, .gm-btn .fa { color: var(--bark); font-size: 12px; }
    .gm-menu { position: absolute; top: 100%; left: 0; margin-top: 4px; min-width: 232px;
               width: max-content; max-width: 360px;
               background: var(--panel); border: 1px solid var(--line); border-radius: 10px;
               box-shadow: 0 18px 44px rgba(0,0,0,.55); padding: 6px; display: none; z-index: 1200; }
    .gm-menu > .gm-item { white-space: nowrap; }
    .gm.open > .gm-menu { display: block; }
    /* .gm-head (a repeated menu title inside the dropdown) was removed — the
       button above already names the menu. Group labels stay. */
    .gm-grp { font: 600 8.5px var(--mono); letter-spacing: .12em; text-transform: uppercase;
              color: var(--bark); padding: 6px 10px 4px; }
    .gm-menu > .gm-grp:first-child { padding-top: 2px; }
    .gm-item { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border-radius: 6px;
               font-size: 12.5px; color: var(--ink); text-decoration: none; cursor: pointer; }
    .gm-item:hover { background: var(--tint); color: var(--ink); text-decoration: none; }
    .gm-item.disabled { color: var(--bark); opacity: .5; pointer-events: none; }
    /* map-based tool: note that its output goes onto the workspace map */
    .ea-wsx-mapnote2 { font-size: 11.5px; color: var(--bark); line-height: 1.5; background: var(--tint);
                  border-left: 2px solid var(--forest); border-radius: 7px; padding: 8px 10px;
                  margin-bottom: 10px; }
    .ea-wsx-mapnote2 svg, .ea-wsx-mapnote2 .fa { color: var(--canopy); margin-right: 4px; }
    /* Data view: a tool's results take the centre, with a way back to the data */
    /* the appearance icon sits between the tool name and the back button */
    .ea-wsx-resulthead .ea-pop { margin-left: auto; margin-right: 8px; }
    .ea-wsx-resulthead { display: flex; align-items: center; gap: 10px; margin-bottom: 10px;
                  padding-bottom: 9px; border-bottom: 1px solid var(--line); }
    .ea-wsx-backbtn { margin-left: auto; font: 550 11.5px var(--mono); color: var(--canopy);
                  background: var(--tint); border: 1px solid var(--line); border-radius: 6px;
                  padding: 5px 11px; cursor: pointer; }
    .ea-wsx-backbtn:hover { border-color: var(--canopy); }
    /* Tool panel header: name + float / minimize / close */
    .ea-wsx-toolbar { display: flex; align-items: center; gap: 8px; padding: 0 0 9px;
                  margin-bottom: 10px; border-bottom: 1px solid var(--line); }
    .ea-wsx-toolnm { font-size: 13px; font-weight: 640; color: var(--ink);
                  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .ea-wsx-toolctl { margin-left: auto; display: flex; gap: 2px; flex: none; }
    .ea-wsx-toolctl button { border: 1px solid transparent; background: transparent; color: var(--bark);
                  cursor: pointer; font: 600 13px var(--mono); line-height: 1; padding: 2px 6px;
                  border-radius: 5px; }
    .ea-wsx-toolctl button:hover { background: var(--tint); color: var(--ink); border-color: var(--line); }
    /* Packages menu: optional-package list */
    .ea-wsx-pkglist { display: flex; flex-direction: column; gap: 6px; margin-top: 10px; }
    .ea-wsx-pkgrow { display: flex; align-items: center; gap: 10px; padding: 8px 10px;
                  border: 1px solid var(--line); border-radius: 8px; background: var(--panel); }
    .ea-wsx-pkgdot { width: 9px; height: 9px; border-radius: 50%; flex: none; }
    .ea-wsx-pkgdot.ok { background: var(--forest); } .ea-wsx-pkgdot.no { background: var(--line); }
    .ea-wsx-pkgnm { font: 600 12.5px var(--mono); min-width: 120px; }
    .ea-wsx-pkgd { font-size: 12px; color: var(--bark); flex: 1 1 auto; }
    .ea-wsx-pkgok { font: 500 11px var(--mono); color: var(--canopy); }
    .gm-item.has-sub { position: relative; }
    .gm-item.has-sub::after { content: '\\203A'; margin-left: auto; color: var(--bark); font-size: 14px; }
    /* ▸ fly-out submenu (GeoLibre style): opens to the side on hover.
       It must FEEL natural: no dead gap to cross (an invisible bridge keeps it
       open on a diagonal move), the parent row stays highlighted, and the first
       submenu row lines up with the parent row. */
    /* Sizes to its CONTENT — a desktop menu never has an inner scrollbar; if it
       would run off the bottom it is nudged up by JS instead. */
    .gm-sub { position: absolute; left: 100%; top: -7px; min-width: 236px; width: max-content;
              max-width: 340px;
              background: var(--panel); border: 1px solid var(--line); border-radius: 10px;
              box-shadow: 0 18px 44px rgba(0,0,0,.55); padding: 6px; display: none; z-index: 1300; }
    .gm-sub .gm-item { white-space: nowrap; }
    .gm-sub::before { content: ''; position: absolute; left: -10px; top: 0; width: 10px; height: 100%; }
    .gm-item.has-sub:hover > .gm-sub,
    .gm-item.has-sub:focus-within > .gm-sub { display: block; }
    /* keep the parent row lit while the fly-out is open */
    .gm-item.has-sub:hover { background: var(--tint); color: var(--ink); }
    .gm-item.has-sub:hover::after { color: var(--canopy); }
    /* flip to the left when the menu is near the right edge of the window */
    .gm-sub.flip { left: auto; right: 100%; }
    /* panel visibility toggles (Controls menu) */
    .ea-wsx-grid.no-left  { grid-template-columns: 0 1fr var(--ws-right, 240px) 46px; }
    .ea-wsx-grid.no-right { grid-template-columns: var(--ws-left, 200px) 1fr 0 46px; }
    .ea-wsx-grid.no-dock  { grid-template-columns: var(--ws-left, 200px) 1fr var(--ws-right, 240px) 0; }
    .ea-wsx-grid.no-left.no-right  { grid-template-columns: 0 1fr 0 46px; }
    .ea-wsx-grid.no-left.no-dock   { grid-template-columns: 0 1fr var(--ws-right, 240px) 0; }
    .ea-wsx-grid.no-right.no-dock  { grid-template-columns: var(--ws-left, 200px) 1fr 0 0; }
    .ea-wsx-grid.no-left.no-right.no-dock { grid-template-columns: 0 1fr 0 0; }
    .ea-wsx-grid.no-left  > .ea-wsx-left,
    .ea-wsx-grid.no-right > .ea-wsx-right,
    .ea-wsx-grid.no-dock  > .ea-wsx-dock { display: none; }
    .gm-item.on::after { content: '\\2713'; margin-left: auto; color: var(--canopy); }
    .gm-sep { height: 1px; background: var(--line); margin: 6px 4px; }
    /* colour-set swatch in the Theme submenu */
    .gm-swatch { width: 14px; height: 14px; border-radius: 4px; border: 2px solid; flex: none; }
    /* M7: active-tool chip in the view bar (replaces the retired tool dropdown) */
    .ea-wsx-active-tool { margin-left: auto; display: flex; align-items: center; gap: 6px; }
    .ea-wsx-atl { display: inline-flex; align-items: center; gap: 7px; font-size: 12.5px;
                  font-weight: 600; color: var(--ink); background: var(--tint);
                  border: 1px solid var(--forest); border-radius: 999px; padding: 5px 13px; }
    .ea-wsx-atl svg, .ea-wsx-atl .fa { color: var(--canopy); font-size: 11px; }
    .ea-wsx-atl-none { font-size: 12px; color: var(--bark); }
    .ea-wsx-atl-none b { color: var(--ink); }
    .ea-wsx-atl-x { border: 1px solid var(--line); background: var(--panel); color: var(--bark);
                  border-radius: 50%; width: 22px; height: 22px; cursor: pointer;
                  font: 600 13px var(--mono); line-height: 1; }
    .ea-wsx-atl-x:hover { border-color: var(--danger); color: var(--danger); }
    /* Side panel widths are VARIABLES so the drag handles can set them; the
       collapse variants below only ever zero the column they hide, leaving the
       other panel at whatever width the user chose. */
    .ea-wsx-grid { flex: 1 1 auto; display: grid; min-height: 0;
                  grid-template-columns: var(--ws-left, 200px) 1fr var(--ws-right, 240px) 46px; }
    .ea-wsx-left, .ea-wsx-right { background: var(--sunk); padding: 12px 11px;
                  overflow-y: auto; position: relative; }
    /* Drag handles sit ON the shared border, a few pixels wide, and only show
       themselves on hover so they do not add visual noise. */
    .ea-wsx-resize { position: absolute; top: 0; bottom: 0; width: 6px; cursor: col-resize;
                  z-index: 30; background: transparent; transition: background .12s; }
    .ea-wsx-resize.l { right: -3px; } .ea-wsx-resize.r { left: -3px; }
    .ea-wsx-resize:hover, .ea-wsx-resize.dragging { background: var(--forest); }
    body.ea-resizing { cursor: col-resize; user-select: none; }
    .ea-wsx-left { border-right: 1px solid var(--line); } .ea-wsx-right { border-left: 1px solid var(--line); }
    .ea-wsx-left h6, .ea-wsx-right h6 { font: 600 10px var(--mono); letter-spacing: .12em;
                  text-transform: uppercase; color: var(--bark); margin: 0 0 10px; }
    /* Canvas fills its column; its own scroll never clips the pop-out panels. */
    .ea-wsx-canvas { padding: 14px; min-width: 0; min-height: 0; background: var(--paper);
                  position: relative; display: flex; flex-direction: column; overflow: hidden; }
    .ea-wsx-canvas > .shiny-html-output { flex: 1 1 auto; min-height: 0; display: flex;
                  flex-direction: column; overflow: auto; }
    /* Map view: the leaflet map takes the free space, attribute dock sits under it. */
    .ea-wsx-canvas .leaflet, .ea-wsx-canvas .leaflet-container { flex: 1 1 auto; min-height: 240px; }
    /* Identify popup. Leaflet ships its own white bubble with dark text, which
       is a fixed light panel in exactly the sense gotcha 31 warns about -- it
       looked fine in light mode and unreadable on every dark set. Leaflet's CSS
       is loaded as a dependency, so these have to restate the component's own
       classes (gotcha 22) rather than rely on a token higher up. */
    .leaflet-popup-content-wrapper, .leaflet-popup-tip {
      background: var(--panel) !important; color: var(--ink) !important;
      box-shadow: 0 6px 22px rgba(0,0,0,.32);
    }
    .leaflet-popup-content-wrapper {
      border: 1px solid var(--line); border-radius: 10px;
    }
    .leaflet-popup-content {
      margin: 10px 12px; font: 400 12px var(--ui); color: var(--ink);
      max-height: 260px; overflow: auto;
    }
    .leaflet-popup-content b { color: var(--ink); }
    .leaflet-popup-content table { border-collapse: collapse; margin-top: 6px; }
    .leaflet-popup-content td { padding: 2px 0; vertical-align: top; }
    .leaflet-popup-content td:first-child {
      color: var(--bark); padding-right: 10px; white-space: nowrap;
    }
    /* The close button is the ONLY way out now that the popup is sticky, so it
       must be clearly visible rather than leaflet's faint grey on our panels. */
    .leaflet-container a.leaflet-popup-close-button {
      color: var(--bark) !important; font-size: 18px; padding: 6px 8px 0 0;
    }
    .leaflet-container a.leaflet-popup-close-button:hover {
      color: var(--ink) !important;
      background: color-mix(in srgb, var(--ink) 10%, transparent);
      border-radius: 0 10px 0 6px;
    }
    .ea-wsx-canvas .shiny-plot-output { flex: 0 0 auto; }
    /* Step 4: results dock + resizable pop-out mini-screens */
    .ea-wsx-dock { background: var(--sunk); border-left: 1px solid var(--line); padding: 11px 6px;
                  display: flex; flex-direction: column; align-items: center; gap: 8px; }
    .ea-wsx-dockhint { font: 500 8px var(--mono); text-transform: uppercase; letter-spacing: .1em;
                  color: var(--bark); writing-mode: vertical-rl; transform: rotate(180deg); opacity: .6; }
    .ea-wsx-dchip { width: 34px; min-height: 48px; border: 1px solid var(--line); border-radius: 9px;
                  background: var(--panel); display: flex; flex-direction: column; align-items: center;
                  justify-content: center; gap: 4px; cursor: pointer; padding: 6px 2px; }
    .ea-wsx-dchip:hover { border-color: var(--canopy); }
    .ea-wsx-dchip.open { border-color: var(--forest); box-shadow: 0 0 0 2px color-mix(in srgb, var(--forest) 30%, transparent); }
    .ea-wsx-dcw { width: 9px; height: 9px; border-radius: 3px; }
    .ea-wsx-dcl { font: 600 8px var(--mono); color: var(--bark); writing-mode: vertical-rl; transform: rotate(180deg); }
    /* Pop-out layer floats ABOVE the canvas content (and above leaflet's panes). */
    .ea-wsx-panels { position: absolute; inset: 0; pointer-events: none; overflow: visible; z-index: 900; }
    /* the uiOutput wrapper must span the layer so panels position/drag correctly */
    .ea-wsx-panels > .shiny-html-output { position: absolute; inset: 0; pointer-events: none; }
    .ea-wsx-panel { pointer-events: auto; }
    /* A migrated module's output panel is roomier — legacy canvases were built
       for a full-width screen, so give them space (and let the user resize). */
    .ea-wsx-panel-tool { width: min(70%, 760px) !important; height: min(74%, 560px) !important;
                  max-width: 96%; max-height: 92%; }
    .ea-wsx-panel-tool .ea-wsx-pb { padding: 8px 10px; }
    .ea-wsx-panel { position: absolute; z-index: 901;
                  width: 320px; height: 288px; min-width: 220px; min-height: 170px;
                  max-width: 600px; max-height: 560px; pointer-events: auto; resize: both; overflow: hidden;
                  display: flex; flex-direction: column; background: color-mix(in srgb, var(--panel) 84%, transparent);
                  backdrop-filter: blur(14px) saturate(1.2); -webkit-backdrop-filter: blur(14px) saturate(1.2);
                  border: 1px solid rgba(255,255,255,.14); border-radius: 12px; box-shadow: 0 20px 50px rgba(0,0,0,.5); }
    .ea-wsx-ph { display: flex; align-items: center; gap: 7px; padding: 8px 11px; border-bottom: 1px solid var(--line);
                  font-size: 12px; font-weight: 640; cursor: grab; flex: none; }
    .ea-wsx-px { margin-left: auto; display: flex; gap: 1px; }
    .ea-wsx-px button { border: none; background: transparent; color: var(--bark); cursor: pointer;
                  font: 600 14px var(--mono); padding: 0 5px; line-height: 1; }
    .ea-wsx-px button:hover { color: var(--ink); }
    .ea-wsx-pb { padding: 11px; flex: 1 1 auto; overflow: auto; display: flex; flex-direction: column; gap: 8px; }
    .ea-wsx-pb img { width: 100%; border-radius: 6px; border: 1px solid var(--line); display: block; }
    .ea-wsx-pmet { display: flex; flex-wrap: wrap; gap: 12px; font-size: 12px; }
    .ea-wsx-pmet span { display: flex; flex-direction: column; }
    .ea-wsx-pmet u { text-decoration: none; font: 600 8.5px var(--mono); text-transform: uppercase; color: var(--bark); }
    .ea-wsx-pmet b { font-family: var(--mono); }
    .ea-wsx-lyr { display: flex; align-items: center; gap: 8px; padding: 7px 9px; border: 1px solid var(--line);
                  border-radius: 7px; background: var(--panel); margin-bottom: 7px; font-size: 12.5px; }
    .ea-wsx-sw { width: 10px; height: 10px; border-radius: 3px; flex: none; }
    .ea-wsx-nm { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .ea-wsx-ty { margin-left: auto; font: 400 9px var(--mono); text-transform: uppercase; color: var(--bark); }
    .ea-wsx-mapnote, .ea-wsx-chartnote { border: 1px dashed var(--line); border-radius: 10px; padding: 16px;
                  color: var(--bark); font-size: 13px; line-height: 1.6; background: var(--panel); margin-bottom: 12px; }
    .ea-wsx-quick { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
    .ea-wsx-qtool { font: 550 11px var(--ui); background: var(--panel); border: 1px solid var(--line);
                  border-radius: 999px; padding: 5px 11px; color: var(--ink); }
    /* Step 2: layers panel — visibility, active, expandable legend/style */
    .ea-wsx-lyr2 { border: 1px solid var(--line); border-radius: 8px; background: var(--panel);
                  margin-bottom: 7px; overflow: hidden; }
    .ea-wsx-lyr2.active { border-color: var(--forest);
                  box-shadow: 0 0 0 1px color-mix(in srgb, var(--forest) 40%, transparent); }
    .ea-wsx-lyrtop { display: flex; align-items: center; gap: 7px; padding: 7px 8px; font-size: 12.5px; }
    /* layer visibility = toggle switch */
    .ea-wsx-sw-toggle { flex: none; width: 26px; height: 15px; border-radius: 999px;
                  background: var(--line); border: 1px solid var(--line); cursor: pointer;
                  position: relative; transition: background .14s, border-color .14s; }
    .ea-wsx-sw-toggle .knob { position: absolute; top: 1px; left: 1px; width: 11px; height: 11px;
                  border-radius: 50%; background: var(--bark); transition: transform .14s, background .14s; }
    .ea-wsx-sw-toggle.on { background: color-mix(in srgb, var(--forest) 45%, transparent);
                  border-color: var(--forest); }
    .ea-wsx-sw-toggle.on .knob { transform: translateX(11px); background: var(--canopy); }
    .ea-wsx-lyr2.off .ea-wsx-nm { opacity: .4; }
    .ea-wsx-lyrtop .ea-wsx-nm { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; cursor: pointer; }
    .ea-wsx-chev { cursor: pointer; color: var(--bark); font-size: 9px; flex: none; transition: transform .12s; }
    .ea-wsx-lyr2.exp .ea-wsx-chev { transform: rotate(90deg); }
    .ea-wsx-leg { display: none; padding: 2px 10px 10px; border-top: 1px solid var(--line); }
    .ea-wsx-lyr2.exp .ea-wsx-leg { display: block; }
    .ea-wsx-lgh { font: 600 8.5px var(--mono); text-transform: uppercase; letter-spacing: .08em; color: var(--bark); margin-top: 8px; }
    .ea-wsx-lgh2 { font-size: 11px; color: var(--bark); margin-top: 8px; }
    .ea-wsx-ramp { height: 9px; border-radius: 4px; margin-top: 6px;
                  background: linear-gradient(90deg, #2b4a2e, #5fbf62, #c9c56b, #d99b57); }
    .ea-wsx-ends { display: flex; justify-content: space-between; font: 400 9px var(--mono); color: var(--bark); margin-top: 3px; }
    .ea-wsx-style { display: flex; gap: 6px; margin-top: 6px; }
    /* raster render mode + RGB band mapping (layers panel) */
    .ea-wsx-rgbrow { display: flex; align-items: center; gap: 8px; margin-top: 6px; }
    .ea-wsx-rgblab { font-size: 11px; color: var(--ink); }
    .ea-wsx-rgbsel { display: flex; gap: 6px; margin-top: 6px; }
    .ea-wsx-rgbsel > div { flex: 1 1 0; min-width: 0; }
    .ea-wsx-rgbsel label { display: block; font: 600 8.5px var(--mono); color: var(--bark);
                           text-transform: uppercase; letter-spacing: .08em; margin-bottom: 2px; }
    .ea-wsx-note { font-size: 10.5px; line-height: 1.45; color: var(--bark);
                   background: var(--sunk); border: 1px solid var(--line);
                   border-radius: 6px; padding: 6px 8px; margin-top: 6px; }
    .ea-wsx-band { width: 100%; max-width: 100%; font-size: 11px; padding: 2px 4px;
                   background: var(--panel); color: var(--ink);
                   border: 1px solid var(--line); border-radius: 5px; }
    .ea-wsx-sc { width: 16px; height: 16px; border-radius: 4px; border: 1px solid var(--line); cursor: pointer; }
    .ea-wsx-symrow { display: flex; align-items: center; gap: 7px; font-size: 11px; color: var(--bark); margin-top: 6px; }
    /* Symbology controls in the layer expander. The colour input and range
       slider are BROWSER-DRAWN, so they follow `color-scheme` (gotcha 28)
       rather than any rule here -- which is why the app declares it per theme
       and these only need sizing. */
    .ea-wsx-col {
      width: 30px; height: 22px; padding: 0; border: 1px solid var(--line);
      border-radius: 5px; background: var(--panel); cursor: pointer;
    }
    .ea-wsx-rng { flex: 1 1 0; min-width: 0; accent-color: var(--forest); cursor: pointer; }
    .ea-wsx-vleg { margin-top: 5px; display: flex; flex-direction: column; gap: 3px; }
    .ea-wsx-vlegrow {
      display: flex; align-items: center; gap: 7px;
      font: 400 11px var(--ui); color: var(--bark);
    }
    /* A long category list must not push the layer row to full height. */
    .ea-wsx-vleg { max-height: 150px; overflow-y: auto; }
    .ea-wsx-sym { width: 13px; height: 13px; border-radius: 50%; flex: none; }
    /* Step 3: tool-panel host */
    .ea-wsx-toolhead { display: flex; align-items: center; gap: 8px; margin: 2px 0 12px;
                  padding-bottom: 11px; border-bottom: 1px solid var(--line); }
    .ea-wsx-toolg { font: 600 9px var(--mono); text-transform: uppercase; letter-spacing: .08em; color: var(--bark); }
    /* Step 5: Data-view chart builder */
    .ea-wsx-chartbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-bottom: 10px; }
    .ea-wsx-chartbar label { font: 600 9px var(--mono); text-transform: uppercase; letter-spacing: .08em;
                  color: var(--bark); margin: 0; }
    .ea-wsx-chartbar .form-group, .ea-wsx-chartbar .shiny-input-container { margin-bottom: 0 !important; }
    /* static <-> interactive plot toggle */
    .ea-wsx-cmode { display: inline-flex; margin-left: auto; border: 1px solid var(--line);
                  border-radius: 7px; overflow: hidden; }
    .ea-wsx-cmb { border: none; background: transparent; color: var(--bark);
                  font: 550 11.5px var(--ui); padding: 5px 11px; cursor: pointer; }
    .ea-wsx-cmb.on { background: var(--forest); color: var(--onbrand); }
    /* Data view: resizable plot / table split (drag the bar between them) */
    .ea-wsx-dsplit { flex: 1 1 auto; min-height: 0; display: flex; flex-direction: column; }
    .ea-wsx-dplot { flex: 0 0 300px; min-height: 90px; overflow: hidden; }
    .ea-wsx-dplot .shiny-plot-output { height: 100% !important; }
    .ea-wsx-dbar { flex: 0 0 10px; cursor: row-resize; position: relative; }
    .ea-wsx-dbar::before { content: ''; position: absolute; left: 0; right: 0; top: 4px; height: 2px;
                  background: var(--line); border-radius: 2px; transition: background .12s; }
    .ea-wsx-dbar:hover::before, .ea-wsx-dbar.dragging::before { background: var(--forest); height: 3px; }
    .ea-wsx-dtable { flex: 1 1 auto; min-height: 70px; overflow: auto; }
    .ea-wsx-tabledock { margin-top: 12px; border-top: 1px solid var(--line); padding-top: 10px; }
    .ea-wsx-tdh { font: 600 10px var(--mono); text-transform: uppercase; letter-spacing: .08em;
                  color: var(--bark); margin-bottom: 8px; }
    /* Step 6: Map-view attribute-table dock */
    .ea-wsx-maptop { display: flex; align-items: center; gap: 10px; margin-bottom: 8px; font-size: 13px; font-weight: 620; }
    .ea-wsx-mapsub { font: 400 11px var(--mono); color: var(--bark); }
    .ea-wsx-attrdock { margin-top: 12px; border: 1px solid var(--line); border-radius: 8px;
                  overflow: hidden; background: var(--panel); }
    .ea-wsx-attrhead { display: flex; align-items: center; gap: 8px; padding: 7px 10px;
                  border-bottom: 1px solid var(--line); font-size: 12px; cursor: ns-resize; background: var(--sunk); }
    .ea-wsx-attrmin { margin-left: auto; border: none; background: transparent; color: var(--bark);
                  cursor: pointer; font: 600 12px var(--mono); }
    /* Selection readout in the attribute dock header. The swatch is the same
       red the map draws the highlight in, so the count and the shapes on the
       map are visibly the same thing. Literal hex on purpose: it has to match a
       leaflet colour, which cannot read a CSS token (same exception as gotcha
       31's in-plot colours). */
    .ea-wsx-selinfo { display: inline-flex; align-items: center; gap: 6px; margin-left: 6px; }
    .ea-wsx-selcount {
      font: 600 11px var(--ui); color: var(--ink);
      background: color-mix(in srgb, #FF2D2D 20%, transparent);
      border: 1px solid color-mix(in srgb, #FF2D2D 55%, transparent);
      border-radius: 999px; padding: 1px 8px; white-space: nowrap;
    }
    .ea-wsx-selclear {
      border: 1px solid var(--line); background: var(--panel); color: var(--bark);
      border-radius: 5px; padding: 1px 7px; font: 500 11px var(--ui); cursor: pointer;
    }
    .ea-wsx-selclear:hover { border-color: var(--canopy); color: var(--forest); }
    /* Edit mode must LOOK armed — a destructive state that is invisible is how
       someone deletes from a layer they thought they were only viewing. */
    .ea-wsx-selclear.on {
      border-color: var(--warn); color: var(--ink);
      background: color-mix(in srgb, var(--warn) 22%, transparent);
    }
    .ea-wsx-seldel {
      border: 1px solid var(--danger); border-radius: 5px; padding: 1px 8px;
      font: 600 11px var(--ui); cursor: pointer;
      background: color-mix(in srgb, var(--danger) 16%, transparent);
      color: var(--ink);
    }
    .ea-wsx-seldel:hover { background: var(--danger); color: #fff; }
    /* Attribute table window controls (backlog item 52).
       The state lives on <html>, NOT on the dock element. The dock is built
       inside .map_ui(), so it is destroyed and rebuilt every time the map
       re-renders -- choosing a layer, toggling visibility, changing basemap.
       A class set on the dock itself is therefore lost at the first interaction,
       which is why the old collapse button kept springing back open. The root
       element survives all of it. Same reason the height is a variable there. */
    /* Drag handle for layer reordering (item 65). Its own grip zone on the left:
       the row already carries a visibility toggle, a name, a delete button and a
       context menu, so a whole-row drag would make all of them feel sticky. */
    .ea-wsx-grip { cursor: grab; color: var(--bark); font: 700 11px var(--mono);
                  padding: 0 3px; user-select: none; flex: 0 0 auto; opacity: .55; }
    .ea-wsx-grip:hover { opacity: 1; color: var(--forest); }
    .ea-wsx-grip:active { cursor: grabbing; }
    .ea-wsx-lyr2.dragging { opacity: .45; }
    .ea-wsx-lyr2.dropinto { outline: 2px dashed var(--forest); outline-offset: -2px; }
    /* ---- Plugin menu (item 74 phase 2) --------------------------------
       Every colour is a token: a fixed light panel looks right in one theme and
       keeps its cream background under light text on every dark set (gotcha 31). */
    /* Plugins is a DIALOG, not a screen (item 76b): the list scrolls inside the
       modal so the modal itself never grows past the viewport. */
    /* See-script control in every tool panel. Quiet by design: it is an escape
       hatch, not an action the screen is about. */
    .ea-wsx-scriptrow { margin-top: 14px; padding-top: 10px;
                  border-top: 1px solid var(--line); }
    .ea-wsx-scriptbtn { width: 100%; border: 1px solid var(--line); border-radius: 6px;
                  background: transparent; color: var(--bark); cursor: pointer;
                  font: 500 12px var(--ui); padding: 6px 10px; }
    .ea-wsx-scriptbtn:hover { border-color: var(--forest); color: var(--forest);
                  background: color-mix(in srgb, var(--forest) 8%, transparent); }
    /* See-script dialog (item 57): code in a modal. Monospace, scrollable and
       themed -- a fixed light code block is gotcha 31 at its most obvious. */
    .ea-script { font: 12px/1.55 var(--mono); white-space: pre; overflow: auto;
                  max-height: 55vh; margin: 0; padding: 12px 14px;
                  border: 1px solid var(--line); border-radius: 7px;
                  background: var(--sunk); color: var(--ink); }
    /* Provider badge on a generated tool's panel (item 77). Says whose engine is
       about to run, while the panel is open -- not only in the tool's name. */
    .ea-prov { display: inline-flex; align-items: center; gap: 7px; margin: 0 0 8px;
                  padding: 3px 9px; border-radius: 999px; font: 500 11px var(--ui);
                  border: 1px solid var(--line); color: var(--bark);
                  background: color-mix(in srgb, var(--forest) 8%, transparent); }
    .ea-prov-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--forest); }
    .ea-prov-nm { color: var(--ink); font-weight: 600; }
    .ea-prov-tool { font: 500 10.5px var(--mono); color: var(--bark); }
    .ea-plug-bar { display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
                  margin: 12px 0 8px; }
    .ea-plug-bar .form-group { margin-bottom: 0; }
    .ea-plug-bar > .form-group:first-child { flex: 1 1 220px; }
    .ea-plug-bar .shiny-options-group { display: flex; gap: 10px; }
    .ea-plug-scroll { max-height: 46vh; overflow-y: auto; padding-right: 4px; }
    .ea-plug-actions { display: flex; gap: 8px; align-items: center;
                  flex-wrap: wrap; margin-top: 12px; }
    .ea-plug-busy { font: 500 11.5px var(--mono); color: var(--bark); }
    .ea-plug-card { border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px;
                  background: var(--panel); margin: 0 0 14px; }
    .ea-plug-card.on { border-color: var(--forest);
                  background: color-mix(in srgb, var(--forest) 7%, var(--panel)); }
    .ea-plug-head { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
    .ea-plug-name { font: 600 16px var(--ui); color: var(--ink); }
    .ea-plug-pill { font: 600 11px var(--ui); padding: 2px 9px; border-radius: 999px;
                  border: 1px solid var(--line); color: var(--bark); }
    .ea-plug-pill.on { border-color: var(--forest); color: var(--ink);
                  background: color-mix(in srgb, var(--forest) 18%, transparent); }
    .ea-plug-desc { margin: 8px 0 4px; font-size: 13.5px; color: var(--ink); }
    .ea-plug-cred { margin: 0; font-size: 12px; color: var(--bark); }
    .ea-plug-cred a { color: var(--forest); }
    .ea-plug-warn { margin-top: 10px; padding: 8px 10px; border-radius: 6px;
                  font-size: 12.5px; color: var(--ink);
                  border: 1px solid var(--warn);
                  background: color-mix(in srgb, var(--warn) 16%, transparent); }
    .ea-plug-searchrow { display: flex; align-items: center; gap: 10px; margin-bottom: 8px; }
    .ea-plug-searchrow .form-group { flex: 1 1 auto; margin-bottom: 0; }
    .ea-plug-count { font: 500 12px var(--mono); color: var(--bark); white-space: nowrap; }
    .ea-plug-list { display: flex; flex-direction: column; gap: 6px; }
    .ea-plug-row { display: flex; gap: 11px; align-items: flex-start; padding: 9px 11px;
                  border: 1px solid var(--line); border-radius: 7px; background: var(--panel); }
    .ea-plug-row.on { border-color: var(--forest);
                  background: color-mix(in srgb, var(--forest) 6%, var(--panel)); }
    .ea-plug-txt { min-width: 0; }
    .ea-plug-tool { font: 600 13px var(--mono); color: var(--ink); }
    .ea-plug-box { font: 500 10.5px var(--ui); color: var(--bark); margin-left: 8px;
                  text-transform: uppercase; letter-spacing: .06em; }
    .ea-plug-sum { margin: 2px 0 0; font-size: 12.5px; color: var(--bark); }
    /* Same switch idiom as the layer visibility toggle, so it reads as the same
       kind of control rather than a new one. */
    .ea-plug-sw { flex: 0 0 auto; width: 34px; height: 19px; border-radius: 999px;
                  border: 1px solid var(--line); background: var(--sunk);
                  position: relative; cursor: pointer; padding: 0; margin-top: 1px; }
    .ea-plug-sw .knob { position: absolute; top: 2px; left: 2px; width: 13px; height: 13px;
                  border-radius: 50%; background: var(--bark); transition: left .14s; }
    .ea-plug-sw.on { background: color-mix(in srgb, var(--forest) 34%, transparent);
                  border-color: var(--forest); }
    .ea-plug-sw.on .knob { left: 17px; background: var(--forest); }
    @media (prefers-reduced-motion: reduce) { .ea-plug-sw .knob { transition: none; } }
    .ea-wsx-attrbtns { margin-left: auto; display: inline-flex; gap: 2px; }
    .ea-wsx-attrbtn { border: none; background: transparent; color: var(--bark);
                  cursor: pointer; font: 600 13px var(--mono); line-height: 1;
                  padding: 3px 7px; border-radius: 4px; }
    .ea-wsx-attrbtn:hover { background: var(--tint); color: var(--ink); }
    .ea-wsx-attrbtn.x:hover { background: var(--danger); color: #fff; }
    .ea-wsx-attrbody { max-height: var(--ea-attr-h, 220px); overflow: auto; padding: 4px 8px; }
    .ea-wsx-attrdock.collapsed .ea-wsx-attrbody,
    html.ea-attr-min .ea-wsx-attrbody { display: none; }
    html.ea-attr-closed .ea-wsx-attrdock { display: none; }
    /* Maximised: the cramped-strip problem the request was actually about.
       .ea-wsx-canvas is already position:relative, so inset works against it. */
    html.ea-attr-max .ea-wsx-attrdock {
      position: absolute; inset: 14px; z-index: 1200; margin: 0;
      display: flex; flex-direction: column;
      box-shadow: 0 10px 34px rgba(0,0,0,.30);
    }
    html.ea-attr-max .ea-wsx-attrbody { max-height: none; flex: 1 1 auto; }
    html.ea-attr-max .ea-wsx-attrhead { cursor: default; }
    html.ea-attr-min .ea-wsx-attrhead { cursor: default; }
    .ea-wsx-attrinfo { padding: 10px 4px; font: 400 12px var(--mono); color: var(--bark); }
    /* Step 7: a migrated module's real canvas embedded in the workspace centre */
    .ea-wsx-modcanvas { min-height: 100%; }
    /* The result area used to fill for a PLOT view and not for the others -- and
       measured, it was worse than that: the two failed in opposite directions.
       On Linear regression, in a 572px container, the card was 444 tall for
       'Model summary' (128px of dead space under it) and 704 tall for
       'Diagnostic plots' (overflowing the panel by 132px), because a solo plot
       carries a fixed pixel height from R while text panes size to their content.
       Make the single-card case a real flex chain so the card takes the height it
       is given, and the viewport absorbs what is left.
       :only-child on purpose -- screens that stack SEVERAL cards (ANOVA, Data &
       Exploration) must keep sizing to their content, or every card would stretch. */
    .ea-wsx-modcanvas { display: flex; flex-direction: column; }
    .ea-wsx-modcanvas > .card:only-child,
    .ea-wsx-modcanvas > div:only-child > .card:only-child {
                  flex: 1 1 auto; min-height: 0; }
    .ea-wsx-modcanvas .lm-viewport { flex: 1 1 auto; min-height: 0; overflow: auto; }
    /* A solo plot should fit the space rather than force a fixed 560px and scroll.
       The plot is a GRANDchild: .lm-viewport > uiOutput(.shiny-html-output) >
       plotOutput, so the wrapper needs a definite height before the plot's 100%
       can resolve against anything. Only when the plot IS the whole pane -- a
       split keeps each pane's own height. */
    .ea-wsx-modcanvas .lm-viewport > .shiny-html-output { height: 100%; }
    .ea-wsx-modcanvas .lm-viewport > .shiny-html-output > .shiny-plot-output:only-child {
                  height: 100% !important; }
    /* M6: R Console — bottom dock that slides up from the bottom of the workspace */
    /* NOTE: inside this flex chain a plain `height` gets compressed to ~1px, so
       the dock's size must be pinned with min-height (verified in-browser). */
    .ea-wsx-console { flex: none; height: 0; min-height: 0; overflow: hidden; background: var(--panel);
                  border-top: 1px solid var(--line); transition: min-height .18s ease;
                  display: flex; flex-direction: column; }
    .ea-wsx-console.open { height: 300px; min-height: 300px; }
    /* FLOATING: fixed takes it out of the flex column, so the workspace above
       reclaims the space instead of leaving a gap where the dock used to be. */
    .ea-wsx-console.open.float { position: fixed; left: 18vw; top: 16vh;
                  width: min(64vw, 900px); height: 46vh; min-height: 200px;
                  border: 1px solid var(--line); border-radius: 10px; overflow: hidden;
                  box-shadow: 0 18px 50px rgba(0,0,0,.45); z-index: 1200; transition: none; }
    .ea-wsx-console.open.float .ea-wsx-conh { cursor: move; }
    /* MINIMIZED: header bar only, still docked at the bottom. */
    .ea-wsx-console.open.min { height: auto; min-height: 0; }
    .ea-wsx-console.open.min .ea-wsx-conb { display: none; }
    .ea-wsx-console.open.min .ea-wsx-conh { cursor: default; }
    /* Only the buttons that apply to the current mode are shown. */
    .ea-wsx-console .con-dock { display: none; }
    .ea-wsx-console.float .con-dock, .ea-wsx-console.min .con-dock { display: inline-block; }
    .ea-wsx-console.float .con-float, .ea-wsx-console.min .con-float { display: none; }
    .ea-wsx-console.min .con-min { display: none; }
    .ea-wsx-conh { display: flex; align-items: center; gap: 8px; padding: 7px 12px; flex: none;
                  background: var(--sunk); border-bottom: 1px solid var(--line);
                  font: 600 11px var(--mono); letter-spacing: .08em; text-transform: uppercase;
                  color: var(--bark); cursor: ns-resize; }
    .ea-wsx-conh svg, .ea-wsx-conh .fa { color: var(--canopy); }
    .ea-wsx-conx { margin-left: auto; display: flex; align-items: center; gap: 2px; }
    .ea-wsx-conx button { border: none; background: transparent; color: var(--bark);
                  cursor: pointer; font: 600 15px var(--mono); line-height: 1; padding: 0 4px; }
    .ea-wsx-conx button:hover { color: var(--ink); }
    .ea-wsx-conb { flex: 1 1 auto; min-height: 0; overflow: auto; padding: 10px 12px; }
    @media (prefers-reduced-motion: reduce) { .ea-wsx-console { transition: none; } }
    /* Split view: Map | divider | Data, each pane collapsible, ratio draggable */
    .ea-wsx-split { display: flex; flex: 1 1 auto; min-height: 0; gap: 0; }
    .ea-wsx-sp { display: flex; flex-direction: column; min-width: 0; min-height: 0; overflow: hidden; }
    .ea-wsx-sp-map  { flex: 0 0 56%; }
    .ea-wsx-sp-data { flex: 1 1 auto; }
    .ea-wsx-sp.collapsed { flex: 0 0 34px !important; }
    .ea-wsx-sp.collapsed .ea-wsx-spb { display: none; }
    .ea-wsx-sph { display: flex; align-items: center; gap: 8px; padding: 5px 9px; background: var(--sunk);
                  border: 1px solid var(--line); border-radius: 7px 7px 0 0; font: 600 10px var(--mono);
                  letter-spacing: .1em; text-transform: uppercase; color: var(--bark); flex: none; }
    .ea-wsx-spmin { margin-left: auto; border: none; background: transparent; color: var(--bark);
                  cursor: pointer; font: 600 13px var(--mono); line-height: 1; }
    .ea-wsx-spmin:hover { color: var(--ink); }
    .ea-wsx-spb { flex: 1 1 auto; min-height: 0; display: flex; flex-direction: column; overflow: auto;
                  border: 1px solid var(--line); border-top: none; border-radius: 0 0 7px 7px; padding: 8px; }
    .ea-wsx-spb .leaflet, .ea-wsx-spb .leaflet-container { flex: 1 1 auto; min-height: 200px; }
    .ea-wsx-splitter { flex: 0 0 8px; cursor: col-resize; background: transparent; position: relative; }
    .ea-wsx-splitter::before { content: ''; position: absolute; inset: 0 3px; background: var(--line);
                  border-radius: 2px; transition: background .12s; }
    .ea-wsx-splitter:hover::before, .ea-wsx-splitter.dragging::before { background: var(--forest); }

    /* ===== PROJECTS SCREEN ===== */
    /* The Projects body is PRE-RENDERED into the first HTML (fast paint). When
       the session connects, Shiny re-runs the renderUI and briefly flags the
       node `recalculating`, which by default DIMS it -> a clear->dark->clear
       flash. Keep it fully opaque: the pre-rendered content stays put until the
       (identical) real render swaps in, so the transition is invisible. */
    /* (per-screen recalculating hack removed — see --shiny-fade-opacity above) */
    .ea-projects { padding: 22px 26px; }
    .ea-firstrun { max-width: 680px; margin: 8px auto; text-align: center; }
    .ea-firstrun h3 { font-weight: 650; letter-spacing: -.02em; margin-bottom: 6px; }
    .ea-firstrun .sub { color: var(--bark); margin-bottom: 22px; }
    .ea-firstrun-card {
      border: 2px dashed var(--line); border-radius: 12px; background: var(--sunk);
      padding: 38px 26px; display: flex; flex-direction: column;
      align-items: center; gap: 12px;
    }
    .ea-firstrun-card .big { font-size: 18px; font-weight: 650; }
    .ea-firstrun-card p { color: var(--bark); max-width: 46ch; margin: 0; }

    .ea-ws-head { display: flex; align-items: flex-end; justify-content: space-between;
                  gap: 14px; flex-wrap: wrap; margin-bottom: 18px; }
    .ea-ws-head h3 { font-weight: 650; letter-spacing: -.02em; margin: 0 0 2px; }
    .ea-ws-head p  { color: var(--bark); margin: 0; font-size: 14px; }
    .ea-sect { display: flex; align-items: baseline; gap: 10px; margin-bottom: 10px;
               font-size: 11px; font-weight: 600; letter-spacing: .12em;
               text-transform: uppercase; color: var(--bark); }
    .ea-sect .hint { margin-left: auto; text-transform: none; letter-spacing: 0;
                     font-weight: 400; font-size: 12px; }

    .ea-proj-grid { display: grid; gap: 12px;
                    grid-template-columns: repeat(auto-fill, minmax(215px, 1fr)); }
    .ea-proj { border: 1px solid var(--line); border-radius: 10px; background: var(--panel);
               cursor: pointer; transition: .15s; display: flex; flex-direction: column; }
    .ea-proj:hover { border-color: var(--canopy); transform: translateY(-2px);
                     box-shadow: 0 6px 18px rgba(16,21,15,.08); }
    .ea-proj.sel { border-color: var(--forest); box-shadow: 0 0 0 2px rgba(46,125,50,.25); }
    .ea-proj-body { padding: 13px 14px 10px; }
    .ea-proj-body .nm { font-weight: 600; font-size: 14px; margin-bottom: 2px;
                        overflow-wrap: anywhere; }
    .ea-proj-body .when { font-size: 11.5px; color: var(--bark); font-family: ui-monospace,Consolas,monospace; }
    .ea-proj-body .chips { display: flex; gap: 4px; flex-wrap: wrap; margin-top: 9px; }
    .ea-proj-body .chip { font-size: 9.5px; font-weight: 600; letter-spacing: .06em;
                          border: 1px solid var(--line); border-radius: 3px; padding: 2px 5px;
                          color: var(--bark); font-family: ui-monospace,Consolas,monospace; }
    .ea-proj-body .chip.empty { color: var(--bark); }
    .ea-proj-open { border-top: 1px solid var(--line); padding: 7px 14px;
                    font-size: 12px; font-weight: 600; }
    .ea-proj-open a { color: var(--forest); text-decoration: none; }

    .ea-tools-block { margin-bottom: 16px; }
    .ea-tools-block h6 { font-size: 11px; font-weight: 600; letter-spacing: .12em;
                         text-transform: uppercase; color: var(--bark); margin-bottom: 8px; }
    .ea-kv > div { display: flex; align-items: center; gap: 8px; padding: 6px 8px;
                   border: 1px solid var(--line); border-radius: 5px; background: var(--panel);
                   margin-bottom: 6px; font-size: 12.5px; }
    .ea-kv .num, .ea-kv .path { margin-left: auto; color: var(--bark);
                                font-family: ui-monospace,Consolas,monospace; font-size: 11px; }
    .ea-hint { border: 1px solid var(--line); border-radius: 6px; padding: 10px 11px;
               color: var(--bark); font-size: 12px; background: var(--panel); }

    /* ===== INSIDE A PROJECT (data-first entry) ===== */
    .ea-project { padding: 26px 30px; }
    .ea-np-head { margin-bottom: 18px; }
    .ea-np-head .kicker { font-size: 10px; font-weight: 600; letter-spacing: .14em;
                          text-transform: uppercase; color: var(--forest); margin-bottom: 5px;
                          font-family: ui-monospace,Consolas,monospace; }
    .ea-np-name { font-size: 28px; font-weight: 650; letter-spacing: -.025em;
                  margin: 0 0 6px; display: flex; align-items: center; gap: 11px;
                  flex-wrap: wrap; }
    .ea-rename { font-size: 11.5px !important; font-weight: 550; color: var(--bark) !important;
                 background: var(--panel) !important; border: 1px solid var(--line) !important;
                 border-radius: 5px !important; padding: 4px 10px !important; }
    .ea-rename:hover { border-color: var(--canopy) !important; color: var(--ink) !important; }
    .ea-np-head .sub { color: var(--bark); font-size: 14px; max-width: 60ch; margin: 0; }

    .ea-drop { border: 2px dashed var(--line); border-radius: 12px; background: var(--sunk);
               padding: 24px 22px; text-align: center; display: flex;
               flex-direction: column; align-items: center; gap: 11px; }
    .ea-drop .big { font-size: 16px; font-weight: 600; }
    .ea-drop .types { display: flex; flex-wrap: wrap; gap: 5px; justify-content: center; }
    .ea-drop .ty { font-size: 10.5px; font-weight: 500; border: 1px solid var(--line);
                   border-radius: 4px; padding: 4px 8px; color: var(--bark); background: var(--panel);
                   font-family: ui-monospace,Consolas,monospace; }
    .ea-drop-input { width: 100%; max-width: 420px; }
    .ea-drop-input .form-group, .ea-drop-input .shiny-input-container { margin-bottom: 0 !important; }
    .ea-drop-input.inline { max-width: 300px; }
    .ea-drop .samples { display: flex; align-items: center; gap: 7px; flex-wrap: wrap;
                        justify-content: center; font-size: 12.5px; color: var(--bark); }
    .ea-chipbtn { font-size: 12px !important; font-weight: 550; border-radius: 999px !important;
                  border: 1px solid var(--line) !important; background: var(--panel) !important;
                  color: var(--forest) !important; padding: 5px 13px !important; }
    .ea-chipbtn:hover { border-color: var(--canopy) !important; }

    .ea-typemap { display: grid; gap: 12px;
                  grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); }
    .ea-tm { border: 1px solid var(--line); border-radius: 8px; padding: 13px 14px; background: var(--panel); }
    .ea-tm .hd { display: flex; align-items: center; gap: 8px; margin-bottom: 7px;
                 font-size: 13px; }
    .ea-tm .hd .sw { width: 10px; height: 10px; border-radius: 2px; display: inline-block; }
    .ea-tm .hd .n { margin-left: auto; color: var(--bark); font-size: 11px;
                    font-family: ui-monospace,Consolas,monospace; }
    .ea-tm ul { margin: 0; padding-left: 16px; color: var(--bark); font-size: 12.5px; line-height: 1.7; }
    .ea-tm .none { color: var(--bark); font-size: 12px; font-style: italic; }
    .ea-loaded-chips { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 16px; }
    .ea-loaded-chips .chip { font-size: 11px; font-weight: 600; border: 1px solid var(--line);
                             border-radius: 999px; padding: 4px 11px; color: var(--forest);
                             background: var(--panel); }
    .ea-np-actions { display: flex; align-items: center; gap: 14px; flex-wrap: wrap;
                     margin-top: 18px; }
    /* Add-more-data wrapper (hidden fileInput trigger) sits inline with the other
       bar buttons. */
    .ea-addfile { display: inline-flex; align-items: center; }

    /* ===== SETTINGS DRAWER ===== */
    #settings-overlay {
      display: none; opacity: 0;
      position: fixed; inset: 0; z-index: 1049;
      background: rgba(0,0,0,.32);
      transition: opacity .22s ease;
    }
    #settings-panel {
      position: fixed; top: 0; right: -380px;
      width: 360px; height: 100vh; z-index: 1050;
      background: var(--panel);
      box-shadow: -4px 0 24px rgba(0,0,0,.18);
      transition: right .25s cubic-bezier(.4,0,.2,1);
      display: flex; flex-direction: column;
      font-size: 13px;
    }
    #settings-panel.open { right: 0; }
    .settings-header {
      background: var(--forest);
      background: linear-gradient(135deg, #2e7d32 0%, #1b5e20 100%);
      color: #fff; padding: 14px 16px;
      display: flex; align-items: center; justify-content: space-between;
      flex-shrink: 0; position: sticky; top: 0; z-index: 1;
    }
    .settings-header-title {
      display: flex; align-items: center; gap: 9px;
      font-size: 14px; font-weight: 600; letter-spacing: .2px;
    }
    .settings-close-btn {
      background: rgba(255,255,255,.18); border: none; color: #fff;
      border-radius: 6px; padding: 2px 10px; font-size: 18px; cursor: pointer;
      line-height: 1.3; transition: background .15s;
    }
    .settings-close-btn:hover { background: rgba(255,255,255,.32); }
    .settings-body {
      padding: 0; overflow-y: auto; flex: 1;
    }
    .settings-section {
      padding: 16px 18px;
      border-bottom: 1px solid var(--line);
    }
    .settings-section:last-child { border-bottom: none; }
    .settings-section-title {
      font-size: 10px; text-transform: uppercase; letter-spacing: 1.2px;
      color: var(--forest); font-weight: 700; margin: 0 0 12px 0;
    }
    .settings-section .form-label,
    .settings-section label { font-size: 12px !important; color: var(--bark); }
    .settings-section .form-control,
    .settings-section .form-select { font-size: 12px !important; }
    .settings-action-row { display: flex; gap: 8px; margin-bottom: 8px; }
    .settings-action-btn {
      flex: 1; background: var(--sunk); border: 1px solid var(--line);
      border-radius: 6px; padding: 7px 10px; font-size: 12px; cursor: pointer;
      display: flex; align-items: center; justify-content: center; gap: 6px;
      color: var(--bark); transition: background .14s, border-color .14s, color .14s;
    }
    .settings-action-btn:hover {
      background: var(--tint); border-color: var(--canopy); color: var(--forest);
    }
    .settings-action-btn .fa { font-size: 13px; }
    .settings-hint { font-size: 11px; color: var(--bark); margin: 0; }
    /* Theme picker. Two per row so the label stays readable; the swatch shows
       the set's own paper + brand colour, which is the only honest preview.
       Every colour here is a token so the picker itself re-themes (gotcha 31). */
    .set-theme-grid {
      display: grid; grid-template-columns: 1fr 1fr; gap: 6px; margin-bottom: 8px;
    }
    .set-theme-sw {
      display: flex; align-items: center; gap: 7px; text-align: left;
      background: var(--sunk); border: 1px solid var(--line); border-radius: 6px;
      padding: 6px 8px; font-size: 11.5px; color: var(--bark); cursor: pointer;
      transition: background .14s, border-color .14s, color .14s;
    }
    .set-theme-sw:hover { background: var(--tint); border-color: var(--canopy); color: var(--ink); }
    /* Selected state is applied by eaMarkTheme() on load, on open and on click:
       the server never knows which theme is active. */
    .set-theme-sw.on {
      border-color: var(--forest); color: var(--ink);
      background: color-mix(in srgb, var(--forest) 14%, transparent);
      box-shadow: inset 0 0 0 1px var(--forest);
    }
    .set-theme-chip {
      position: relative; flex: 0 0 auto; width: 20px; height: 20px;
      border-radius: 5px; border: 1px solid var(--line); display: block;
    }
    .set-theme-dot {
      position: absolute; right: -2px; bottom: -2px; width: 9px; height: 9px;
      border-radius: 50%; border: 1px solid var(--panel); display: block;
    }
    .set-theme-lbl { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .settings-flash { animation: setFlash 1.2s ease; }
    @keyframes setFlash { 0%, 100% { background: transparent; }
                          25% { background: color-mix(in srgb, var(--forest) 16%, transparent); } }
    /* Buttons: bslib bakes the dark palette into Bootstrap's own button vars,
       declared ON .btn, so the :root remap in the surfaces block cannot reach
       them (same root cause as the tables and accordions). */
    .btn { --bs-btn-bg: transparent; --bs-btn-color: var(--ink);
           --bs-btn-border-color: var(--line); --bs-btn-hover-color: var(--ink);
           --bs-btn-hover-bg: var(--sunk); --bs-btn-hover-border-color: var(--forest);
           --bs-btn-active-bg: var(--sunk); --bs-btn-active-color: var(--ink);
           --bs-btn-disabled-color: var(--bark); --bs-btn-disabled-bg: transparent; }
    .btn-success, .btn-primary { --bs-btn-bg: var(--forest); --bs-btn-color: var(--onbrand);
           --bs-btn-border-color: var(--forest); --bs-btn-hover-bg: var(--canopy);
           --bs-btn-hover-color: var(--onbrand); --bs-btn-hover-border-color: var(--canopy);
           --bs-btn-active-bg: var(--canopy); --bs-btn-active-color: var(--onbrand); }
    /* stated outright: this one is not a Bootstrap button and had no rule that
       survived the colour sets */
    .settings-action-btn { background-color: var(--sunk) !important; color: var(--ink) !important; }
    .settings-action-btn:hover { background-color: var(--tint) !important; color: var(--forest) !important; }
    /* Keyboard shortcut rows */
    .kbd-row {
      display: flex; align-items: center; justify-content: space-between;
      padding: 5px 0; border-bottom: 1px solid var(--line); font-size: 12px;
    }
    .kbd-row:last-child { border-bottom: none; }
    .kbd-keys { display: flex; align-items: center; gap: 3px; flex-shrink: 0; }
    kbd {
      background: var(--sunk); border: 1px solid var(--line); border-bottom-width: 2px;
      border-radius: 3px; padding: 1px 5px;
      font-size: 10px; font-family: ui-monospace, monospace; color: var(--bark);
    }
    .kbd-desc { color: var(--bark); }
    /* About block */
    .about-logo-mark {
      display: inline-flex; align-items: center; justify-content: center;
      width: 36px; height: 36px; border-radius: 8px;
      background: var(--forest); color: var(--onbrand);
      font-size: 16px;   /* holds the lightbulb app icon */
      margin-bottom: 8px;
    }
    .about-name { font-size: 15px; font-weight: 700; color: var(--forest); }
    .about-version {
      display: inline-block; background: var(--tint); color: var(--forest);
      font-size: 10px; font-weight: 600; padding: 1px 7px;
      border-radius: 10px; margin-left: 6px; vertical-align: middle;
    }
    .about-tagline { font-size: 12px; color: var(--bark); margin: 4px 0 10px; }
    .about-tech { display: flex; flex-wrap: wrap; gap: 5px; margin-top: 8px; }
    .about-tech span {
      background: var(--sunk); color: var(--bark); font-size: 11px;
      padding: 2px 8px; border-radius: 10px;
    }

    /* ===== FEATURED RECOMMEND BUTTON ===== */
    .app-topbar .nav-link.app-menu.rec-featured {
      background: rgba(255,255,255,.15);
      color: #fff !important;
      border: 1px solid rgba(255,255,255,.45);
      border-radius: 12px;
      padding: 0 12px;
      font-weight: 700;
      margin: 5px 8px;
      letter-spacing: .25px;
      transition: background .15s, box-shadow .15s;
      animation: recGlow 4s ease-in-out infinite;
    }
    .app-topbar .nav-link.app-menu.rec-featured:hover {
      background: rgba(255,255,255,.28) !important;
      border-color: rgba(255,255,255,.7) !important;
      animation: none;
    }
    @keyframes recGlow {
      0%, 100% { box-shadow: none; border-color: rgba(255,255,255,.45); }
      50% { box-shadow: inset 0 0 6px rgba(255,255,255,.18), 0 0 6px rgba(255,255,255,.15); border-color: rgba(255,255,255,.7); }
    }

    /* ===== GLOBAL PLOT DOWNLOAD OVERLAY ===== */
    .shiny-plot-output { position: relative; }
    .plot-dl-btn {
      position: absolute; top: 6px; right: 6px; z-index: 20;
      background: rgba(255,255,255,.88); border: 1px solid var(--line);
      border-radius: 4px; padding: 3px 8px; font-size: 11px;
      cursor: pointer; color: var(--bark); display: none;
      transition: background .1s, border-color .1s, color .1s;
      line-height: 1.4;
    }
    .shiny-plot-output:hover .plot-dl-btn { display: inline-block; }
    .plot-dl-btn:hover { background: var(--tint); border-color: var(--canopy); color: var(--forest); }

    /* ==================================================================
       DARK SURFACES — applied last so these win over the older light
       rules above. Everything here is expressed in tokens; to retheme the
       app, change :root at the top of this block and nothing else.
       ================================================================== */
    .app-topbar { background: var(--bar); color: var(--ink);
                  border-bottom: 1px solid var(--line); }
    .app-topbar .brand, .app-topbar .app-menu, .app-topbar a { color: var(--ink); }
    .app-menu:hover, .app-topbar .nav > li:hover > a { background: rgba(255,255,255,.10); }
    .dropdown-menu { background: var(--panel); border: 1px solid var(--line); }
    .dropdown-item { color: var(--ink); }
    .dropdown-item:hover, .dropdown-item:focus { background: var(--tint); color: var(--ink); }

    .app-left, .app-right { background: var(--sunk); color: var(--ink);
                            border-color: var(--line) !important; }
    .app-left h6, .app-right h6 { color: var(--bark); }
    .app-center { background: var(--paper); }
    .app-divider { background: var(--line); }
    .app-status { background: var(--sunk); border-top: 1px solid var(--line);
                  color: var(--bark); font-family: var(--mono); font-size: 11.5px; }
    .app-status .sep { color: var(--line); }

    /* dataset rail items */
    .ds-item { background: var(--panel); border: 1px solid var(--line); color: var(--ink); }
    .ds-item:hover { border-color: var(--canopy); }
    .ds-item.active { background: var(--forest); border-color: var(--forest); color: var(--onbrand); }

    /* bslib cards + tabs */
    .card, .bslib-card { background: var(--panel); border-color: var(--line); }
    .card-header { background: var(--tint); border-color: var(--line); color: var(--ink); }
    .nav-tabs { border-color: var(--line); }
    .nav-tabs .nav-link { color: var(--bark); }
    .nav-tabs .nav-link.active { background: var(--panel); border-color: var(--line) var(--line) var(--panel);
                                 color: var(--ink); }

    /* ===== Result text: <pre>, <code>, .well =====================
       Bootstrap colours all three from --bs-emphasis-color-rgb, which theme.R
       now sets per palette. These restate background and border too, because
       bootstrap derives the background from the SAME triplet at 4% alpha --
       which on a dark set is a barely-visible wash rather than a panel. */
    pre, .well {
      color: var(--ink); background: var(--sunk);
      border: 1px solid var(--line); border-radius: 8px;
    }
    pre code, code { background: transparent; }
    code { color: var(--canopy); }

    /* ===== Sub-panel inside a tool sidebar ==========================
       Replaces the inline `background-color:#f8f9fa` / `#fff8e1` blocks that
       several modules hand-rolled. Those were fixed LIGHT surfaces, so on a
       dark theme they kept a cream background while the app's light text ran
       across them -- unreadable, and the reason the Convergence Options and
       Quick Builder panels were reported. The warn variant is a translucent
       TINT of the semantic colour, so it takes its lightness from whatever is
       behind it and works on every set (same approach as round-1 item 10). */
    .ea-subpanel {
      background: var(--sunk); border: 1px solid var(--line);
      border-radius: 6px; padding: 10px; color: var(--ink);
    }
    .ea-subpanel-warn {
      background: color-mix(in srgb, var(--warn) 14%, transparent);
      border-color: color-mix(in srgb, var(--warn) 38%, transparent);
    }
    .ea-subpanel .form-label, .ea-subpanel label, .ea-subpanel strong,
    .ea-subpanel p { color: var(--ink); }
    .ea-subpanel .text-muted { color: var(--bark) !important; }

    /* The formula strip above a model's results. Four modules carried the class
       but styled it inline with a fixed #e9ecef, so it never followed a theme. */
    .formula-box {
      padding: 8px 10px; background: var(--sunk); color: var(--ink);
      border-bottom: 1px solid var(--line);
      font-family: var(--mono); font-size: 12px;
    }

    /* Row flags in the data/profile tables. Translucent tints of the semantic
       colour rather than fixed pastels, so the row takes its lightness from the
       surface behind it and stays legible on every set (round-1 item 10). */
    .ea-row-warn { background: color-mix(in srgb, var(--warn) 14%, transparent); }
    .ea-row-flat { background: color-mix(in srgb, var(--danger) 12%, transparent); }

    /* form controls */
    .form-control, .form-select, .selectize-input, textarea {
      background: var(--sunk) !important; color: var(--ink) !important;
      border-color: var(--line) !important; }
    .selectize-dropdown, .selectize-dropdown .option, .selectize-dropdown-content,
    .selectize-input .item {
      background: var(--panel) !important; color: var(--ink) !important;
      border-color: var(--line) !important; }
    .selectize-dropdown .active, .selectize-dropdown .option.active,
    .selectize-dropdown .option:hover {
      background: var(--sunk) !important; color: var(--ink) !important; }
    /* NATIVE <select> popups. The rules above are all selectize (which renders
       divs); a plain selectInput(selectize = FALSE) renders a real <select>,
       whose option list selectize CSS never touches. `color-scheme` in theme.R
       is the portable half of this fix -- these two rules are the other half,
       for engines that do let the page colour an <option> (Chromium on Windows
       does; Firefox/Safari largely ignore them, which is exactly why
       color-scheme has to carry the load rather than these). */
    .form-select option, select.form-control option {
      background-color: var(--panel); color: var(--ink); }
    .form-control::placeholder { color: var(--bark); }
    /* ===== Glassy popups — a frosted translucent panel over a blurred, dark
       backdrop. Never the white-ish default. ===== */
    .modal-content {
      background: color-mix(in srgb, var(--panel) 78%, transparent);
      -webkit-backdrop-filter: blur(18px) saturate(1.3);
      backdrop-filter: blur(18px) saturate(1.3);
      color: var(--ink);
      font-family: var(--mono);   /* brand typewriter/code vibe in popups */
      border: 1px solid rgba(255,255,255,.14);
      border-radius: 14px;
      box-shadow: 0 24px 64px rgba(0,0,0,.55);
    }
    .modal-title { font-family: var(--mono); letter-spacing: -.01em; }
    .modal-header, .modal-footer { border-color: var(--line); }
    /* Backdrop: subtle dark dim + blur of the page behind — not white. */
    .modal-backdrop, .modal-backdrop.show {
      background-color: rgba(6,10,6,.45);
      opacity: 1 !important;
      -webkit-backdrop-filter: blur(4px);
      backdrop-filter: blur(4px);
    }
    .modal-content pre { background: var(--sunk); color: var(--ink);
                         border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; }
    .modal-content .btn-close { filter: invert(1) grayscale(1) brightness(1.6); }
    /* Popups sit vertically centred, not pinned to the top. */
    .modal-dialog { display: flex; align-items: center; min-height: calc(100% - 3.5rem); }

    /* rhandsontable grid (New dataset modal) in dark */
    .handsontable { color: var(--ink); font-family: var(--ui); }
    .handsontable th { background: var(--tint) !important; color: var(--bark) !important;
                       border-color: var(--line) !important; }
    .handsontable td { background: var(--panel) !important; color: var(--ink) !important;
                       border-color: var(--line) !important; }
    .handsontable .htDimmed { color: var(--bark) !important; }
    .handsontableInput { background: var(--sunk) !important; color: var(--ink) !important; }
    .handsontable tbody th.ht__highlight,
    .handsontable thead th.ht__highlight { background: var(--forest) !important; color: var(--onbrand) !important; }

    /* rounded frame around the Plot-Relationships (EDA) plot area */
    .ea-eda-frame { border: 1px solid var(--line); border-radius: 14px; padding: 12px;
                    background: var(--panel); }
    .ea-eda-frame .shiny-plot-output img { border-radius: 10px; }

    /* ---- Projects screen ---- */
    .ea-firstrun .sub { color: var(--bark); }
    .ea-firstrun-card { border: 2px dashed var(--line); background: var(--sunk); }
    .ea-firstrun-card p { color: var(--bark); }
    .ea-sect { color: var(--bark); }
    .ea-proj { background: var(--panel); border-color: var(--line); }
    .ea-proj:hover { border-color: var(--canopy); box-shadow: 0 6px 20px rgba(0,0,0,.35); }
    .ea-proj.sel { border-color: var(--forest);
                   box-shadow: 0 0 0 2px color-mix(in srgb, var(--forest) 35%, transparent); }
    .ea-proj-body .when { color: var(--bark); font-family: var(--mono); }
    .ea-proj-body .chip { border-color: var(--line); color: var(--bark); font-family: var(--mono); }
    .ea-proj-open { border-top: 1px solid var(--line); display: flex; gap: 12px;
                    align-items: center; }
    .ea-proj-open a { color: var(--canopy); text-decoration: none; }
    .ea-proj-open a.go { font-weight: 650; margin-right: auto; }
    .ea-proj-open a.muted { color: var(--bark); font-weight: 500; font-size: 11.5px; }
    .ea-proj-open a.muted:hover { color: var(--ink); }
    .ea-proj-open a.danger:hover { color: var(--danger); }
    /* Give the landing canvas room to breathe now that it is full width. */
    .app-main.view-projects .ea-projects { max-width: 1060px; margin: 0 auto;
                                           padding: 0 26px 34px; }

    /* --- slim bar above the canvas (where you are + what this page is for) --- */
    .ea-page-bar { display: flex; align-items: center; gap: 10px; flex-wrap: wrap;
                   padding: 11px 0 13px; margin-bottom: 20px;
                   border-bottom: 1px solid var(--line); }
    .ea-page-bar .where { font-family: var(--mono); font-size: 12px; color: var(--bark);
                          letter-spacing: .04em; }
    .ea-page-bar .acts { margin-left: auto; display: flex; gap: 7px; }
    .ea-barbtn { font-size: 11.5px !important; font-weight: 550 !important;
                 background: var(--panel) !important; border: 1px solid var(--line) !important;
                 color: var(--ink) !important; border-radius: 5px !important;
                 padding: 6px 12px !important; }
    .ea-barbtn:hover { border-color: var(--canopy) !important; }
    .ea-barbtn.go { background: var(--forest) !important; border-color: var(--forest) !important;
                    color: var(--onbrand) !important; }
    .ea-barbtn.danger { color: var(--bark) !important; }
    .ea-barbtn.danger:hover { color: var(--danger) !important;
                              border-color: var(--danger) !important; }
    .ea-page-bar .where.back { text-decoration: none; cursor: pointer; }
    .ea-page-bar .where.back:hover { color: var(--ink); }
    /* the bar sits at the very top of the project header block */
    .ea-np-head .ea-page-bar { margin-bottom: 18px; }

    /* --- first-run card: mockup proportions --- */
    .ea-firstrun { max-width: 700px; margin: 10px auto 0; text-align: center; }
    .ea-firstrun h3 { font-size: 22px; font-weight: 650; letter-spacing: -.02em;
                      margin-bottom: 6px; }
    .ea-firstrun .sub { font-size: 13.5px; margin-bottom: 22px; }
    .ea-firstrun-card { border-radius: 11px; padding: 44px 26px; gap: 13px; }
    .ea-firstrun-card .big { font-size: 18px; font-weight: 650; }
    .ea-firstrun-card p { font-size: 13.5px; max-width: 50ch; line-height: 1.55; }
    .ea-cta { font-weight: 600 !important; padding: 11px 22px !important;
              border-radius: 7px !important; color: var(--onbrand) !important; }

    /* --- the create-project view (large modal) --- */
    .modal-lg { max-width: 760px; }
    .ea-newproj { padding: 14px 18px 6px; }
    .ea-newproj .kicker { font-family: var(--mono); font-size: 10px; letter-spacing: .14em;
                          text-transform: uppercase; color: var(--forest); margin-bottom: 7px; }
    .ea-newproj h2 { font-size: 27px; font-weight: 650; letter-spacing: -.025em; margin: 0 0 8px; }
    .ea-newproj .sub { color: var(--bark); font-size: 14px; max-width: 58ch; margin: 0 0 24px;
                       line-height: 1.55; }
    .ea-newproj .field { margin-bottom: 22px; }
    .ea-newproj .field label { font-family: var(--mono); font-size: 10.5px; letter-spacing: .1em;
                               text-transform: uppercase; color: var(--bark); margin-bottom: 6px;
                               display: block; }
    .ea-newproj .field .form-control { font-size: 17px !important; padding: 12px 14px !important;
                                       border-radius: 8px !important; }
    .ea-newproj .field .form-control:focus { border-color: var(--forest) !important;
                                             box-shadow: 0 0 0 3px rgba(95,191,98,.18) !important; }
    .ea-newproj-what { display: grid; gap: 12px; margin-bottom: 26px;
                       grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); }
    .ea-newproj-what .w { border-left: 2px solid var(--forest); padding: 2px 0 2px 12px; }
    .ea-newproj-what .t { font-size: 13px; font-weight: 600; margin-bottom: 3px; }
    .ea-newproj-what .d { font-size: 12.5px; color: var(--bark); line-height: 1.45; }
    .ea-newproj-foot { display: flex; justify-content: flex-end; align-items: center; gap: 10px;
                       border-top: 1px solid var(--line); padding-top: 16px; }
    .ea-locpick { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
    .ea-locpick .val { font-family: var(--mono); font-size: 11.5px; color: var(--ink);
                       background: var(--sunk); border: 1px solid var(--line); border-radius: 5px;
                       padding: 7px 10px; flex: 1 1 240px; word-break: break-all; min-width: 0; }
    .ea-locpick-hint { font-size: 11.5px; color: var(--bark); margin-top: 6px; }
    .ea-hidden-file { position: absolute; width: 0; height: 0; overflow: hidden;
                      opacity: 0; pointer-events: none; }

    /* ===== GUIDED TOUR (spotlight) ===== */
    #ea-tour { position: fixed; inset: 0; z-index: 3000; display: none; }
    #ea-tour.on { display: block; }
    #ea-tour-spot { position: absolute; border-radius: 8px; pointer-events: none;
                    box-shadow: 0 0 0 9999px rgba(6,10,6,.72); outline: 2px solid var(--canopy);
                    transition: all .28s cubic-bezier(.4,0,.2,1); }
    #ea-tour-tip { position: absolute; width: 288px; background: var(--panel);
                   border: 1px solid var(--line); border-radius: 10px;
                   box-shadow: 0 16px 40px rgba(0,0,0,.45); padding: 15px 16px;
                   transition: all .28s cubic-bezier(.4,0,.2,1); }
    #ea-tour-tip .sc { font-family: var(--mono); font-size: 9.5px; letter-spacing: .12em;
                       text-transform: uppercase; color: var(--forest); margin-bottom: 6px; }
    #ea-tour-tip .ti { font-size: 15px; font-weight: 650; margin-bottom: 5px; color: var(--ink); }
    #ea-tour-tip .bd { font-size: 13px; color: var(--bark); line-height: 1.5; margin-bottom: 13px; }
    #ea-tour-tip .ft { display: flex; align-items: center; gap: 8px; }
    #ea-tour-tip .dots { display: flex; gap: 5px; margin-right: auto; }
    #ea-tour-tip .dots i { width: 6px; height: 6px; border-radius: 50%; background: var(--line); }
    #ea-tour-tip .dots i.on { background: var(--forest); }
    #ea-tour-tip button { font-size: 12.5px; font-weight: 550; border-radius: 6px;
                          padding: 7px 14px; cursor: pointer; border: 1px solid var(--line);
                          background: var(--panel); color: var(--bark); }
    #ea-tour-tip button:hover { border-color: var(--canopy); color: var(--ink); }
    #ea-tour-tip button.pri { background: var(--forest); border-color: var(--forest);
                              color: var(--onbrand); }
    @media (prefers-reduced-motion: reduce) {
      #ea-tour-spot, #ea-tour-tip { transition: none; }
    }
    .ea-tools-block h6 { color: var(--bark); font-family: var(--mono); }
    /* Help panel buttons — quiet app style (no bootstrap outline pills). */
    .ea-help-btn { display: flex; align-items: center; gap: 9px; width: 100%;
                   background: var(--panel); border: 1px solid var(--line); color: var(--ink);
                   border-radius: 6px; padding: 9px 11px; font-size: 12.5px; font-weight: 500;
                   text-align: left; margin-bottom: 6px; cursor: pointer; }
    .ea-help-btn:hover { border-color: var(--canopy); }
    .ea-help-btn:last-child { margin-bottom: 0; }
    .ea-help-btn svg, .ea-help-btn .fa { color: var(--bark); width: 15px; }
    .ea-kv > div { background: var(--panel); border-color: var(--line); color: var(--ink); }
    .ea-kv .num, .ea-kv .path { color: var(--bark); font-family: var(--mono); }
    .ea-hint { background: var(--panel); border-color: var(--line); color: var(--bark); }
    .ea-loc { margin-top: 8px; }
    .ea-loc .lab { font-family: var(--mono); font-size: 9.5px; letter-spacing: .1em;
                   text-transform: uppercase; color: var(--bark); margin-bottom: 3px; }
    .ea-loc .val { font-family: var(--mono); font-size: 10.5px; color: var(--ink);
                   background: var(--sunk); border: 1px solid var(--line); border-radius: 4px;
                   padding: 6px 8px; word-break: break-all; line-height: 1.4; }
    .ea-ws-head p { color: var(--bark); }

    /* ---- Inside a project ---- */
    .ea-np-head .kicker { color: var(--forest); font-family: var(--mono); }
    .ea-np-head .sub { color: var(--bark); }
    /* Compact project meta line (created / last opened) — small, mono, quiet. */
    .ea-np-meta { font: 400 11px var(--mono); color: var(--bark); letter-spacing: .02em;
                  margin: 3px 0 0; }
    /* Small file cards in the centre — one per file in the project. */
    .ea-filecards { display: grid; gap: 9px;
                    grid-template-columns: repeat(auto-fill, minmax(158px, 1fr)); }
    .ea-fcard { display: flex; align-items: center; gap: 9px; padding: 9px 11px;
                border: 1px solid var(--line); border-radius: 9px; background: var(--panel); }
    .ea-fcard-dot { width: 10px; height: 10px; border-radius: 3px; flex: 0 0 auto; }
    .ea-fcard-body { min-width: 0; }
    .ea-fcard-nm { font-size: 12.5px; font-weight: 600; color: var(--ink);
                   overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .ea-fcard-ty { font: 400 9.5px var(--mono); color: var(--bark);
                   text-transform: uppercase; letter-spacing: .08em; margin-top: 1px; }
    /* remove-file button: quiet until you hover the card, red on hover */
    .ea-fcard-x { margin-left: auto; flex: none; border: 1px solid transparent;
                  background: transparent; color: var(--bark); cursor: pointer;
                  font: 600 15px var(--mono); line-height: 1; padding: 1px 7px;
                  border-radius: 6px; opacity: 0; transition: opacity .12s, color .12s; }
    .ea-fcard:hover .ea-fcard-x, .ea-fcard-x:focus { opacity: 1; }
    .ea-fcard-x:hover { color: var(--danger); border-color: var(--danger); }
    /* same, in the workspace layers panel */
    .ea-wsx-del { flex: none; cursor: pointer; color: var(--bark); font: 600 14px var(--mono);
                  line-height: 1; padding: 0 4px; border-radius: 5px; opacity: 0;
                  transition: opacity .12s, color .12s; }
    .ea-wsx-lyr2:hover .ea-wsx-del { opacity: 1; }
    .ea-wsx-del:hover { color: var(--danger); }
    .ea-rename { background: var(--panel) !important; border-color: var(--line) !important;
                 color: var(--bark) !important; }
    .ea-rename:hover { border-color: var(--canopy) !important; color: var(--ink) !important; }
    .ea-drop { border: 2px dashed var(--line); background: var(--sunk); }
    .ea-drop .ty { background: var(--panel); border-color: var(--line); color: var(--bark);
                   font-family: var(--mono); }
    .ea-drop .samples { color: var(--bark); }
    .ea-chipbtn { background: var(--panel) !important; border-color: var(--line) !important;
                  color: var(--canopy) !important; }
    .ea-chipbtn:hover { border-color: var(--canopy) !important; }
    .ea-tm { background: var(--panel); border-color: var(--line); }
    .ea-tm ul { color: var(--bark); }
    .ea-tm .none { color: var(--bark); }
    .ea-tm .hd .n { color: var(--bark); font-family: var(--mono); }
    .ea-loaded-chips .chip { background: var(--panel); border-color: var(--line);
                             color: var(--canopy); }

    /* file input (Shiny renders its own button + text field) */
    .ea-drop-input .form-control { background: var(--sunk) !important; }
    .ea-drop-input .btn-file, .ea-drop-input .input-group-btn .btn {
      background: var(--forest) !important; border-color: var(--forest) !important;
      color: #08120A !important; }
    .progress { background: var(--line); }
    ")),

    tags$script(HTML("
      /* Per-view chrome. 'projects' = landing (no rails at all); 'project' =
         inside a project (no data rail — the canvas already has the drop zone).
         The initial class ships in the markup, so this only handles changes. */
      Shiny.addCustomMessageHandler('ea-view', function(v){
        var m = document.querySelector('.app-main');
        if (m) {
          m.classList.toggle('view-projects', v === 'projects');
          m.classList.toggle('view-project',  v === 'project');
          m.classList.toggle('view-workspace', v === 'workspace');
        }
        // Menubar + search + Undo/Reset only inside the workspace (any analysis
        // view). Projects landing and the project Overview stay menu-free.
        // 'on-projects' additionally hides Co-Analyst on the welcome-back page.
        var tb = document.querySelector('.app-topbar');
        if (tb) {
          tb.classList.toggle('menufree', v === 'projects' || v === 'project');
          tb.classList.toggle('on-projects', v === 'projects');
        }
      });
      /* Workspace Map/Data tab: toggle the .on class client-side (the click also
         sets input$wsview, which swaps the canvas server-side). */
      /* The view tabs are rendered from wsview() on the server now, so the old
         client-side highlighter is gone: two sources of truth for which tab is
         lit is exactly how the tab and the view came to disagree. */
      /* Workspace pop-out mini-screens: drag by the header (client-side; CSS handles resize). */
      document.addEventListener('mousedown', function(e){
        var ph = e.target.closest ? e.target.closest('.ea-wsx-ph') : null;
        if (!ph || e.target.tagName === 'BUTTON') return;
        var panel = ph.closest('.ea-wsx-panel'); if (!panel) return;
        var host = panel.closest('.ea-wsx-panels') || panel.parentNode;
        var pr = panel.getBoundingClientRect(), hr = host.getBoundingClientRect();
        var sx = e.clientX, sy = e.clientY, ol = pr.left - hr.left, ot = pr.top - hr.top;
        panel.style.left = ol + 'px'; panel.style.top = ot + 'px';
        panel.style.zIndex = 950;
        function mv(ev){ var hb = host.getBoundingClientRect();
          panel.style.left = Math.max(0, Math.min(hb.width - 90,  ol + ev.clientX - sx)) + 'px';
          panel.style.top  = Math.max(0, Math.min(hb.height - 30, ot + ev.clientY - sy)) + 'px'; }
        function up(){ document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up); e.preventDefault();
      });
      /* The Projects screen is PRE-RENDERED into the first HTML, so a click can
         land before the websocket is up — the input would be set and lost, which
         is why the first click on a project card appeared to do nothing and only
         a second click worked. Queue it until Shiny is connected. */
      window.eaSetInput = function(id, value){
        var send = function(){ Shiny.setInputValue(id, value, {priority: 'event'}); };
        if (window.Shiny && Shiny.shinyapp && Shiny.shinyapp.$socket &&
            Shiny.shinyapp.$socket.readyState === 1) { send(); }
        else { $(document).one('shiny:connected', function(){ setTimeout(send, 30); }); }
      };
      /* Fly-out submenus: flip to the left if they would overflow the window. */
      document.addEventListener('mouseover', function(e){
        var it = e.target.closest ? e.target.closest('.gm-item.has-sub') : null;
        if (!it) return;
        var sub = it.querySelector('.gm-sub'); if (!sub) return;
        sub.classList.remove('flip'); sub.style.top = '-7px';
        var r = sub.getBoundingClientRect();
        if (r.right > window.innerWidth - 8) sub.classList.add('flip');
        /* if it would run past the bottom, slide it UP so it fits — a desktop
           menu repositions rather than growing an inner scrollbar */
        var over = r.bottom - (window.innerHeight - 10);
        if (over > 0) sub.style.top = (-7 - over) + 'px';
      });
      /* GeoLibre menubar: click outside or press Escape to close any open menu.
         (Opening/closing on click is handled inline on each .gm-btn.) */
      document.addEventListener('click', function(e){
        if (e.target.closest && e.target.closest('.gm')) return;
        document.querySelectorAll('.gm.open').forEach(function(x){ x.classList.remove('open'); });
      });
      document.addEventListener('keydown', function(e){
        if (e.key === 'Escape')
          document.querySelectorAll('.gm.open').forEach(function(x){ x.classList.remove('open'); });
      });
      /* Workspace SPLIT view: drag the divider to set the map/data ratio. */
      document.addEventListener('mousedown', function(e){
        var sp = e.target.closest ? e.target.closest('.ea-wsx-splitter') : null;
        if (!sp) return;
        var wrap = sp.parentNode, left = sp.previousElementSibling;
        var wr = wrap.getBoundingClientRect(), sx = e.clientX, sw = left.getBoundingClientRect().width;
        sp.classList.add('dragging');
        function mv(ev){
          var w = Math.max(140, Math.min(wr.width - 160, sw + ev.clientX - sx));
          left.style.flex = '0 0 ' + w + 'px';
          window.dispatchEvent(new Event('resize'));
        }
        function up(){ sp.classList.remove('dragging');
          document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up);
          window.dispatchEvent(new Event('resize')); }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up); e.preventDefault();
      });
      /* Data view: drag the bar between the plot and the table to resize them. */
      document.addEventListener('mousedown', function(e){
        var bar = e.target.closest ? e.target.closest('.ea-wsx-dbar') : null;
        if (!bar) return;
        var plot = bar.previousElementSibling, wrap = bar.parentNode;
        var sy = e.clientY, sh = plot.getBoundingClientRect().height;
        bar.classList.add('dragging');
        function mv(ev){
          var max = wrap.getBoundingClientRect().height - 90;
          plot.style.flex = '0 0 ' + Math.max(90, Math.min(max, sh + ev.clientY - sy)) + 'px';
          window.dispatchEvent(new Event('resize'));
        }
        function up(){ bar.classList.remove('dragging');
          document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up);
          window.dispatchEvent(new Event('resize')); }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up); e.preventDefault();
      });
      /* R Console mode: dock (bottom) | float (over the canvas) | min (bar).
         Docking always returns it to the BOTTOM, clearing any inline geometry
         left behind by dragging or resizing while floating. */
      window.eaConsole = function(id, mode){
        var c = document.getElementById(id); if(!c) return;
        c.classList.remove('float','min','dock');
        if(mode === 'close'){ c.classList.remove('open'); c.classList.add('dock');
          c.style.left = c.style.top = c.style.width = ''; return; }
        if(mode === 'float'){ c.classList.add('open','float'); }
        else if(mode === 'min'){ c.classList.add('open','min');
          c.style.left = c.style.top = c.style.width = ''; c.style.height = ''; c.style.minHeight = ''; }
        else { c.classList.add('open','dock');
          c.style.left = c.style.top = c.style.width = '';
          c.style.height = '300px'; c.style.minHeight = '300px'; }
        window.dispatchEvent(new Event('resize'));   /* let plots re-measure */
      };
      /* The Co-Analyst driving the real UI. It does not run anything behind the
         user's back: it switches to the dataset, opens the screen, fills the
         controls and presses the screen's own Run button, so every setting is
         visible and can be changed and re-run by hand. Each step waits for the
         previous one to actually land, because the panels render server-side. */
      function eaWaitFor(sel, cb, tries){
        tries = tries || 60;
        var el = document.querySelector(sel);
        if (el) { cb(el); return; }
        if (tries <= 0) return;
        setTimeout(function(){ eaWaitFor(sel, cb, tries - 1); }, 100);
      }
      /* A select's choices are filled in by the server AFTER its panel appears,
         so setting a value too early is silently dropped. Wait for the option
         itself, not just the element. */
      function eaWaitForOption(sel, value, cb, tries){
        tries = tries || 80;
        var el = document.querySelector(sel);
        if (el) {
          var has = false, i;
          if (el.selectize) {
            has = !!(el.selectize.options && el.selectize.options[value]);
          } else {
            for (i = 0; i < el.options.length; i++)
              if (el.options[i].value === value) { has = true; break; }
          }
          if (has) { cb(el); return; }
        }
        if (tries <= 0) { console.warn('ea: option not found for ' + sel + ' = ' + value); return; }
        setTimeout(function(){ eaWaitForOption(sel, value, cb, tries - 1); }, 100);
      }
      function eaSetInputEl(el, value){
        /* selectize replaces the <select>, so drive it through its API when present */
        if (el.selectize) { el.selectize.setValue(value, false); return; }
        el.value = value;
        el.dispatchEvent(new Event('input',  { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        if (window.$) $(el).trigger('change');
      }
      if (window.Shiny) Shiny.addCustomMessageHandler('ea_agent_ui', function(a){
        if (!a || a.kind !== 'run_model') return;
        var ds = Array.isArray(a.dataset) ? a.dataset[0] : a.dataset;
        var resp = Array.isArray(a.response) ? a.response[0] : a.response;
        var frm  = Array.isArray(a.formula)  ? a.formula[0]  : a.formula;
        Shiny.setInputValue('active_dataset', ds, {priority:'event'});
        Shiny.setInputValue('current_view', 'workspace', {priority:'event'});
        setTimeout(function(){
          Shiny.setInputValue('workspace-tool_pick', a.method, {priority:'event'});
          /* the module's panel is rendered by the server; wait for its controls */
          eaWaitForOption('#lm-y', resp, function(y){
            eaSetInputEl(y, resp);
            eaWaitFor('#lm-formula_text', function(f){
              eaSetInputEl(f, frm);
              /* let Shiny receive both values before pressing Run */
              setTimeout(function(){
                var b = document.getElementById('lm-run_model');
                if (b) b.click();
              }, 500);
            });
          });
        }, 400);
      });
      /* Stacked output panes: drag a divider to trade height between the pane
         above it and the one below. Sizes are flex-basis, so the panes keep
         filling the area no matter how many are shown. */
      document.addEventListener('mousedown', function(e){
        var sp = e.target.closest ? e.target.closest('.lm-split') : null;
        if (!sp) return;
        var prev = sp.previousElementSibling, next = sp.nextElementSibling;
        if (!prev || !next) return;
        var sy = e.clientY, ph = prev.getBoundingClientRect().height,
            nh = next.getBoundingClientRect().height;
        sp.classList.add('dragging'); document.body.classList.add('ea-resizing');
        function mv(ev){
          var d = ev.clientY - sy;
          var a = Math.max(60, ph + d), b = Math.max(60, nh - d);
          prev.style.flex = '0 0 ' + a + 'px';
          next.style.flex = '0 0 ' + b + 'px';
        }
        function up(){
          sp.classList.remove('dragging'); document.body.classList.remove('ea-resizing');
          document.removeEventListener('mousemove', mv);
          document.removeEventListener('mouseup', up);
          window.dispatchEvent(new Event('resize'));
        }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
        e.preventDefault();
      });
      /* Side panels are resizable by dragging their shared border. The width is
         written to a CSS variable on the grid, so the collapse classes keep
         working and a hidden panel does not lose the width it had. */
      document.addEventListener('mousedown', function(e){
        var h = e.target.closest ? e.target.closest('.ea-wsx-resize') : null;
        if (!h) return;
        var grid = h.closest('.ea-wsx-grid'); if (!grid) return;
        var isLeft = h.classList.contains('l');
        var panel  = h.parentNode, startW = panel.getBoundingClientRect().width;
        var sx = e.clientX;
        h.classList.add('dragging'); document.body.classList.add('ea-resizing');
        function mv(ev){
          var d = ev.clientX - sx;
          var w = Math.round(isLeft ? startW + d : startW - d);
          w = Math.max(140, Math.min(520, w));
          grid.style.setProperty(isLeft ? '--ws-left' : '--ws-right', w + 'px');
        }
        function up(){
          h.classList.remove('dragging'); document.body.classList.remove('ea-resizing');
          document.removeEventListener('mousemove', mv);
          document.removeEventListener('mouseup', up);
          window.dispatchEvent(new Event('resize'));   /* let plots re-measure */
        }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
        e.preventDefault();
      });
      /* .ea-pop behaviour. Hover alone is not enough for a panel holding
         inputs: the moment focus moves the pointer can leave and the panel
         would close mid-edit. So clicking the icon PINS it, Escape closes it,
         and a click outside closes it. Reusable for any hover panel. */
      window.eaPop = function(btn){
        var pop = btn.closest('.ea-pop');
        if (!pop) return;
        var wasOpen = pop.classList.contains('open');
        document.querySelectorAll('.ea-pop.open').forEach(function(p){ p.classList.remove('open'); });
        if (!wasOpen) {
          pop.classList.add('open');
          var first = pop.querySelector('.ea-pop-body input[type=text]');
          if (first) setTimeout(function(){ first.focus(); }, 30);
        }
      };
      /* Right-click menu for a layer row. One menu element reused for every
         layer, built at the cursor. The actions are the ones that only make
         sense per-layer: zoom to it, rename it, hide it, remove it. */
      window.eaLayerMenu = function(ev, name, kind, visible){
        ev.preventDefault(); ev.stopPropagation();
        var old = document.getElementById('ea-ctxmenu');
        if (old) old.remove();
        var m = document.createElement('div');
        m.id = 'ea-ctxmenu'; m.className = 'ea-ctxmenu';
        var add = function(label, fn, danger){
          var a = document.createElement('a');
          a.className = 'ea-ctx-item' + (danger ? ' danger' : '');
          a.textContent = label;
          a.onclick = function(e){ e.preventDefault(); m.remove(); fn(); };
          m.appendChild(a);
        };
        var sep = function(){ var d=document.createElement('div'); d.className='ea-ctx-sep'; m.appendChild(d); };
        /* Symbology first: it is the action a user is most often looking for on
           a layer, and it was previously reachable ONLY by finding the small
           chevron on the row -- built but effectively hidden. */
        if (kind === 'vector' || kind === 'raster') {
          add('Symbology…', function(){
            Shiny.setInputValue('workspace-ws_sym_open', name, {priority:'event'}); });
          sep();
        }
        add('Zoom to layer', function(){
          Shiny.setInputValue('workspace-ws_zoom_layer', name, {priority:'event'}); });
        /* Move to top/bottom: nearly free once the order is explicit, and easier
           than dragging in a long list -- which is exactly where a drag handle is
           worst, because the panel scrolls while you drag. */
        add('Move to top', function(){
          Shiny.setInputValue('workspace-ws_lyr_top', name, {priority:'event'}); });
        add('Move to bottom', function(){
          Shiny.setInputValue('workspace-ws_lyr_bottom', name, {priority:'event'}); });
        add('Rename…', function(){
          Shiny.setInputValue('layer_rename_request', name, {priority:'event'}); });
        add(visible ? 'Hide layer' : 'Show layer', function(){
          Shiny.setInputValue('workspace-ws_vis', name, {priority:'event'}); });
        sep();
        add('Remove from project', function(){
          if (confirm('Remove \\'' + name + '\\' from this project?\\n\\nYour original file on disk is not deleted.'))
            eaSetInput('delete_dataset', name); }, true);
        document.body.appendChild(m);
        /* keep it on screen */
        var w = m.offsetWidth, h = m.offsetHeight;
        var x = Math.min(ev.clientX, window.innerWidth  - w - 8);
        var y = Math.min(ev.clientY, window.innerHeight - h - 8);
        m.style.left = Math.max(4, x) + 'px';
        m.style.top  = Math.max(4, y) + 'px';
      };

      /* Layer reordering by drag (backlog item 65) -------------------------
         Only the grip starts a drag; the row keeps its click targets. The drop
         handler sends the COMPLETE new order rather than a move instruction, so
         the server never reconstructs what the drag did, and the rows are then
         rebuilt from the stored order -- the DOM is never the source of truth.
         A drop that fails to save simply snaps back, which is honest.
         The basemap row carries no data-lyr, so it can neither be dragged nor
         dropped onto: it is tiles pinned under everything, not a project layer. */
      var eaDragLyr = null;
      document.addEventListener('dragstart', function(e){
        var g = e.target.closest && e.target.closest('.ea-wsx-grip');
        if (!g) return;
        var row = g.closest('[data-lyr]');
        if (!row) return;
        eaDragLyr = row.getAttribute('data-lyr');
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', eaDragLyr);
        if (e.dataTransfer.setDragImage) e.dataTransfer.setDragImage(row, 12, 12);
        row.classList.add('dragging');
      });
      var eaDragClear = function(){
        eaDragLyr = null;
        document.querySelectorAll('.ea-wsx-lyr2.dragging, .ea-wsx-lyr2.dropinto')
          .forEach(function(r){ r.classList.remove('dragging', 'dropinto'); });
      };
      document.addEventListener('dragend', eaDragClear);
      document.addEventListener('dragover', function(e){
        if (!eaDragLyr) return;
        var row = e.target.closest && e.target.closest('[data-lyr]');
        if (!row) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        document.querySelectorAll('.ea-wsx-lyr2.dropinto')
          .forEach(function(r){ r.classList.remove('dropinto'); });
        if (row.getAttribute('data-lyr') !== eaDragLyr) row.classList.add('dropinto');
      });
      document.addEventListener('drop', function(e){
        if (!eaDragLyr) return;
        var row = e.target.closest && e.target.closest('[data-lyr]');
        if (!row) { eaDragClear(); return; }
        e.preventDefault();
        var box = row.closest('[data-reorder-input]');
        var target = row.getAttribute('data-lyr');
        if (!box || target === eaDragLyr) { eaDragClear(); return; }
        var names = [].map.call(box.querySelectorAll('[data-lyr]'), function(r){
          return r.getAttribute('data-lyr'); });
        var rect = row.getBoundingClientRect();
        var after = (e.clientY - rect.top) > rect.height / 2;
        var moved = eaDragLyr;
        names = names.filter(function(n){ return n !== moved; });
        names.splice(names.indexOf(target) + (after ? 1 : 0), 0, moved);
        Shiny.setInputValue(box.getAttribute('data-reorder-input'),
                            {order: names, nonce: Date.now()}, {priority:'event'});
        eaDragClear();
      });
      document.addEventListener('click', function(e){
        var m = document.getElementById('ea-ctxmenu');
        if (m && !e.target.closest('#ea-ctxmenu')) m.remove();
        if (e.target.closest && e.target.closest('.ea-pop')) return;
        document.querySelectorAll('.ea-pop.open').forEach(function(p){ p.classList.remove('open'); });
      });

      /* Attribute-table window controls (backlog item 52) ------------------
         Delegated, and the state is kept on <html>, because the dock is rebuilt
         by .map_ui() on every map re-render. An inline onclick that toggled a
         class on the dock lost its state at the first layer change -- which is
         why collapsing it never stuck. Client-side by necessity too: Shiny is
         single-threaded, so a server round-trip here would queue behind any
         running fit (gotcha 29). */
      var eaAttrSet = function(s){
        var R = document.documentElement;
        R.classList.remove('ea-attr-min', 'ea-attr-max', 'ea-attr-closed');
        if (s !== 'normal') R.classList.add('ea-attr-' + s);
        R.setAttribute('data-attr-state', s);
      };
      window.eaAttrSet = eaAttrSet;
      eaAttrSet('normal');
      document.addEventListener('click', function(e){
        var b = e.target.closest && e.target.closest('[data-attr-act]');
        if (!b) return;
        e.preventDefault();
        var a = b.getAttribute('data-attr-act');
        var cur = document.documentElement.getAttribute('data-attr-state') || 'normal';
        if (a === 'min')   eaAttrSet(cur === 'min' ? 'normal' : 'min');
        else if (a === 'max') eaAttrSet(cur === 'max' ? 'normal' : 'max');
        else if (a === 'close') eaAttrSet('closed');
        else if (a === 'open')  eaAttrSet(cur === 'closed' ? 'normal' : 'closed');
      });
      /* Drag the header to resize. The header has advertised ns-resize since it
         was written, with nothing behind it -- an affordance that promises and
         does not deliver is worse than none. Height goes on <html> for the same
         survival reason as the state. */
      var eaAttrDrag = null;
      document.addEventListener('mousedown', function(e){
        if (!e.target.closest) return;
        if (e.target.closest('[data-attr-act]')) return;
        var h = e.target.closest('.ea-wsx-attrhead');
        if (!h) return;
        var R = document.documentElement;
        if (R.classList.contains('ea-attr-max') || R.classList.contains('ea-attr-min')) return;
        var body = h.parentElement && h.parentElement.querySelector('.ea-wsx-attrbody');
        if (!body) return;
        eaAttrDrag = { y: e.clientY, h: body.getBoundingClientRect().height };
        e.preventDefault();
      });
      document.addEventListener('mousemove', function(e){
        if (!eaAttrDrag) return;
        var nh = Math.min(760, Math.max(90, eaAttrDrag.h + (eaAttrDrag.y - e.clientY)));
        document.documentElement.style.setProperty('--ea-attr-h', nh + 'px');
      });
      document.addEventListener('mouseup', function(){ eaAttrDrag = null; });
      document.addEventListener('keydown', function(e){
        if (e.key === 'Escape') {
          var m = document.getElementById('ea-ctxmenu'); if (m) m.remove();
          document.querySelectorAll('.ea-pop.open').forEach(function(p){ p.classList.remove('open'); });
        }
      });
      /* Mark the icon when the panel holds a value, so a closed panel still
         shows that something was overridden. Done here rather than server-side
         because the panel must NOT depend on the store it writes to — that
         dependency is what previously made it rebuild and wipe itself. */
      document.addEventListener('input', function(e){
        var body = e.target.closest ? e.target.closest('.ea-pop-body') : null;
        if (!body) return;
        var pop = body.closest('.ea-pop'), btn = pop.querySelector('.ea-pop-btn');
        var any = false;
        body.querySelectorAll('input[type=text]').forEach(function(i){
          if (i.value && i.value.length) any = true;
        });
        btn.classList.toggle('set', any);
      });
      /* Line numbers for the R Console editor. A gutter div beside the textarea
         rather than a code-editor library: no external dependency (the CSP
         blocks them anyway), and it stays a plain Shiny textarea so Ctrl+Enter,
         the example chips and value persistence keep working. Wrapping is off
         in the textarea, so one number is always exactly one line. */
      window.eaCodeGutter = function(taId, gutId){
        var ta = document.getElementById(taId), g = document.getElementById(gutId);
        if (!ta || !g || ta.dataset.eaGutter) return;
        ta.dataset.eaGutter = '1';
        /* NL via fromCharCode on purpose: a literal backslash-n inside this
           HTML() string is consumed by R and arrives here as a REAL newline,
           which breaks the JS string it sits in (CLAUDE.md gotcha 1). */
        var NL = String.fromCharCode(10);
        function paint(){
          var n = ta.value.split(NL).length;
          if (g.dataset.n !== String(n)){
            var out = [];
            for (var i = 1; i <= n; i++) out.push(i);
            g.textContent = out.join(NL);
            g.dataset.n = String(n);
          }
          g.scrollTop = ta.scrollTop;   /* keep the two in step */
        }
        ta.addEventListener('input',  paint);
        ta.addEventListener('keyup',  paint);
        ta.addEventListener('scroll', function(){ g.scrollTop = ta.scrollTop; });
        paint();
      };
      /* R Console plot window: open / maximize-restore / close. Resizing is the
         browser's own grip (CSS `resize`); there is no dock mode by design. */
      window.eaPlotWin = function(id, mode){
        var w = document.getElementById(id); if(!w) return;
        if(mode === 'close'){ w.classList.remove('open','max'); return; }
        if(mode === 'max'){
          w.classList.add('open');
          if(w.classList.contains('max')){        /* restore */
            w.classList.remove('max');
            w.style.cssText = w.dataset.prevStyle || '';
          } else {                                 /* maximize */
            /* drop any inline geometry from dragging/resizing, else it would
               out-specify the .max rules and the window would not grow. */
            w.dataset.prevStyle = w.style.cssText;
            w.style.cssText = '';
            w.classList.add('max');
          }
        } else { w.classList.add('open'); }
        window.dispatchEvent(new Event('resize'));
      };
      if(window.Shiny){
        Shiny.addCustomMessageHandler('rc_plotwin',       function(id){ eaPlotWin(id, 'open'); });
        Shiny.addCustomMessageHandler('rc_plotwin_close', function(id){ eaPlotWin(id, 'close'); });
      }
      /* Drag the plot window by its header (not while maximized). */
      document.addEventListener('mousedown', function(e){
        var h = e.target.closest ? e.target.closest('.rc-pw-head') : null;
        if (!h || e.target.tagName === 'BUTTON') return;
        var win = h.parentNode;
        if (win.classList.contains('max')) return;
        var r = win.getBoundingClientRect(), sx = e.clientX, sy = e.clientY;
        /* pin by left/top so dragging is not fought by the right/bottom anchor */
        win.style.left = r.left + 'px'; win.style.top = r.top + 'px';
        win.style.right = 'auto'; win.style.bottom = 'auto';
        win.style.width = r.width + 'px'; win.style.height = r.height + 'px';
        function mv(ev){
          win.style.left = Math.max(0, Math.min(window.innerWidth  - 80, r.left + ev.clientX - sx)) + 'px';
          win.style.top  = Math.max(0, Math.min(window.innerHeight - 40, r.top  + ev.clientY - sy)) + 'px';
        }
        function up(){ document.removeEventListener('mousemove', mv);
                       document.removeEventListener('mouseup', up); }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
        e.preventDefault();
      });
      /* The plot must re-render at the new size when the window is resized by
         its grip — that grip fires no window 'resize', which Shiny listens for. */
      if (window.ResizeObserver) {
        var pwT = null;
        var pwObs = new ResizeObserver(function(){
          clearTimeout(pwT);
          pwT = setTimeout(function(){ window.dispatchEvent(new Event('resize')); }, 120);
        });
        document.addEventListener('DOMContentLoaded', function(){
          setTimeout(function(){
            document.querySelectorAll('.rc-plotwin').forEach(function(w){ pwObs.observe(w); });
          }, 1500);
        });
      }
      /* Header drag: RESIZE when docked (drag up = taller), MOVE when floating. */
      document.addEventListener('mousedown', function(e){
        var h = e.target.closest ? e.target.closest('.ea-wsx-conh') : null;
        if (!h || e.target.tagName === 'BUTTON') return;
        var dock = h.parentNode;
        if (dock.classList.contains('min')) return;
        var floating = dock.classList.contains('float');
        var sx = e.clientX, sy = e.clientY;
        var r = dock.getBoundingClientRect(), sh = dock.offsetHeight;
        function mv(ev){
          if (floating){
            var nx = Math.max(0, Math.min(window.innerWidth  - 120, r.left + ev.clientX - sx));
            var ny = Math.max(0, Math.min(window.innerHeight - 60,  r.top  + ev.clientY - sy));
            dock.style.left = nx + 'px'; dock.style.top = ny + 'px';
          } else {
            var nh = Math.max(90, Math.min(window.innerHeight - 160, sh - (ev.clientY - sy)));
            dock.style.height = nh + 'px'; dock.style.minHeight = nh + 'px';
          }
        }
        function up(){ document.removeEventListener('mousemove', mv);
                       document.removeEventListener('mouseup', up);
                       window.dispatchEvent(new Event('resize')); }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
        e.preventDefault();
      });
      /* Workspace attribute dock: drag the header to resize (drag up = taller). */
      document.addEventListener('mousedown', function(e){
        var h = e.target.closest ? e.target.closest('.ea-wsx-attrhead') : null;
        if (!h || e.target.tagName === 'BUTTON') return;
        var body = h.nextElementSibling; if (!body) return;
        var sy = e.clientY, sh = body.offsetHeight;
        function mv(ev){ body.style.maxHeight = Math.max(0, Math.min(420, sh - (ev.clientY - sy))) + 'px'; }
        function up(){ document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up); e.preventDefault();
      });
      /* Projects screen: empty (no panels) vs populated (tools panel shows
         project info). Sent whenever the project list changes. */
      Shiny.addCustomMessageHandler('ea-projects-empty', function(isEmpty){
        var m = document.querySelector('.app-main');
        if (m) m.classList.toggle('projects-empty', !!isEmpty);
      });

      /* ---- Panel resize drag ---- */
      (function(){
        var dragging=null, startX=0, startW=0;
        document.addEventListener('mousedown', function(e){
          var d = e.target.closest('.app-divider'); if(!d) return;
          var m = document.querySelector('.app-main');
          dragging = d.classList.contains('left') ? 'left' : 'right';
          if(m.classList.contains(dragging+'-collapsed')){ dragging=null; return; }
          startX = e.clientX;
          var cur = m.style.getPropertyValue(dragging==='left'?'--left-w':'--right-w');
          startW = parseInt(cur) || (dragging==='left'?240:350);
          d.classList.add('dragging');
          document.body.style.userSelect='none'; document.body.style.cursor='col-resize';
          e.preventDefault();
        });
        document.addEventListener('mousemove', function(e){
          if(!dragging) return;
          var m = document.querySelector('.app-main');
          var dx = e.clientX - startX;
          var w  = dragging==='left' ? startW+dx : startW-dx;
          w = Math.max(140, Math.min(window.innerWidth*0.5, w));
          m.style.setProperty(dragging==='left'?'--left-w':'--right-w', w+'px');
        });
        document.addEventListener('mouseup', function(){
          if(!dragging) return; dragging=null;
          document.querySelectorAll('.app-divider').forEach(function(d){ d.classList.remove('dragging'); });
          document.body.style.userSelect=''; document.body.style.cursor='';
          if(window.Shiny) window.dispatchEvent(new Event('resize'));
        });
      })();

      function toggleRail(side){
        var m   = document.querySelector('.app-main');
        var cls = side==='left' ? 'left-collapsed' : 'right-collapsed';
        var v   = side==='left' ? '--left-w' : '--right-w';
        var def = side==='left' ? '240px' : '350px';
        if(m.classList.contains(cls)){
          m.classList.remove(cls);
          m.style.setProperty(v, m.dataset[side] || def);
        } else {
          m.dataset[side] = m.style.getPropertyValue(v) || def;
          m.classList.add(cls);
          m.style.setProperty(v, '36px');
        }
      }

      /* ---- Disconnect (usually: the computer slept) ----
         The websocket dies when the OS suspends the network stack. Shiny's own
         response is a grey veil with no way out, so the app looked permanently
         broken. Probe the server to tell the two cases apart, because the
         remedy is different: R still running -> reload reconnects; R gone ->
         it has to be started again. */
      /* A backgrounded tab can have its websocket throttled or dropped by the
         browser, which arrives as shiny:disconnected and is indistinguishable
         from a real failure at that instant. Showing the panel then interrupts
         ordinary browsing -- switch tab, come back, get told you are
         disconnected.
         NO TIME WINDOW. An earlier version suppressed for 30 s after the tab was
         hidden, which was arbitrary and wrong in both directions: away for a
         minute and you still got the panel, while a genuine failure 20 s after a
         glance at another tab was hidden. The rule is about STATE, not elapsed
         time -- a disconnect that arrives while the tab is hidden is simply
         held, and decided when the user is looking at the page again. */
      window.eaPendingDc = false;
      document.addEventListener('visibilitychange', function(){
        if (document.hidden) return;
        /* Back on the page. If a disconnect was held while away, decide it now:
           still disconnected after the delay -> show; reconnected in the
           meantime -> shiny:connected already cleared it. */
        if (window.eaPendingDc) {
          window.eaPendingDc = false;
          eaShowDisconnect();
        }
      });

      function eaShowDisconnect(){
        /* Quit drops the websocket too, and that disconnect is EXPECTED -- without
           this guard the panel would cover the has-closed message and tell the
           user to reconnect to something they just closed. (No literal double
           quotes in here: this is inside an R HTML() string -- gotcha 1.) */
        if(window.eaQuitting) return;
        /* Hidden: HOLD it, indefinitely, and decide when the page is visible
           again (the visibilitychange handler above re-calls this). Nothing is
           lost -- if the connection really is gone the panel appears as soon as
           the user is looking, and if it recovered while away shiny:connected
           cleared the flag. */
        if(document.hidden) { window.eaPendingDc = true; return; }
        var el = document.getElementById('ea-disconnect');
        if(!el || el.classList.contains('on')) return;   /* never stack */

        /* WAIT before shouting. A momentary drop usually reconnects on its own,
           and a panel that appears and vanishes is worse than no panel. Only a
           disconnect still standing after the delay is worth interrupting for --
           shiny:connected cancels it (see the handler below). */
        clearTimeout(window.eaDcTimer);
        window.eaDcTimer = setTimeout(function(){ eaRenderDisconnect(el); }, 2500);
      }

      function eaRenderDisconnect(el){
        if(window.eaQuitting || document.hidden) return;
        if(!el || el.classList.contains('on')) return;
        el.classList.add('on');
        var msg = document.getElementById('ea-dc-msg');
        var btn = document.getElementById('ea-dc-reload');
        if(btn) btn.disabled = true;
        /* cache: no-store so a cached 200 cannot make a dead server look alive. */
        fetch(window.location.pathname + '?ea-ping=' + Date.now(),
              { method: 'GET', cache: 'no-store' })
          .then(function(r){
            if(!r.ok) throw new Error('bad status');
            if(msg) msg.textContent =
              'EasyAnalysis is still running. This usually happens after the computer sleeps. Reconnect to carry on.';
            if(btn){ btn.disabled = false; btn.textContent = 'Reconnect'; btn.focus(); }
          })
          .catch(function(){
            if(msg) msg.textContent =
              'EasyAnalysis has stopped. Start it again from the EasyAnalysis shortcut on your Desktop, then reopen your project.';
            if(btn){ btn.disabled = false; btn.textContent = 'Try again'; }
          });
      }
      if(window.jQuery){
        jQuery(document).on('shiny:disconnected', eaShowDisconnect);
        /* If it comes back on its own, get out of the way. */
        jQuery(document).on('shiny:connected', function(){
          /* Cancel a pending panel as well as hiding a shown one -- otherwise a
             drop that reconnects within the delay still pops the panel
             afterwards, which is the exact interruption this is meant to stop. */
          clearTimeout(window.eaDcTimer);
          window.eaPendingDc = false;   /* a held disconnect that recovered */
          var el = document.getElementById('ea-disconnect');
          if(el) el.classList.remove('on');
        });
      }

      /* ---- Quit ----
         Confirm, then show the veil BEFORE telling the server to stop: once
         stopApp() runs the websocket drops, and anything we try to render after
         that never arrives. The veil is therefore purely client-side. */
      function eaQuitApp(){
        /* \\n, NOT \n: this lives in an R double-quoted HTML() string, so R
           consumes the escape first. A bare \n became a REAL newline inside a
           JS string literal -- a syntax error that killed this whole <script>
           block, taking openSettings() and every other handler with it. The
           app rendered fine and nothing was clickable. (Gotcha 1, new form.) */
        if(!confirm('Close EasyAnalysis?\\n\\nThe R session will stop. Your project is saved automatically.')) return;
        /* Tell the disconnect handler this drop is intentional (see above). */
        window.eaQuitting = true;
        var v = document.getElementById('ea-quit-veil');
        if(v) v.classList.add('on');
        Shiny.setInputValue('app_quit', Date.now(), {priority:'event'});
      }

      /* ---- Settings drawer ---- */
      function openSettings(section){
        var p  = document.getElementById('settings-panel');
        var ov = document.getElementById('settings-overlay');
        ov.style.display = 'block';
        /* Re-mark the active theme on every open: it can be changed from the
           workspace View menu too, and the panel is built once and reused. */
        if (window.eaMarkTheme) window.eaMarkTheme();
        requestAnimationFrame(function(){
          p.classList.add('open');
          ov.style.opacity = '1';
          /* Menu entries name a SECTION (About, Keyboard shortcuts, ...) — land
             on it rather than dumping the reader at the top of the panel. */
          if (section){
            var el = document.getElementById(section);
            if (el) setTimeout(function(){
              el.scrollIntoView({behavior:'smooth', block:'start'});
              el.classList.add('settings-flash');
              setTimeout(function(){ el.classList.remove('settings-flash'); }, 1200);
            }, 240);
          }
        });
      }
      function closeSettings(){
        var p  = document.getElementById('settings-panel');
        var ov = document.getElementById('settings-overlay');
        p.classList.remove('open');
        ov.style.opacity = '0';
        setTimeout(function(){ ov.style.display='none'; }, 260);
      }

      /* ---- Global keyboard shortcuts ---- */
      document.addEventListener('keydown', function(e){
        /* Ctrl+Z  — Undo last data operation */
        if(e.ctrlKey && !e.shiftKey && !e.altKey && e.key==='z'){
          if(window.Shiny)
            Shiny.setInputValue('data-undo_last', Date.now(), {priority:'event'});
          e.preventDefault();
        }
        /* Ctrl+Shift+Z  — Reset dataset to upload */
        if(e.ctrlKey && e.shiftKey && e.key==='Z'){
          if(window.Shiny)
            Shiny.setInputValue('data-reset_raw', Date.now(), {priority:'event'});
          e.preventDefault();
        }
        /* Ctrl+,  — Open settings */
        if(e.ctrlKey && e.key===','){
          openSettings(); e.preventDefault();
        }
        /* Enter  — submit the primary (success) action of an open modal, e.g.
           Create project / Rename. Skips a textarea so multi-line inputs still
           get newlines. Delete modals have no .btn-success, so Enter never
           auto-confirms a destructive action. */
        if(e.key==='Enter' && !e.shiftKey){
          var md = document.querySelector('.modal.show');
          if(md && document.activeElement && document.activeElement.tagName !== 'TEXTAREA'){
            var go = md.querySelector('.btn-success');
            if(go){ e.preventDefault(); go.click(); }
          }
        }
        /* Escape  — close the settings drawer (modals close via Bootstrap easyClose) */
        if(e.key==='Escape') closeSettings();
      });

      /* ===== GLOBAL PLOT DOWNLOAD OVERLAY ===== */
      /* Inject a download button into every Shiny plot output on first hover. */
      $(document).on('mouseenter', '.shiny-plot-output', function(){
        var $w = $(this);
        if($w.find('.plot-dl-btn').length > 0) return;
        var $btn = $('<button class=\"plot-dl-btn\" title=\"Download plot\"><i class=\"fa fa-download\" style=\"margin-right:3px;\"></i>PNG</button>');
        $btn.on('click', function(e){
          e.stopPropagation();
          var $img = $w.find('img');
          if(!$img.length) return;
          var src = $img.attr('src');
          if(!src) return;
          var outId = ($w.attr('id') || 'plot').replace(/[^a-z0-9_\\-]/gi,'_');
          var a = document.createElement('a');
          a.download = outId + '.png';
          if(src.startsWith('data:')){
            a.href = src; document.body.appendChild(a); a.click(); document.body.removeChild(a);
          } else {
            fetch(src).then(function(r){return r.blob();}).then(function(b){
              a.href = URL.createObjectURL(b);
              document.body.appendChild(a); a.click(); document.body.removeChild(a);
              setTimeout(function(){URL.revokeObjectURL(a.href);},1000);
            });
          }
        });
        $w.append($btn);
      });

      /* ===== GLOBAL RUNNING INDICATOR — honest elapsed count-up, no fake ETA ===== */
      (function(){
        var css='#ea-run{position:fixed;bottom:18px;left:50%;transform:translateX(-50%) translateY(20px);z-index:12000;display:none;align-items:center;gap:9px;padding:8px 15px;border-radius:22px;background:rgba(27,94,32,.96);color:#fff;font:600 13px system-ui,-apple-system,Segoe UI,Roboto,sans-serif;box-shadow:0 8px 26px rgba(0,0,0,.32);opacity:0;transition:opacity .25s,transform .25s;}#ea-run.on{display:flex;opacity:1;transform:translateX(-50%) translateY(0);}#ea-run .s{width:14px;height:14px;border:2.4px solid rgba(255,255,255,.35);border-top-color:#fff;border-radius:50%;animation:earun .8s linear infinite;}#ea-run b{color:#c8e6c9;font-variant-numeric:tabular-nums;}@keyframes earun{to{transform:rotate(360deg);}}';
        var st=document.createElement('style'); st.textContent=css; document.head.appendChild(st);
        var el=document.createElement('div'); el.id='ea-run';
        el.innerHTML='<span class=\"s\"></span><span>Running… <b id=\"ea-run-t\">0:00</b></span>';
        document.body.appendChild(el);
        var t0,iv,showT;
        function fmt(s){return Math.floor(s/60)+':'+('0'+(s%60)).slice(-2);}
        document.addEventListener('shiny:busy', function(){
          t0=Date.now(); clearTimeout(showT);
          showT=setTimeout(function(){
            el.classList.add('on'); clearInterval(iv);
            iv=setInterval(function(){var t=document.getElementById('ea-run-t'); if(t) t.textContent=fmt(Math.floor((Date.now()-t0)/1000));},1000);
          },500);
        });
        document.addEventListener('shiny:idle', function(){
          clearTimeout(showT); clearInterval(iv); el.classList.remove('on');
        });
      })();

      /* ===== ROBUST DOWNLOAD — webR downloadHandler is unreliable; R sends content, JS saves it ===== */
      Shiny.addCustomMessageHandler('ea-download', function(m){
        try{
          var doc = document;
          try { if (window.top && window.top.document && window.top.document.body) doc = window.top.document; } catch(e){}
          var blob = new Blob([m.content], {type: m.mime || 'text/plain;charset=utf-8'});
          var url = URL.createObjectURL(blob);
          var a = doc.createElement('a'); a.href = url; a.download = m.name || 'download';
          a.style.display = 'none'; doc.body.appendChild(a); a.click();
          setTimeout(function(){ try{ doc.body.removeChild(a); }catch(e){} URL.revokeObjectURL(url); }, 2000);
        }catch(e){ console.error('ea-download failed', e); }
      });
    ")),

    tags$script(HTML("
      /* ===== TOOL SEARCH — one box that indexes every menu item =====
         The index is built from the live menu DOM (each menu link already sets
         current_view via onclick), so it can never drift from the menus. Uses
         String.fromCharCode(39) for the single-quote split and only single
         quotes throughout, so nothing here breaks the R HTML() string. */
      (function(){
        /* Tool search. It used to scrape the OLD menubar for items whose onclick
           set `current_view`; the unified workspace builds its menu from .gm-item
           and sets `workspace-tool_pick`, so the index came back empty and every
           query found nothing. Index the real menu instead, and activate
           a hit by replaying the item's OWN click — the menu already knows how to
           open each thing, so the search never has to model that itself.
           Rebuilt per query on purpose: the menubar is a uiOutput, so a cached
           index would hold references to elements that no longer exist. */
        function buildIndex(){
          var out = [];
          document.querySelectorAll('.gm-item').forEach(function(a){
            if (a.classList.contains('disabled')) return;
            /* A fly-out PARENT is itself a .gm-item and contains the whole
               submenu, so its textContent is every child concatenated. Index
               leaves only. */
            if (a.querySelector('.gm-item')) return;
            var label = (a.textContent || '').replace(/\\s+/g, ' ').trim();
            if (!label) return;
            var grp = '', menu = a.closest('.gm');
            if (menu){
              var btn = menu.querySelector('.gm-btn span');
              if (btn) grp = (btn.textContent || '').trim();
            }
            var fly = a.closest('.gm-fly');            /* nested fly-out group */
            if (fly){
              var head = fly.previousElementSibling;
              if (head) {
                var sub = (head.textContent || '').replace(/[\\u25b8>]/g, '').trim();
                if (sub) grp = grp ? (grp + ' / ' + sub) : sub;
              }
            }
            out.push({ label: label, group: grp, el: a });
          });
          return out;
        }
        function box(){ return document.getElementById('tool_search_results'); }
        window.eaToolSearch = function(q){
          var b = box(); if(!b) return;
          b.innerHTML = ''; q = (q||'').trim().toLowerCase();
          if(!q){ b.classList.remove('open'); return; }
          var hits = buildIndex().filter(function(t){
            return t.label.toLowerCase().indexOf(q) > -1 ||
                   (t.group && t.group.toLowerCase().indexOf(q) > -1);
          }).slice(0, 14);
          /* Ask the server for tools that are NOT in the menu -- provider tools
             the user has not enabled yet. The menu index can only ever find what
             is already registered, which is why searching for a WhiteboxTools
             tool returned nothing at all. */
          if (window.Shiny && Shiny.setInputValue)
            Shiny.setInputValue('tool_search_q', q, {priority:'event'});
          if(!hits.length){
            var none = document.createElement('div'); none.className = 'none';
            none.textContent = 'Searching…'; none.id = 'ea-ts-none';
            b.appendChild(none);
            b.classList.add('open'); return;
          }
          hits.forEach(function(h){
            var a = document.createElement('a'); a.href = '#';
            a.appendChild(document.createTextNode(h.label));
            if(h.group){
              var g = document.createElement('span'); g.className = 'grp';
              g.textContent = h.group; a.appendChild(g);
            }
            a.addEventListener('click', function(e){
              e.preventDefault(); e.stopPropagation();
              b.classList.remove('open'); b.innerHTML = '';
              var inp = document.getElementById('tool_search'); if(inp) inp.value = '';
              document.querySelectorAll('.gm.open').forEach(function(x){ x.classList.remove('open'); });
              h.el.click();                    /* let the menu item do its own job */
            });
            b.appendChild(a);
          });
          b.classList.add('open');
        };
        document.addEventListener('click', function(){ var b = box(); if(b) b.classList.remove('open'); });

        /* Extra results: provider tools that are not enabled yet. They are shown
           under their own heading with an Activate action, because enabling one
           is a decision -- it is somebody else's engine -- not a side effect of
           searching. Non-provider tools never reach this path and so never show
           an activation control. */
        /* Open a tool by key after the server has enabled it. Binding and the
           catalogue rebuild both happen on the same flush, so by the time this
           arrives the tool exists. */
        if (window.Shiny && Shiny.addCustomMessageHandler)
          Shiny.addCustomMessageHandler('ea_open_tool', function(m){
            if (m && m.key) Shiny.setInputValue('workspace-tool_pick', m.key,
                                                {priority:'event'});
          });
        if (window.Shiny && Shiny.addCustomMessageHandler)
          Shiny.addCustomMessageHandler('ea_tool_search_extra', function(m){
            var b = box(); if(!b) return;
            var none = document.getElementById('ea-ts-none'); if(none) none.remove();
            var old = b.querySelector('.ea-ts-extra'); if(old) old.remove();
            if(!m || (!m.items || !m.items.length) && !m.needs_index){
              if(!b.children.length){
                var n2 = document.createElement('div'); n2.className='none';
                n2.textContent = 'No tools match: ' + (m && m.q ? m.q : '');
                b.appendChild(n2);
              }
              b.classList.add('open'); return;
            }
            var wrap = document.createElement('div'); wrap.className = 'ea-ts-extra';
            var h = document.createElement('div'); h.className = 'ea-ts-head';
            /* Name the source in the heading, not only in each label: the popup is
               where the decision to enable someone else's engine is taken, so it
               must be unmistakable whose engine it is. */
            h.textContent = m.needs_index ? 'WhiteboxTools'
                                          : 'WhiteboxTools - not enabled yet';
            wrap.appendChild(h);
            if(m.needs_index){
              var a0 = document.createElement('a'); a0.href = '#';
              a0.appendChild(document.createTextNode(
                'Index WhiteboxTools to search its 484 tools'));
              a0.addEventListener('click', function(e){
                e.preventDefault(); e.stopPropagation();
                b.classList.remove('open'); b.innerHTML = '';
                Shiny.setInputValue('plugins_open', Date.now(), {priority:'event'});
              });
              wrap.appendChild(a0);
            }
            (m.items||[]).forEach(function(it){
              var a = document.createElement('a'); a.href = '#';
              a.appendChild(document.createTextNode(it.label));
              var g = document.createElement('span'); g.className = 'grp';
              g.textContent = it.group || 'WhiteboxTools'; a.appendChild(g);
              var act = document.createElement('span');
              if (it.usable === false){
                /* Shown, but never offered. A tool that declares no output cannot
                   become a layer, so an Activate here would do nothing at all --
                   and a dead button is worse than an honest explanation. */
                act.className = 'ea-ts-act off';
                act.textContent = 'Not supported';
                act.title = 'This tool writes its result beside its input rather ' +
                            'than returning a layer, so it cannot run here yet.';
                a.classList.add('ea-ts-dim');
              } else {
                act.className = 'ea-ts-act'; act.textContent = 'Activate';
                a.addEventListener('click', function(e){
                  e.preventDefault(); e.stopPropagation();
                  b.classList.remove('open'); b.innerHTML = '';
                  var inp = document.getElementById('tool_search'); if(inp) inp.value = '';
                  Shiny.setInputValue('tool_activate',
                    {provider: it.provider, tool: it.tool, n: Date.now()},
                    {priority:'event'});
                });
              }
              a.appendChild(act);
              wrap.appendChild(a);
            });
            b.appendChild(wrap);
            b.classList.add('open');
          });
      })();
    "))
  ),

  # ---- Boot overlay: covers the first render until Shiny is idle ----
  tags$div(id = "ea-boot",
    tags$div(class = "ea-boot-inner",
      tags$div(class = "ea-boot-mark", icon("lightbulb")),
      tags$div(class = "ea-boot-name", "EasyAnalysis"),
      tags$div(class = "ea-boot-bar", tags$i()),
      tags$div(class = "ea-boot-msg", "Starting up…"))),
  tags$script(HTML(paste0(
    "(function(){var b=document.getElementById('ea-boot');if(!b)return;",
    "var done=function(){ if(b.classList.contains('gone'))return;",
    "  b.classList.add('gone'); setTimeout(function(){ b.style.display='none'; },320); };",
    # hide once Shiny has finished its first render pass, with a hard timeout
    "if(window.jQuery){ $(document).one('shiny:idle', function(){ setTimeout(done, 120); }); }",
    "setTimeout(done, 12000);",
    "})();"))),

  # ---- GLOBAL "Running" pill --------------------------------------------
  # The one signal that covers all 42 screens. Only 12 of them use
  # withProgress(), so on the other 30 a slow fit used to look like a frozen
  # app -- and this app had LESS feedback than stock Shiny, because
  # `--shiny-fade-opacity: 1` above deliberately turns off Shiny's own dimming.
  # That trade was made on the promise of a "Running pill" (see the comment at
  # the top of this file) which was never actually built. This is it.
  #
  # It is CLIENT-side on purpose, keyed off the `shiny-busy` class Shiny puts on
  # <html> while a request is outstanding. Shiny is single-threaded, so during a
  # blocking fit the server cannot render or animate anything at all -- but the
  # browser is a separate process and keeps painting, so a CSS animation driven
  # by a class is the ONLY thing that can move while R is busy. It also needs no
  # per-module wiring, which is what makes it reach every screen at once.
  #
  # Honest by construction: it is shown by Shiny's real request state, never by
  # a timer, so it cannot claim work that is not happening.
  tags$div(id = "ea-busy", role = "status", `aria-live` = "polite",
           tags$i(class = "ea-busy-spin"), tags$span("Running…")),

  tags$div(class = "app-shell",

    # =================== TOP MENUBAR ===================
    # Ships menu-free + on-projects: the app starts on Projects. The ea-view
    # handler updates both when the view changes.
    tags$div(class = "app-topbar menufree on-projects",

      # Brand
      tags$span(class = "brand",
        icon("lightbulb", class = "brand-icon"),   # the app icon (for now)
        "EasyAnalysis"
      ),

      # GeoLibre menubar lives HERE in the top bar. It is rendered by
      # mod_workspace's `output$menubar` (namespaced id "workspace-menubar").
      tags$div(class = "gm-host", `data-tour` = "menu",
               uiOutput("workspace-menubar")),

      # Legacy nav (retired — kept only so old .topItem/.topMenu helpers stay
      # referenced; hidden by CSS and skipped by if(FALSE) below).
      tags$ul(class = "nav legacy-nav",
        # "Project" is deliberately NOT a menu item: you get there by opening a
        # project, and the project screen has its own "← Projects" link. Two
        # near-identical nav entries read as a mistake.
        # UNIFIED: every analysis lives in the workspace's tool dropdown + the
        # search box, so the menubar stays minimal (artifact = source of truth).
        # Recommend is merged INTO the Co-Analyst dock; everything else moved to
        # the GeoLibre menubar above. Nothing renders from this legacy list.
        if (FALSE) tagList(
          .topItem("Projects", "projects"),
          .topItem("Workspace", "workspace"),
          .topFeatured("wand-magic-sparkles", "Recommend", "recommend"),
        .topMenu("Statistics", list(
          list(value = "descriptive", label = "Descriptive Statistics & Correlation"),
          list(value = "tests",       label = "Statistical Tests  (t-test · Non-param · Chi-sq)"),
          list(value = "anova",       label = "ANOVA"),
          list(value = "lm",          label = "Regression  (Linear · Poly · Ridge/Lasso · Poisson)"),
          list(value = "logistic",    label = "Logistic Regression  (Multinomial)"),
          list(value = "lme",         label = "Linear Mixed Effects  (LME)"),
          list(value = "survival",    label = "Survival Analysis  (KM · Cox · Log-rank)"),
          list(value = "sem",         label = "SEM, Path & Mediation"),
          list(value = "bayesian",    label = "Bayesian Analysis"),
          list(value = "gam",         label = "Generalized Additive Models  (GAM)")
        )),
        .topMenu("Machine Learning", list(
          list(value = "rf",             label = "Random Forest"),
          list(value = "xgboost",        label = "XGBoost"),
          list(value = "dtree",          label = "Decision Trees  (rpart)"),
          list(value = "svm",            label = "Support Vector Machines"),
          list(value = "nnet_ml",        label = "Neural Networks  (nnet)"),
          list(value = "da",             label = "Discriminant Analysis  (LDA · QDA)"),
          list(value = "clustering",     label = "Clustering  (K-Means · Hierarchical)"),
          list(value = "classification", label = "Classification  (one-vs-all GLM)"),
          list(value = "pca",            label = "Dimension Reduction  (PCA · FA · MDS)")
        )),
        .topItem("Time Series", "timeseries"),
        .topMenu("Spatial Analysis", list(
          list(value = "rs_search",      label = "Download Spatial Data"),
          list(value = "raster",         label = "Raster & Vector Analysis"),
          list(value = "surface",        label = "Surface Models (DTM / DSM / CHM)"),
          list(value = "terrain",        label = "Terrain & Surface Analysis"),
          list(value = "hydro",          label = "Hydrological Analysis"),
          list(value = "suitability",    label = "Suitability Modeling"),
          list(value = "land_classify",  label = "Land Classification"),
          list(value = "ntl",            label = "Night-time Lights Regression"),
          list(value = "climate_trend",  label = "Climate Trend Analysis  (Mann-Kendall)"),
          list(value = "wind",           label = "Wind & Environmental Analysis"),
          list(value = "pointcloud",     label = "Point Cloud & 3D Viewer"),
          list(value = "chm_itd",        label = "CHM & Individual Tree Detection"),
          list(value = "metrics",        label = "Metric Extraction & Evaluation")
        )),
        .topItem("R Console", "rconsole"),
        .topItem("Documentation", "docs"),
        .topItem("References", "references")
        )   # end if(FALSE) — retired menus, now in the workspace tool dropdown
      ),

      # Right-side quick actions (pushed to far right via margin-left:auto)
      tags$div(class = "topbar-right",
        # Tool search — index of every menu item; hidden on menu-free screens
        tags$div(class = "ea-toolsearch",
          tags$input(
            id = "tool_search", class = "ea-toolsearch-input", type = "text",
            placeholder = "Search tools & analyses…", autocomplete = "off",
            oninput = "eaToolSearch(this.value)",
            onclick = "event.stopPropagation()"
          ),
          tags$div(id = "tool_search_results", class = "ea-toolsearch-results")
        ),
        # Undo
        tags$button(
          class = "topbar-action-btn tb-ws",
          title = "Undo the last data operation, up to 5 steps  (Ctrl+Z)",
          `data-tour` = "undo",
          onclick = "Shiny.setInputValue('data-undo_last', Date.now(), {priority:'event'})",
          icon("rotate-left", style = "font-size:12px;"), "Undo"
        ),
        # Reset
        tags$button(
          class = "topbar-action-btn tb-ws",
          title = "Reset active dataset to its uploaded state  (Ctrl+Shift+Z)",
          onclick = "Shiny.setInputValue('data-reset_raw', Date.now(), {priority:'event'})",
          icon("rotate", style = "font-size:12px;"), "Reset"
        ),
        # Separator (hidden with Undo/Reset on menu-free screens)
        tags$div(class = "topbar-sep tb-ws"),
        # Co-Analyst toggle (hidden on the Projects welcome-back page)
        tags$button(
          class = "topbar-action-btn tb-coanalyst",
          title = "Co-Analyst — recommend a method, or ask it to run an analysis",
          `data-tour` = "copilot",
          onclick = "document.getElementById('chat-panel').classList.toggle('open')",
          icon("wand-magic-sparkles", style = "font-size:12px;"), "Co-Analyst"
        ),
        tags$div(class = "topbar-sep tb-coanalyst"),
        # Documentation — the landing site's docs are built and linked from the
        # website, but nothing in the APP pointed at them (backlog item 17), so
        # a user who never visits the site never finds them. Opens in a new tab
        # so the running project is never navigated away from.
        tags$a(
          class = "topbar-action-btn",
          # Clean URL, no .html: landing/vercel.json sets cleanUrls, so the .html
          # form 308-redirects. Harmless in a browser, but a needless hop -- and
          # 308s have bitten this project before (backlog item 16).
          href = "https://easyanalysis.dev/documentation",
          target = "_blank", rel = "noopener",
          title = "Documentation — guides and a reference for every screen",
          `data-tour` = "docs",
          icon("book", style = "font-size:12px;"), "Docs"
        ),
        # Settings gear
        tags$button(
          class = "topbar-action-btn",
          id    = "settings-open-btn",
          title = "Settings & Preferences  (Ctrl+,)",
          onclick = "openSettings()",
          icon("gear", style = "font-size:12px;"), "Settings"
        ),
        # Quit. Separated from everything else because it is the only control up
        # here that ends the session -- and it is what makes a desktop shortcut
        # safe to launch with the console window hidden, since closing that
        # window was previously the ONLY way to stop the app.
        tags$div(class = "topbar-sep"),
        tags$button(
          class = "topbar-action-btn tb-quit",
          id    = "app-quit-btn",
          title = "Close EasyAnalysis and stop the R session",
          onclick = "eaQuitApp()",
          icon("power-off", style = "font-size:12px;"), "Quit"
        )
      )
    ),

    # Shown after Quit. The server CANNOT close the browser tab -- window.close()
    # is refused for a window the script did not open, and the launcher opens the
    # browser itself -- so say so plainly rather than leaving Shiny's grey
    # "disconnected" veil, which reads as a crash.
    tags$div(id = "ea-quit-veil",
      tags$div(class = "ea-quit-card",
        tags$div(class = "ea-quit-mark", icon("power-off")),
        tags$h3("EasyAnalysis has closed"),
        tags$p("The R session has stopped. You can close this tab now."),
        tags$p(class = "ea-quit-sub",
               "To start again, use the EasyAnalysis shortcut or run the launcher."))),

    # Shown when the connection to R drops — which happens routinely when the
    # computer SLEEPS, because the OS suspends the network stack and the
    # websocket dies. Shiny's own response is a grey veil with no way out, so
    # the app looked permanently broken and the only recourse was to hunt for
    # the launcher. This panel says what happened and offers the way back.
    #
    # It distinguishes two very different cases by probing the server, because
    # the remedy differs: if R is still running (the usual case after sleep) a
    # reload reconnects; if R has stopped, no amount of reloading will help and
    # the app has to be started again.
    tags$div(id = "ea-disconnect",
      tags$div(class = "ea-dc-card",
        tags$div(class = "ea-dc-mark", icon("plug-circle-exclamation")),
        tags$h3("Connection to R was lost"),
        tags$p(id = "ea-dc-msg", "Checking whether EasyAnalysis is still running…"),
        tags$div(class = "ea-dc-actions",
          tags$button(id = "ea-dc-reload", class = "ea-dc-btn",
                      onclick = "location.reload()", "Reconnect")),
        tags$p(class = "ea-dc-sub",
               "Your project is saved as you work, so nothing is lost."))),

    # =================== BODY ===================
    # Starts on Projects, so ship the layout class in the MARKUP. Adding it via
    # JS on DOMContentLoaded meant the rails were painted first and visibly
    # flashed before being hidden.
    tags$div(class = .main_class,

      # Left rail: Datasets
      tags$div(class = "app-left",
        tags$button(class = "rail-toggle", onclick = "toggleRail('left')",
          title = "Collapse / expand",
          HTML('<span class="chev">&#9664;</span>')),
        # The Projects screen shows project-level nav here instead of the
        # dataset tools (toggled by the view-projects class in CSS).
        projectsLeftUI("projects"),
        # The project Overview shows an informational "Project data" list here
        # (toggled by the view-project class in CSS; replaces the Datasets rail).
        projectLeftUI("project"),
        tags$div(class = "rail-body",
          tags$h6("Datasets"),
          # ONE way to add data. There is no second route and no choice to make:
          # the app runs on the same machine as the data, so a file is OPENED,
          # never copied through the browser. Offering both was complexity with
          # no upside -- the user should not have to know which is faster.
          #
          # Rendered server-side because only the server knows whether a native
          # dialog exists. Where it does not (the browser build) the same button
          # is replaced by a file input, so the control is always present and
          # always called the same thing.
          uiOutput("add_data_ui"),
          tags$p(class = "text-muted",
            style = "font-size:10px; margin-top:-4px;",
            "CSV/Excel • GeoTIFF • LAS/LAZ • Shapefile/GeoPackage"),
          actionButton("new_dataset", "Create Dataset",
            class = "btn-sm btn-outline-secondary w-100 mb-2", icon = icon("plus")),
          uiOutput("datasets_list"),
          tags$hr(),
          actionButton("view_data", "View Data Table",
            class = "btn-sm btn-outline-success w-100", icon = icon("table"))
        )
      ),

      tags$div(class = "app-divider left"),

      # Center canvas
      tags$div(class = "app-center",
        navset_hidden(id = "canvas_view",
          # Projects is FIRST => it is the default view on app start.
          .viewPanel("projects",       projectsCanvasUI("projects")),
          .viewPanel("project",        projectCanvasUI("project")),
          # UNIFIED: every analysis screen now lives INSIDE the workspace
          # (mod_workspace.R MODUI hosts each module's real Canvas/Tools UI with
          # its original namespace). Only the frame views remain as panes.
          .viewPanel("workspace",      workspaceCanvasUI("workspace"))
        )
      ),

      tags$div(class = "app-divider right"),

      # Right tools rail
      tags$div(class = "app-right",
        tags$button(class = "rail-toggle", onclick = "toggleRail('right')",
          title = "Collapse / expand",
          HTML('<span class="chev">&#9654;</span>')),
        tags$div(class = "rail-body",
          navset_hidden(id = "tools_view",
            .viewPanel("projects",       projectsToolsUI("projects")),
            .viewPanel("project",        projectToolsUI("project")),
            # UNIFIED: analysis tool panels now render inside the workspace.
            .viewPanel("workspace",      workspaceToolsUI("workspace"))
          )
        )
      )
    ),

    # =================== STATUS BAR ===================
    tags$div(class = "app-status",
      tags$span("Project: "),
      tags$strong(textOutput("status_project", inline = TRUE)),
      tags$span(class = "sep", "|"),
      tags$span("Active: "),
      tags$strong(textOutput("status_active", inline = TRUE)),
      tags$span(class = "sep", "|"),
      textOutput("status_dims", inline = TRUE),
      tags$span(class = "sep", "|"),
      tags$span("Memory: "),
      tags$strong(textOutput("status_memory", inline = TRUE),
                  title = "In-RAM size of all loaded data (rasters are disk-backed)"),
      # Project saved location — pushed right; truncates with a hover tooltip.
      tags$span(class = "status-loc", style = "margin-left:auto;",
        tags$span("Saved: "),
        tags$strong(textOutput("status_location", inline = TRUE))),
      tags$span(style = "margin-left:16px;color: var(--bark);",
        paste0("EasyAnalysis v", APP_VERSION))
    )
  ),

  # =================== SETTINGS DRAWER ===================
  # Fixed-position slide-over from the right. Backdrop overlay dismisses it.
  tags$div(
    id      = "settings-overlay",
    onclick = "closeSettings()"
  ),

  tags$div(
    id = "settings-panel",

    # Header
    tags$div(class = "settings-header",
      tags$div(class = "settings-header-title",
        icon("gear"), "Settings & Preferences"
      ),
      tags$button(class = "settings-close-btn", onclick = "closeSettings()",
        HTML("&times;"))
    ),

    # Body
    tags$div(class = "settings-body",

      # --- Section: Theme ---
      # FIRST in the panel deliberately. The theme picker used to live only in
      # the workspace's View menu, which is not reachable until a project is
      # open -- so a user could not set the appearance before starting work, or
      # from the Projects screen at all. The Settings gear is visible on every
      # screen including Projects, so putting it here is what makes the theme
      # changeable "upon the software loading".
      #
      # Client-side only: eaSetTheme() sets <html data-ea-theme> and writes
      # localStorage. No Shiny input, no server round-trip, and it survives a
      # restart. The same mechanism the View menu uses -- one implementation.
      tags$div(class = "settings-section", id = "set-theme",
        tags$p(class = "settings-section-title", "Theme"),
        tags$div(class = "set-theme-grid",
          lapply(names(ea_palettes), function(nm) {
            p <- ea_palettes[[nm]]
            tags$button(
              class = "set-theme-sw", `data-theme-name` = nm,
              title = p$label %||% nm,
              onclick = sprintf("eaSetTheme('%s')", nm),
              tags$span(class = "set-theme-chip",
                style = sprintf("background:%s; border-color:%s;",
                  p$paper  %||% ea_palette$paper,
                  p$line   %||% ea_palette$line),
                # A second dot in the set's brand colour: paper alone made the
                # two light themes indistinguishable in the picker.
                tags$span(class = "set-theme-dot",
                  style = sprintf("background:%s;",
                    p$forest %||% ea_palette$forest))),
              tags$span(class = "set-theme-lbl", p$label %||% nm))
          })
        ),
        tags$p(class = "settings-hint",
          "Applies instantly and is remembered on this computer.")
      ),

      # --- Section: Data History ---
      tags$div(class = "settings-section",
        tags$p(class = "settings-section-title", "Data History"),
        tags$div(class = "settings-action-row",
          tags$button(
            class   = "settings-action-btn",
            title   = "Undo last operation on the active dataset (Ctrl+Z)",
            onclick = "Shiny.setInputValue('data-undo_last', Date.now(), {priority:'event'}); closeSettings();",
            icon("rotate-left"), " Undo Last"
          ),
          tags$button(
            class   = "settings-action-btn",
            title   = "Restore active dataset to its original uploaded state (Ctrl+Shift+Z)",
            onclick = "Shiny.setInputValue('data-reset_raw', Date.now(), {priority:'event'}); closeSettings();",
            icon("rotate"), " Reset to Upload"
          )
        ),
        tags$p(class = "settings-hint",
          "Applies to the dataset currently active on the Data screen.")
      ),

      # --- Section: Display ---
      tags$div(class = "settings-section", id = "set-display",
        tags$p(class = "settings-section-title", "Display"),
        selectInput("setting_decimal_places", "Decimal places in summaries",
          choices  = c("2 decimal places" = 2, "3 decimal places" = 3,
                       "4 decimal places" = 4, "6 decimal places" = 6),
          selected = 3, width = "100%"
        ),
        selectInput("setting_page_length", "Rows per page in data tables",
          choices  = c("10 rows" = 10, "15 rows" = 15, "25 rows" = 25, "50 rows" = 50),
          selected = 15, width = "100%"
        ),
        selectInput("setting_na_display", "Missing value label",
          choices  = c("NA" = "NA", "— (em dash)" = "—", "(blank)" = ""),
          selected = "NA", width = "100%"
        )
      ),

      # --- Section: Data Import ---
      tags$div(class = "settings-section",
        tags$p(class = "settings-section-title", "Data Import"),
        radioButtons("setting_csv_sep", "CSV column separator",
          choices  = c("Comma  ( , )" = ",", "Semicolon  ( ; )" = ";", "Tab" = "\t"),
          selected = ",", width = "100%"
        ),
        checkboxInput("setting_auto_coerce",
          "Auto-detect numeric columns on import", value = TRUE)
      ),

      # --- Section: Map Defaults ---
      tags$div(class = "settings-section",
        tags$p(class = "settings-section-title", "Map Defaults"),
        radioButtons("setting_basemap", "Default base map",
          choices  = c("OpenStreetMap" = "OSM",
                       "Satellite (Esri)" = "Satellite",
                       "CartoDB Light" = "CartoDB"),
          selected = "OSM", width = "100%"
        ),
        checkboxInput("setting_scalebar", "Show scale bar on maps", value = TRUE)
      ),

      # --- Section: Keyboard Shortcuts ---
      tags$div(class = "settings-section", id = "set-keys",
        tags$p(class = "settings-section-title", "Keyboard Shortcuts"),
        .kbdRow("Ctrl + Z",        "Undo last data operation"),
        .kbdRow("Ctrl + Shift + Z","Reset dataset to upload"),
        .kbdRow("Ctrl + ,",        "Open settings"),
        .kbdRow("Esc",             "Close settings / modals"),
        .kbdRow("Ctrl + U",        "Focus file upload (browser)"),
        tags$p(
          style = "margin-top:10px; font-size:11px; color: var(--bark);",
          "Undo and Reset apply to the Data screen only."
        )
      ),

      # --- Section: About ---
      tags$div(class = "settings-section", id = "set-about",
        tags$p(class = "settings-section-title", "About"),
        tags$div(class = "about-logo-mark", icon("lightbulb")),
        tags$div(
          tags$span(class = "about-name", "EasyAnalysis"),
          tags$span(class = "about-version", paste0("v", APP_VERSION))
        ),
        # The version is the natural place to ask "what changed?", so it links
        # to the release notes the CI job generates from CHANGELOG.md — a user
        # who never visits the website otherwise has no way to find them
        # (backlog item 24).
        tags$p(style = "margin:2px 0 8px;",
          tags$a(href = "https://easyanalysis.dev/release-notes",
                 target = "_blank", rel = "noopener",
                 style = "font-size:12.5px; color: var(--canopy);",
                 "What's new in this version")),
        tags$p(class = "about-tagline",
          "A universal scientific analysis platform"),
        tags$p(style = "font-size:12.5px; color: var(--bark); margin:6px 0 4px; line-height:1.5;",
          "EasyAnalysis is a platform for conducting analyses without writing complex ",
          "code — upload your data and run rigorous statistical, machine-learning, ",
          "spatial/remote-sensing and time-series methods point-and-click, with ",
          "plain-English results and a Co-Analyst that can run them for you. It runs ",
          "entirely in your browser: your data never leaves your machine."),
        tags$div(class = "about-tech",
          tags$span("R 4.5.3"),
          tags$span("Shiny 1.13.0"),
          tags$span("bslib 0.10.0"),
          tags$span("terra 1.9"),
          tags$span("lidR 4.x")
        )
      ),

      # --- Section: Acknowledgements ---
      tags$div(class = "settings-section",
        tags$p(class = "settings-section-title", "Acknowledgements"),
        tags$p(style = "font-size:12.5px; color: var(--bark); margin:6px 0 0; line-height:1.5;",
          tags$b("Tim Casanda Gibson"), " — creator and lead developer."),
        tags$p(style = "font-size:12.5px; color: var(--bark); margin:6px 0 0; line-height:1.5;",
          tags$b("University of Eastern Finland"),
          " — code contributions, and data for analyses and testing.")
      )
    )
  ),

  # =================== GUIDED TOUR (spotlight overlay) ===================
  tags$div(id = "ea-tour",
    tags$div(id = "ea-tour-spot"),
    tags$div(id = "ea-tour-tip",
      tags$div(class = "sc", id = "ea-tour-step"),
      tags$div(class = "ti", id = "ea-tour-title"),
      tags$div(class = "bd", id = "ea-tour-body"),
      tags$div(class = "ft",
        tags$span(class = "dots", id = "ea-tour-dots"),
        tags$button(id = "ea-tour-skip", "Skip"),
        tags$button(id = "ea-tour-next", class = "pri", "Next")
      )
    )
  ),
  tags$script(HTML("
    (function(){
      // The tour runs INSIDE the workspace, pointing at the parts the user
      // actually works in — a tour of the welcome screen taught nothing, since
      // the welcome screen is the one place that explains itself. start()
      // switches to the workspace first and waits for it to exist.
      // A step whose target is missing is skipped; target:null = centered card.
      var STEPS = [
        { target:'.ea-wsx-left', title:'Your data lives here',
          body:'Every table, raster, point cloud and vector layer in the project. Click one to make it active; the toggle controls what the map draws.' },
        { target:'[data-tour=menu]', title:'Every tool is in these menus',
          body:'Statistics, machine learning, spatial analysis and LiDAR — all of it under Analysis and its neighbours. Nothing is exported to another program.' },
        { target:'.ea-wsx-tabs', title:'Map, data, or both',
          body:'Spatial layers open on the map; tables open in the data view. Split shows them side by side so a model and its map stay in view together.' },
        { target:'.ea-wsx-right', title:'Tool settings appear here',
          body:'Pick a tool from the menus and its settings open in this panel. Set them, then press Run.' },
        { target:'.ea-wsx-dock, .ea-wsx-canvas', title:'Results collect in the dock',
          body:'Each run is kept with its numbers and plot, so you can compare runs instead of losing the last one. Click a result to pop it out.' },
        { target:'[data-tour=copilot]', title:'Ask the Co-Analyst',
          body:'Stuck? It can run an analysis or explain a result for you, in plain language.' },
        { target:'.ea-toolsearch', title:'Or just search for it',
          body:'Type what you want to do — regression, raster, DTM — and it finds the tool for you. Faster than remembering which menu a thing lives under.' },
        { target:'[data-tour=undo]', title:'Changes are reversible',
          body:'Every data operation can be undone, up to five steps back. Reset returns the active dataset to the state it was uploaded in.' },
        { target:'[data-tour=docs]', title:'Full documentation',
          body:'Guides, worked examples and a reference for every screen — opens on the website. Your project stays exactly as you left it.' }
      ];
      var i = 0, ov, spot, tip;
      function el(id){ return document.getElementById(id); }
      function firstMatch(sel){ if(!sel) return null;
        var parts = sel.split(','); for(var k=0;k<parts.length;k++){
          var e = document.querySelector(parts[k].trim());
          if(e && e.getClientRects().length) return e; } return null; }
      function render(){
        var s = STEPS[i]; if(!s){ stop(); return; }
        var t = firstMatch(s.target);
        if(s.target && !t){                    // anchor absent here — skip it
          if(i >= STEPS.length-1){ stop(); return; }
          i++; render(); return;
        }
        el('ea-tour-step').textContent = 'Step ' + (i+1) + ' of ' + STEPS.length;
        el('ea-tour-title').textContent = s.title;
        el('ea-tour-body').textContent = s.body;
        el('ea-tour-dots').innerHTML = STEPS.map(function(_,j){ return '<i class=\"'+(j===i?'on':'')+'\"></i>'; }).join('');
        el('ea-tour-next').textContent = (i===STEPS.length-1) ? 'Done' : 'Next';
        if(t){
          var r = t.getBoundingClientRect(), pad = 6;
          spot.style.opacity = 1;
          spot.style.left = (r.left-pad)+'px'; spot.style.top = (r.top-pad)+'px';
          spot.style.width = (r.width+pad*2)+'px'; spot.style.height = (r.height+pad*2)+'px';
          var tx = r.left, ty = r.bottom + 12;
          if(ty + 190 > window.innerHeight) ty = Math.max(12, r.top - 190);
          tx = Math.min(Math.max(12, tx), window.innerWidth - 300);
          tip.style.left = tx+'px'; tip.style.top = ty+'px';
        } else {
          spot.style.opacity = 0; spot.style.width = spot.style.height = '0px';
          spot.style.left = '50%'; spot.style.top = '50%';
          tip.style.left = (window.innerWidth/2 - 144)+'px';
          tip.style.top  = (window.innerHeight/2 - 90)+'px';
        }
      }
      function inWorkspace(){ var g = document.querySelector('.ea-wsx-grid');
        return !!(g && g.getClientRects().length); }
      function start(){ ov=el('ea-tour'); spot=el('ea-tour-spot'); tip=el('ea-tour-tip');
        if(!ov) return;
        // Every step describes the workspace, so go there first. View panes are
        // hidden (and their outputs suspended) until Shiny switches them, so
        // poll for the grid instead of assuming it is up.
        if(!inWorkspace() && window.Shiny){
          try{ Shiny.setInputValue('current_view','workspace',{priority:'event'}); }catch(e){}
        }
        var tries = 0;
        (function wait(){
          if(inWorkspace() || tries++ > 40){ i=0; ov.classList.add('on'); render(); return; }
          setTimeout(wait, 100);
        })();
      }
      function next(){ if(i>=STEPS.length-1){ stop(); return; } i++; render(); }
      function stop(){ if(ov) ov.classList.remove('on');
        try{ localStorage.setItem('ea-tour-seen','1'); }catch(e){} }
      window.eaStartTour = start;
      document.addEventListener('DOMContentLoaded', function(){
        el('ea-tour-next').addEventListener('click', next);
        el('ea-tour-skip').addEventListener('click', stop);
        document.addEventListener('keydown', function(e){
          if(!el('ea-tour').classList.contains('on')) return;
          if(e.key==='Escape') stop();
          else if(e.key==='ArrowRight'||e.key==='Enter') next();
        });
        window.addEventListener('resize', function(){
          if(el('ea-tour').classList.contains('on')) render(); });
      });
      if(window.Shiny) Shiny.addCustomMessageHandler('ea-tour', function(m){
        if(m==='start') start();
      });
    })();
  ")),

  # Hidden download targets — the workspace Project menu clicks these.
  tags$div(class = "ea-hidden-file",
    downloadLink("ws_export", "Save as .eap", class = "ea-eap-save"),
    downloadLink("ws_report", "Export report")),

  # =================== AI CO-PILOT (floating) ===================
  chatUI("chat")
)
}
