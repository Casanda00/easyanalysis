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
      " padding:5px 0; border-bottom:1px solid #f1f3f4; font-size:12px;"
    ),
    tags$span(style = "display:flex; align-items:center; gap:3px; flex-shrink:0;",
      lapply(strsplit(keys, "\\+")[[1]], function(k)
        tags$kbd(style = paste0(
          "background:#f1f3f5; border:1px solid #ced4da; border-radius:3px;",
          " padding:1px 5px; font-size:10px; font-family:monospace; color:#495057;"),
          trimws(k)
        )
      )
    ),
    tags$span(style = "color:#6c757d;", desc)
  )
}

ui <- page_fillable(
  theme   = app_theme,
  padding = 0,
  gap     = 0,

  tags$head(
    tags$style(HTML("
    html, body { height: 100%; }
    .app-shell { display: grid; grid-template-rows: auto 1fr auto; height: 100vh; }

    /* ---- Top menubar ---- */
    .app-topbar {
      background: #2e7d32; color: #fff;
      display: flex; align-items: center; gap: 6px;
      padding: 0 8px; height: 40px;
      box-shadow: 0 1px 4px rgba(0,0,0,.18);
    }
    .app-topbar .brand {
      font-weight: 700; font-size: 15px; letter-spacing: .4px;
      margin-right: 6px; white-space: nowrap;
      display: flex; align-items: center; gap: 6px;
    }
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
    .app-topbar .dropdown-item:hover { background: #e8f5e9; color: #1b5e20; }
    .app-topbar .dropdown-item.active,
    .app-topbar .dropdown-item:active { background: #2e7d32; color: #fff; }

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
    .topbar-sep {
      width: 1px; height: 20px;
      background: rgba(255,255,255,.28); margin: 0 4px;
    }

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
    .app-left, .app-right {
      background: #f8faf8; overflow-y: auto; padding: 10px; position: relative;
    }
    .app-left  { border-right: 1px solid #dee2e6; }
    .app-right { border-left:  1px solid #dee2e6; }
    .app-center { overflow: auto; padding: 10px; min-width: 0; }
    .app-left h6 {
      text-transform: uppercase; font-size: 11px;
      letter-spacing: .6px; color: #6c757d;
    }
    .app-main.left-collapsed  .app-left  .rail-body,
    .app-main.right-collapsed .app-right .rail-body { display: none; }
    .app-main.left-collapsed  .app-left,
    .app-main.right-collapsed .app-right { padding: 8px 2px; overflow: hidden; }

    /* ---- Resize dividers ---- */
    .app-divider { cursor: col-resize; background: transparent; transition: background .1s; }
    .app-divider:hover, .app-divider.dragging { background: #4caf50; }
    .app-main.left-collapsed  .app-divider.left,
    .app-main.right-collapsed .app-divider.right { pointer-events: none; }

    /* ---- Rail collapse toggles ---- */
    .rail-toggle {
      border: none; background: transparent; color: #6c757d;
      cursor: pointer; font-size: 13px; padding: 0 4px; line-height: 1.4;
    }
    .rail-toggle:hover { color: #2e7d32; }
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
    .ds-item:hover { background: #e8f5e9; }
    .ds-item.active { background: #2e7d32; color: #fff; }
    .ds-item .dot {
      width: 8px; height: 8px; border-radius: 50%;
      background: #4caf50; flex: 0 0 auto;
    }
    .ds-item.active .dot { background: #fff; }

    /* ---- Status bar ---- */
    .app-status {
      background: #eef3ee; border-top: 1px solid #dee2e6;
      font-size: 12px; color: #495057;
      display: flex; align-items: center; gap: 18px; padding: 3px 14px;
    }
    .app-status .sep { color: #adb5bd; }

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
      background: #fff;
      box-shadow: -4px 0 24px rgba(0,0,0,.18);
      transition: right .25s cubic-bezier(.4,0,.2,1);
      display: flex; flex-direction: column;
      font-size: 13px;
    }
    #settings-panel.open { right: 0; }
    .settings-header {
      background: #1b5e20;
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
      border-bottom: 1px solid #f0f0f0;
    }
    .settings-section:last-child { border-bottom: none; }
    .settings-section-title {
      font-size: 10px; text-transform: uppercase; letter-spacing: 1.2px;
      color: #2e7d32; font-weight: 700; margin: 0 0 12px 0;
    }
    .settings-section .form-label,
    .settings-section label { font-size: 12px !important; color: #495057; }
    .settings-section .form-control,
    .settings-section .form-select { font-size: 12px !important; }
    .settings-action-row { display: flex; gap: 8px; margin-bottom: 8px; }
    .settings-action-btn {
      flex: 1; background: #f8f9fa; border: 1px solid #dee2e6;
      border-radius: 6px; padding: 7px 10px; font-size: 12px; cursor: pointer;
      display: flex; align-items: center; justify-content: center; gap: 6px;
      color: #495057; transition: background .14s, border-color .14s, color .14s;
    }
    .settings-action-btn:hover {
      background: #e8f5e9; border-color: #4caf50; color: #1b5e20;
    }
    .settings-action-btn .fa { font-size: 13px; }
    .settings-hint { font-size: 11px; color: #adb5bd; margin: 0; }
    /* Keyboard shortcut rows */
    .kbd-row {
      display: flex; align-items: center; justify-content: space-between;
      padding: 5px 0; border-bottom: 1px solid #f4f4f4; font-size: 12px;
    }
    .kbd-row:last-child { border-bottom: none; }
    .kbd-keys { display: flex; align-items: center; gap: 3px; flex-shrink: 0; }
    kbd {
      background: #f1f3f5; border: 1px solid #ced4da; border-bottom-width: 2px;
      border-radius: 3px; padding: 1px 5px;
      font-size: 10px; font-family: ui-monospace, monospace; color: #495057;
    }
    .kbd-desc { color: #6c757d; }
    /* About block */
    .about-logo-mark {
      display: inline-flex; align-items: center; justify-content: center;
      width: 36px; height: 36px; border-radius: 8px;
      background: #2e7d32; color: #fff;
      font-weight: 800; font-size: 14px; letter-spacing: -.5px;
      margin-bottom: 8px;
    }
    .about-name { font-size: 15px; font-weight: 700; color: #1b5e20; }
    .about-version {
      display: inline-block; background: #e8f5e9; color: #2e7d32;
      font-size: 10px; font-weight: 600; padding: 1px 7px;
      border-radius: 10px; margin-left: 6px; vertical-align: middle;
    }
    .about-tagline { font-size: 12px; color: #6c757d; margin: 4px 0 10px; }
    .about-tech { display: flex; flex-wrap: wrap; gap: 5px; margin-top: 8px; }
    .about-tech span {
      background: #f1f3f5; color: #495057; font-size: 11px;
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
      background: rgba(255,255,255,.88); border: 1px solid #dee2e6;
      border-radius: 4px; padding: 3px 8px; font-size: 11px;
      cursor: pointer; color: #495057; display: none;
      transition: background .1s, border-color .1s, color .1s;
      line-height: 1.4;
    }
    .shiny-plot-output:hover .plot-dl-btn { display: inline-block; }
    .plot-dl-btn:hover { background:#e8f5e9; border-color:#4caf50; color:#1b5e20; }
    ")),

    tags$script(HTML("
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

      /* ---- Settings drawer ---- */
      function openSettings(){
        var p  = document.getElementById('settings-panel');
        var ov = document.getElementById('settings-overlay');
        ov.style.display = 'block';
        requestAnimationFrame(function(){
          p.classList.add('open');
          ov.style.opacity = '1';
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
        /* Escape  — Close settings */
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
    "))
  ),

  tags$div(class = "app-shell",

    # =================== TOP MENUBAR ===================
    tags$div(class = "app-topbar",

      # Brand
      tags$span(class = "brand",
        tags$span(class = "brand-dot"),
        "SimpleAnalysis"
      ),

      # Main navigation
      tags$ul(class = "nav",
        .topItem("Data", "data"),
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
        ))
      ),

      # Right-side quick actions (pushed to far right via margin-left:auto)
      tags$div(class = "topbar-right",
        # Undo
        tags$button(
          class = "topbar-action-btn",
          title = "Undo last data operation  (Ctrl+Z)",
          onclick = "Shiny.setInputValue('data-undo_last', Date.now(), {priority:'event'})",
          icon("rotate-left", style = "font-size:12px;"), "Undo"
        ),
        # Reset
        tags$button(
          class = "topbar-action-btn",
          title = "Reset active dataset to its uploaded state  (Ctrl+Shift+Z)",
          onclick = "Shiny.setInputValue('data-reset_raw', Date.now(), {priority:'event'})",
          icon("rotate", style = "font-size:12px;"), "Reset"
        ),
        # Separator
        tags$div(class = "topbar-sep"),
        # AI Co-Pilot toggle
        tags$button(
          class = "topbar-action-btn",
          title = "Ask AI Co-Pilot",
          onclick = "document.getElementById('chat-panel').classList.toggle('open')",
          icon("robot", style = "font-size:12px;"), "Co-Pilot"
        ),
        tags$div(class = "topbar-sep"),
        # Settings gear
        tags$button(
          class = "topbar-action-btn",
          id    = "settings-open-btn",
          title = "Settings & Preferences  (Ctrl+,)",
          onclick = "openSettings()",
          icon("gear", style = "font-size:12px;"), "Settings"
        )
      )
    ),

    # =================== BODY ===================
    tags$div(class = "app-main",

      # Left rail: Datasets
      tags$div(class = "app-left",
        tags$button(class = "rail-toggle", onclick = "toggleRail('left')",
          title = "Collapse / expand",
          HTML('<span class="chev">&#9664;</span>')),
        tags$div(class = "rail-body",
          tags$h6("Datasets"),
          fileInput("upload_files", NULL, multiple = TRUE,
            accept = c(".csv", ".txt", ".xlsx", ".xls",
                       ".tif", ".tiff", ".img", ".asc", ".nc", ".grd",
                       ".las", ".laz",
                       ".gpkg", ".geojson", ".json",
                       ".shp", ".shx", ".dbf", ".prj", ".cpg"),
            buttonLabel = "Upload Data", placeholder = "no file"),
          tags$p(class = "text-muted",
            style = "font-size:10px; margin-top:-8px;",
            "CSV/Excel • GeoTIFF • LAS/LAZ • Shapefile/GeoPackage"),
          actionButton("new_dataset", "New Dataset",
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
          .viewPanel("data",           dataCanvasUI("data")),
          .viewPanel("descriptive",    descriptiveCanvasUI("descriptive")),
          .viewPanel("tests",          testsCanvasUI("tests")),
          .viewPanel("pca",            pcaCanvasUI("pca")),
          .viewPanel("timeseries",     timeseriesCanvasUI("timeseries")),
          .viewPanel("survival",       survivalCanvasUI("survival")),
          .viewPanel("sem",            semCanvasUI("sem")),
          .viewPanel("bayesian",       bayesianCanvasUI("bayesian")),
          .viewPanel("xgboost",        xgboostCanvasUI("xgboost")),
          .viewPanel("dtree",          dtreeCanvasUI("dtree")),
          .viewPanel("nnet_ml",        nnetMlCanvasUI("nnet_ml")),
          .viewPanel("svm",            svmCanvasUI("svm")),
          .viewPanel("lm",             lmCanvasUI("lm")),
          .viewPanel("lme",            lmeCanvasUI("lme")),
          .viewPanel("anova",          anovaCanvasUI("anova")),
          .viewPanel("logistic",       logisticCanvasUI("logistic")),
          .viewPanel("rf",             rfCanvasUI("rf")),
          .viewPanel("da",             daCanvasUI("da")),
          .viewPanel("clustering",     clusteringCanvasUI("clustering")),
          .viewPanel("classification", classificationCanvasUI("classification")),
          .viewPanel("raster",        rasterCanvasUI("raster")),
          .viewPanel("surface",       surfaceCanvasUI("surface")),
          .viewPanel("terrain",       terrainCanvasUI("terrain")),
          .viewPanel("hydro",         hydroCanvasUI("hydro")),
          .viewPanel("suitability",   suitabilityCanvasUI("suitability")),
          .viewPanel("land_classify", landClassifyCanvasUI("land_classify")),
          .viewPanel("recommend",      recommendCanvasUI("recommend")),
          .viewPanel("rs_search",     rsSearchCanvasUI("rs_search")),
          .viewPanel("ntl",            ntlCanvasUI("ntl")),
          .viewPanel("climate_trend",  climateTrendCanvasUI("climate_trend")),
          .viewPanel("wind",           windCanvasUI("wind")),
          .viewPanel("gam",            gamCanvasUI("gam")),
          .viewPanel("pointcloud",     lidarPointcloudCanvasUI("lidar")),
          .viewPanel("chm_itd",        lidarChmCanvasUI("lidar")),
          .viewPanel("metrics",        lidarMetricsCanvasUI("lidar"))
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
            .viewPanel("data",
              tags$div(
                tags$h6(class = "text-uppercase text-muted small", "Processing Toolbox"),
                dataToolsUI("data")
              )
            ),
            .viewPanel("descriptive",    descriptiveToolsUI("descriptive")),
            .viewPanel("tests",          testsToolsUI("tests")),
            .viewPanel("pca",            pcaToolsUI("pca")),
            .viewPanel("timeseries",     timeseriesToolsUI("timeseries")),
            .viewPanel("survival",       survivalToolsUI("survival")),
            .viewPanel("sem",            semToolsUI("sem")),
            .viewPanel("bayesian",       bayesianToolsUI("bayesian")),
            .viewPanel("xgboost",        xgboostToolsUI("xgboost")),
            .viewPanel("dtree",          dtreeToolsUI("dtree")),
            .viewPanel("nnet_ml",        nnetMlToolsUI("nnet_ml")),
            .viewPanel("svm",            svmToolsUI("svm")),
            .viewPanel("lm",             lmToolsUI("lm")),
            .viewPanel("lme",            lmeToolsUI("lme")),
            .viewPanel("anova",          anovaToolsUI("anova")),
            .viewPanel("logistic",       logisticToolsUI("logistic")),
            .viewPanel("rf",             rfToolsUI("rf")),
            .viewPanel("da",             daToolsUI("da")),
            .viewPanel("clustering",     clusteringToolsUI("clustering")),
            .viewPanel("classification", classificationToolsUI("classification")),
            .viewPanel("raster",        rasterToolsUI("raster")),
            .viewPanel("surface",       surfaceToolsUI("surface")),
            .viewPanel("terrain",       terrainToolsUI("terrain")),
            .viewPanel("hydro",         hydroToolsUI("hydro")),
            .viewPanel("suitability",   suitabilityToolsUI("suitability")),
            .viewPanel("land_classify", landClassifyToolsUI("land_classify")),
            .viewPanel("recommend",      recommendToolsUI("recommend")),
            .viewPanel("rs_search",     rsSearchToolsUI("rs_search")),
            .viewPanel("ntl",            ntlToolsUI("ntl")),
            .viewPanel("climate_trend",  climateTrendToolsUI("climate_trend")),
            .viewPanel("wind",           windToolsUI("wind")),
            .viewPanel("gam",            gamToolsUI("gam")),
            .viewPanel("pointcloud",     lidarPointcloudToolsUI("lidar")),
            .viewPanel("chm_itd",        lidarChmToolsUI("lidar")),
            .viewPanel("metrics",        lidarMetricsToolsUI("lidar"))
          )
        )
      )
    ),

    # =================== STATUS BAR ===================
    tags$div(class = "app-status",
      tags$span("Active: "),
      tags$strong(textOutput("status_active", inline = TRUE)),
      tags$span(class = "sep", "|"),
      textOutput("status_dims", inline = TRUE)
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
      tags$div(class = "settings-section",
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
      tags$div(class = "settings-section",
        tags$p(class = "settings-section-title", "Keyboard Shortcuts"),
        .kbdRow("Ctrl + Z",        "Undo last data operation"),
        .kbdRow("Ctrl + Shift + Z","Reset dataset to upload"),
        .kbdRow("Ctrl + ,",        "Open settings"),
        .kbdRow("Esc",             "Close settings / modals"),
        .kbdRow("Ctrl + U",        "Focus file upload (browser)"),
        tags$p(
          style = "margin-top:10px; font-size:11px; color:#adb5bd;",
          "Undo and Reset apply to the Data screen only."
        )
      ),

      # --- Section: About ---
      tags$div(class = "settings-section",
        tags$p(class = "settings-section-title", "About"),
        tags$div(class = "about-logo-mark", "SA"),
        tags$div(
          tags$span(class = "about-name", "SimpleAnalysis"),
          tags$span(class = "about-version", "v0.9.0")
        ),
        tags$p(class = "about-tagline",
          "Forest Trafficability & Tree Growth Modeling"),
        tags$p(style = "font-size:12px; color:#6c757d; margin:0;",
          "University of Eastern Finland"),
        tags$div(class = "about-tech",
          tags$span("R 4.5.3"),
          tags$span("Shiny 1.13.0"),
          tags$span("bslib 0.10.0"),
          tags$span("terra 1.9"),
          tags$span("lidR 4.x")
        )
      )
    )
  ),

  # =================== AI CO-PILOT (floating) ===================
  chatUI("chat")
)
