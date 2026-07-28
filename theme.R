# ==========================================================================
# theme.R  --  THE single source of truth for colour in EasyAnalysis
# --------------------------------------------------------------------------
# Change a colour HERE and it propagates everywhere:
#   ea_theme()    -> the bslib theme  (Bootstrap components: buttons, modals,
#                    inputs, cards, navs — everything bslib renders)
#   ea_css_vars() -> the :root CSS variables used by the hand-written shell
#                    and every .ea-* rule in ui.R
# Nothing else in the app should contain a raw hex value. If you find one,
# it belongs in this palette.
#
# Neutrals are deliberately GREEN-BIASED (not pure grey) so the whole surface
# reads as one system rather than a green accent bolted onto grey chrome.
# ==========================================================================

ea_palette <- list(
  # --- surfaces (darkest -> lightest) ---
  paper  = "#0F1310",  # app background
  panel  = "#171C17",  # cards, raised surfaces
  sunk   = "#131813",  # rails, wells, inputs
  bar    = "#1B3A1D",  # top menubar
  tint   = "#1D2A1E",  # subtle green fill (hover, card headers)

  # --- text ---
  ink    = "#E8EDE4",  # primary text
  bark   = "#93A08C",  # secondary text / labels
  line   = "#2A322A",  # borders & dividers

  # --- brand ---
  forest = "#5FBF62",  # primary green (lifted for contrast on dark)
  canopy = "#7ED481",  # lighter accent
  onbrand= "#08120A",  # text that sits ON a brand-green fill

  # --- semantic (kept separate from the brand hue on purpose) ---
  warn   = "#E0A458",
  danger = "#D9694F",

  # --- type ---
  mono   = "ui-monospace, 'Cascadia Code', Consolas, monospace"
)

# The bslib theme. Everything Bootstrap renders inherits from this.
ea_theme <- function(p = ea_palette) {
  bslib::bs_theme(
    preset    = "zephyr",
    bg        = p$paper,
    fg        = p$ink,
    primary   = p$forest,
    secondary = p$canopy,
    success   = p$canopy,
    info      = p$canopy,
    warning   = p$warn,
    danger    = p$danger
  )
}

# The same palette as CSS custom properties, for the hand-written CSS in ui.R.
# Generated from the list above so the two can never drift apart.
ea_css_vars <- function(p = ea_palette) {
  paste0(
    ":root{\n",
    paste0("  --", names(p), ": ", unlist(p), ";", collapse = "\n"),
    "\n}\n"
  )
}

# ==========================================================================
# COLOUR SETS — the whole app re-skins by swapping these variables.
# Each set overrides the same keys as ea_palette; anything omitted falls back
# to the default (forest) values, so a set only states what it changes.
# Switching is instant and client-side: <html data-ea-theme="light">.
# ==========================================================================
ea_palettes <- list(
  forest = list(   # default — dark, green-biased neutrals
    label = "Forest (dark)"
  ),
  light = list(
    label  = "Light",
    paper  = "#F7F8F4", panel = "#FFFFFF", sunk = "#EEF1EA", bar = "#2E7D32", tint = "#E7F0E7",
    ink    = "#10150F", bark  = "#5C6657", line = "#DCE1D6",
    forest = "#2E7D32", canopy = "#3E9B44", onbrand = "#FFFFFF",
    warn   = "#B37514", danger = "#B23C23"
  ),
  midnight = list( # true black, high contrast
    label  = "Midnight (black)",
    paper  = "#000000", panel = "#0C0F0C", sunk = "#070907", bar = "#0F1A10", tint = "#141A14",
    ink    = "#EDEFEA", bark  = "#8A9487", line = "#242A24",
    forest = "#4CD964", canopy = "#7BE58E", onbrand = "#04140A"
  ),
  ocean = list(    # cool blue-teal dark
    label  = "Ocean",
    paper  = "#0B1013", panel = "#121A1F", sunk = "#0E161A", bar = "#123243", tint = "#16252C",
    ink    = "#E4EDF1", bark  = "#8CA2AC", line = "#243239",
    forest = "#3FB8C4", canopy = "#6FD6DE", onbrand = "#04161A"
  ),
  plum = list(     # deep violet dark
    label  = "Plum",
    paper  = "#0F0C13", panel = "#171320", sunk = "#120F18", bar = "#2B1B47", tint = "#221A2E",
    ink    = "#ECE7F2", bark  = "#9D93AC", line = "#2C2438",
    forest = "#A77BE0", canopy = "#C4A4F0", onbrand = "#120A1C"
  ),
  paperwhite = list(  # warm light, low glare
    label  = "Paper (warm light)",
    paper  = "#FAF7F0", panel = "#FFFFFF", sunk = "#F1ECE1", bar = "#3B5D3F", tint = "#EAF0E6",
    ink    = "#1A1712", bark  = "#6B6355", line = "#E0D8C8",
    forest = "#3B7A43", canopy = "#4E9A57", onbrand = "#FFFFFF",
    warn   = "#A96A12", danger = "#A83A22"
  )
)

# CSS for every colour set: :root holds the default, each other set is applied
# via html[data-ea-theme="<name>"]. Emitted once; switching costs nothing.
ea_theme_css <- function(sets = ea_palettes, base = ea_palette) {
  blocks <- vapply(names(sets), function(nm) {
    p <- sets[[nm]]; p$label <- NULL
    if (!length(p)) return("")                 # default set = :root already
    paste0("html[data-ea-theme=\"", nm, "\"]{\n",
           paste0("  --", names(p), ": ", unlist(p), ";", collapse = "\n"), "\n}\n")
  }, character(1))
  paste(blocks, collapse = "")
}
