# ==========================================================================
# references.R — the papers whose methodology is implemented in the app.
# --------------------------------------------------------------------------
# Single source of truth for the in-app References screen. Keep in sync with
# papers/METHODS.md (the developer catalog). Each entry: full citation + the
# named method(s) derived from it + where it is used in the app.
# referencesCanvasUI / referencesToolsUI are static (no server binding needed).
# ==========================================================================

APP_REFERENCES <- list(
  list(
    authors = "Kalliovirta, J. & Tokola, T.",
    year    = 2005,
    title   = "Functions for estimating stem diameter and tree age using tree height, crown width and existing stand database information.",
    source  = "Silva Fennica 39(2): 227–248.",
    doi     = "https://doi.org/10.14214/sf.386",
    methods = c("Diameter model — Kalliovirta & Tokola 2005",
                "Age model — Kalliovirta & Tokola 2005"),
    used_for = paste("Bias-corrected transformed-response regression: fit on a",
                     "log- or sqrt-transformed Y, then back-transform predictions to",
                     "the original scale with the lognormal / variance correction.",
                     "Available in Linear Regression (Transform Y + “Back-transform",
                     "to original scale”)."),
    status  = "implemented"
  )
)

# ---- one reference card ----------------------------------------------------
.reference_card <- function(r) {
  badge_col <- switch(r$status %||% "cataloged",
    implemented = "#2e7d32", partial = "#f9a825", "#6c757d")
  badge_txt <- switch(r$status %||% "cataloged",
    implemented = "Implemented", partial = "In progress", "Cataloged")
  tags$div(
    style = "border:1px solid #e3e8e3;border-radius:12px;padding:16px 18px;margin-bottom:14px;background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.04);",
    tags$div(style = "display:flex;justify-content:space-between;align-items:flex-start;gap:12px;",
      tags$div(
        tags$strong(style = "font-size:15px;", sprintf("%s (%d)", r$authors, r$year)),
        tags$div(style = "font-size:13.5px;margin-top:2px;", r$title),
        tags$div(style = "font-size:12.5px;color:#6c757d;font-style:italic;margin-top:2px;", r$source)
      ),
      tags$span(style = sprintf("flex:0 0 auto;background:%s;color:#fff;border-radius:12px;padding:2px 10px;font-size:11px;font-weight:700;", badge_col),
        badge_txt)
    ),
    tags$div(style = "margin-top:10px;",
      tags$div(style = "font-size:11px;text-transform:uppercase;letter-spacing:.6px;color:#2e7d32;font-weight:700;", "Methods"),
      tags$ul(style = "margin:4px 0 0;padding-left:18px;font-size:13px;",
        lapply(r$methods, function(m) tags$li(m)))
    ),
    tags$div(style = "margin-top:8px;font-size:12.5px;color:#495057;",
      tags$span(style = "font-weight:700;color:#2e7d32;", "Used for: "), r$used_for),
    if (!is.null(r$doi) && nzchar(r$doi))
      tags$a(href = r$doi, target = "_blank", style = "font-size:12px;display:inline-block;margin-top:8px;", r$doi)
  )
}

referencesCanvasUI <- function(id) {
  ns <- NS(id)
  tags$div(style = "max-width:900px;margin:0 auto;padding:18px 6px;",
    tags$h4(style = "color:#2e7d32;font-weight:700;", "References"),
    tags$p(style = "color:#6c757d;font-size:13.5px;",
      "Published methods implemented in EasyAnalysis. Each analysis derived from a",
      "paper is named after its authors and cited here."),
    tags$hr(),
    lapply(APP_REFERENCES, .reference_card),
    tags$p(style = "color:#adb5bd;font-size:11.5px;margin-top:6px;",
      "Cite the original papers when reporting results produced with these methods.")
  )
}

referencesToolsUI <- function(id) {
  ns <- NS(id)
  tags$div(
    tags$h6(class = "text-uppercase text-muted small", "References"),
    tags$p(style = "font-size:12.5px;color:#6c757d;",
      sprintf("%d paper%s implemented.", length(APP_REFERENCES),
              if (length(APP_REFERENCES) == 1) "" else "s")),
    tags$p(style = "font-size:12px;color:#adb5bd;",
      "New papers are added here as their methods are implemented.")
  )
}
