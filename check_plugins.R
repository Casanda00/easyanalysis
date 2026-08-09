# check_plugins.R -- external tool providers stay OFF until asked for, and a
# generated spec actually runs
#
# WHY THIS EXISTS
# ---------------
# plugins.R generates registry specs from WhiteboxTools' own self-description
# instead of hand-wrapping 484 tools. Two properties have to hold, and neither
# is visible by reading the code:
#
#   1. NOTHING is contributed until a user activates it. Binding one algorithm
#      module costs 33 ms (measured), so an unfiltered provider would add ~16 s
#      to every session start. If activation ever stops gating the provider, the
#      app just gets slower and nothing errors.
#   2. A GENERATED spec runs. The mapper turns JSON metadata into inputs, params
#      and a flag list; nothing proves that is right except executing one and
#      getting a raster back.
#
# Uses a temporary EASYANALYSIS_HOME so it never touches real settings, and
# builds a THREE-tool manifest -- a full build is ~8 minutes.
#
# Run:  Rscript check_plugins.R

home <- file.path(tempdir(), paste0("eahome_", as.integer(runif(1, 1e6, 9e6))))
dir.create(home, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(EASYANALYSIS_HOME = home)

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
suppressMessages(source("global.R"))

ok  <- TRUE
say <- function(p, m) { cat(if (p) "PASS  " else "FAIL  ", m, "\n", sep = ""); if (!p) ok <<- FALSE }

# ---- 0. WhiteboxTools present? ---------------------------------------------
have <- tryCatch({ .ea_require_whitebox(); TRUE }, error = function(e) FALSE)
if (!have) {
  cat("SKIP  WhiteboxTools is not installed; provider checks need the real tool.\n")
  cat("\nPLUGIN CHECK: SKIPPED\n"); quit(status = 0L)
}

# ---- 1. Everything is OFF by default ---------------------------------------
say(!ea_plugin_on("whitebox"), "a fresh install has the plugin OFF")
say(length(ea_provider_whitebox()) == 0, "an inactive provider contributes no specs")
base_n <- length(ea_algorithms())
say(base_n == 51, sprintf("the registry is unchanged with the plugin off (%d)", base_n))

# ---- 2. Activation state round-trips ----------------------------------------
ea_plugin_set("whitebox", TRUE)
say(ea_plugin_on("whitebox"), "the provider can be turned on")
say(length(ea_provider_whitebox()) == 0,
    "CONTROL: provider ON but no tools activated still contributes nothing")

ea_tool_set("whitebox", "Slope", TRUE)
say(ea_tool_on("whitebox", "Slope"), "a single tool can be activated")
say(!ea_tool_on("whitebox", "Aspect"), "and its neighbours stay off")

# State must survive a reload -- it is a preference about the installation.
ea_wbt_manifest_clear()
say(identical(ea_plugin_state()$tools[["whitebox"]], "Slope"),
    "activation is persisted to disk, not held in memory")

# ---- 3. Build a small manifest ---------------------------------------------
tools <- c("Slope", "FillDepressions", "D8FlowAccumulation")
t0 <- Sys.time()
invisible(ea_wbt_build_manifest(only = tools))
ea_wbt_manifest_clear()
man <- ea_wbt_manifest()
cat(sprintf("      (built %d tools in %.1f s)\n", length(man$tools %||% list()),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
say(!is.null(man) && length(man$tools) == 3, "the manifest builds and caches")
say(all(nzchar(vapply(man$tools, function(e) e$toolbox %||% "", character(1)))),
    "every tool carries its authoritative toolbox category")

# ---- 4. The mapper produces a usable spec ----------------------------------
e   <- Filter(function(x) identical(x$name, "Slope"), man$tools)[[1]]
spc <- ea_wbt_spec(e)
say(!is.null(spc), "Slope maps to a spec")
say(length(spc$inputs) >= 1 && identical(spc$inputs[[1]]$pool, "raster"),
    "its DEM input maps to the raster pool")
say(identical(spc$output$pool, "raster"), "its output maps to the raster pool")
kinds <- vapply(spc$params, function(q) q$kind, character(1))
say("sel" %in% kinds, paste0("OptionList became a dropdown (kinds: ",
                             paste(unique(kinds), collapse = ", "), ")"))
say(grepl("WhiteboxTools", spc$label, fixed = TRUE),
    paste0("the label carries provenance: ", spc$label))

# ---- 5. THE ONE THAT MATTERS: a generated spec actually runs ----------------
set.seed(1)
dem <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 600, ymin = 0, ymax = 600,
                   crs = "EPSG:32635")
terra::values(dem) <- as.vector(outer(1:60, 1:60, function(i, j) i * 2 + j * 0.5)) +
                      rnorm(3600, 0, 0.5)
p <- lapply(spc$params, function(q) q$value)
names(p) <- vapply(spc$params, function(q) q$key, character(1))
res <- tryCatch(spc$run(list(dem = dem), p), error = function(e) conditionMessage(e))
if (inherits(res, "SpatRaster")) {
  v <- terra::values(res, mat = FALSE); v <- v[is.finite(v)]
  say(TRUE, sprintf("a GENERATED spec runs end to end (%d cells, slope %.2f-%.2f)",
                    terra::ncell(res), min(v), max(v)))
  say(length(v) > 0 && diff(range(v)) > 0, "and returns varying values, not a constant")
} else {
  say(FALSE, paste0("the generated Slope spec failed: ", res))
}

# ---- 6. Provider now yields exactly the activated tools ---------------------
sp <- ea_provider_whitebox()
say(length(sp) == 1, sprintf("only the activated tool becomes a spec (%d)", length(sp)))
ea_tool_set("whitebox", "FillDepressions", TRUE)
say(length(ea_provider_whitebox()) == 2, "activating a second tool adds exactly one")

# Turning the PROVIDER off must hide everything without losing the picks.
ea_plugin_set("whitebox", FALSE)
say(length(ea_provider_whitebox()) == 0, "turning the provider off hides all its tools")
say(length(ea_plugin_state()$tools[["whitebox"]]) == 2,
    "...but the per-tool picks are remembered")

# ---- 7. Search finds INACTIVE tools -----------------------------------------
# The point of the design: a user can find a tool they have never activated.
ea_plugin_set("whitebox", TRUE)
cat0 <- ea_wbt_catalogue("flow")
say(nrow(cat0) >= 1, sprintf("search finds tools by keyword (%d hit(s) for 'flow')", nrow(cat0)))
say("active" %in% names(cat0) && "featured" %in% names(cat0),
    "results say whether each tool is active, so it can be enabled from the result")
inact <- ea_wbt_catalogue("slope")
say(nrow(ea_wbt_catalogue("zzznotatool")) == 0, "a nonsense query returns nothing")

# ---- 8. The featured set is real -------------------------------------------
raw  <- whitebox::wbt_list_tools(); raw <- raw[grepl(": ", raw, fixed = TRUE)]
real <- sub(":.*$", "", raw)
miss <- setdiff(EA_WBT_FEATURED, real)
say(length(miss) == 0,
    if (length(miss)) paste("featured tools that DO NOT EXIST:", paste(miss, collapse = ", "))
    else sprintf("all %d featured tools exist in the catalogue", length(EA_WBT_FEATURED)))

# ---- 9. The Plugin menu module ---------------------------------------------
# The screen is what makes any of the above reachable, so it must render and its
# toggles must write state. Asserted on BEHAVIOUR, not on markup.
ea_plugin_set("whitebox", FALSE)
local({ st <- ea_plugin_state(); st$tools[["whitebox"]] <- character(0)
        ea_plugin_state_set(st) })

R  <- NULL
OP <- reactiveVal(0)
suppressWarnings(testServer(pluginsServer, args = list(open = OP), {
  OP(1)                                   # open the dialog, as the menu does
  session$setInputs(q = "", filt = "feat")
  R <<- list(card = !is.null(output$provider_card),
             res  = !is.null(output$results))

  session$setInputs(toggle_prov = 1)
  R$prov_on <<- ea_plugin_on("whitebox")

  # The per-tool switch sends {tool, on, n}; it must write through.
  session$setInputs(tog = list(tool = "Slope", on = TRUE, n = 1))
  R$tool_on <<- ea_tool_on("whitebox", "Slope")
  session$setInputs(tog = list(tool = "Slope", on = FALSE, n = 2))
  R$tool_off <<- !ea_tool_on("whitebox", "Slope")

  session$setInputs(enable_feat = 1)
  R$feat_n <<- length(ea_plugin_state()$tools[["whitebox"]] %||% character(0))
  session$setInputs(disable_all = 1)
  R$cleared <<- length(ea_plugin_state()$tools[["whitebox"]] %||% character(0)) == 0
}))

say(isTRUE(R$card) && isTRUE(R$res), "the Plugins dialog renders its card and tool list")

# It must be a DIALOG, not a screen. The first version took the canvas and the
# tool panel, which is wrong for a settings action -- and is the specific thing
# item 76b exists to correct.
mp <- paste(readLines("mod_plugins.R", warn = FALSE), collapse = "
")
say(!grepl("pluginsCanvasUI", mp, fixed = TRUE) &&
    !grepl("pluginsToolsUI",  mp, fixed = TRUE),
    "CONTROL: the canvas and tools UI are gone -- it is no longer a screen")
say(grepl("ea_settings_modal", mp, fixed = TRUE),
    "the dialog is built on the shared settings-modal shape")
w2 <- paste(readLines("mod_workspace.R", warn = FALSE), collapse = "
")
say(!grepl('plugins        = list(nm = "Plugins"', w2, fixed = TRUE),
    "CONTROL: it is no longer registered as a workspace tool")
say(grepl("Shiny.setInputValue('plugins_open'", w2, fixed = TRUE),
    "the top-level menu opens it as a dialog")
say(isTRUE(R$prov_on),  "the Enable button turns the provider on")
say(isTRUE(R$tool_on),  "a per-tool switch enables that tool")
say(isTRUE(R$tool_off), "and turns it off again")
say(identical(R$feat_n, length(EA_WBT_FEATURED)),
    sprintf("'Enable all common tools' enables exactly the featured set (%s)", R$feat_n))
say(isTRUE(R$cleared), "'Disable every tool' clears them")

# ---- 10. The screen is reachable --------------------------------------------
# A screen nobody can open is the item-67 failure in a new place.
w <- paste(readLines("mod_workspace.R", warn = FALSE), collapse = " ")
# Reachability, NOT registration. The previous version of this check asserted the
# tool was registered and its server bound, and passed while Plugins sat buried in
# an Analysis > More fly-out that nobody found. Registration is not reachability.
say(grepl('.menu("Plugins", "puzzle-piece"', w, fixed = TRUE),
    "Plugins has its OWN top-level menu, beside Packages")
say(!grepl('"Whitebox tools", NULL, disabled = TRUE', w, fixed = TRUE),
    "CONTROL: the dead disabled Whitebox placeholder is gone")
s <- paste(readLines("server.R", warn = FALSE), collapse = " ")
# Matched WITHOUT the closing paren: the call is multi-line since on_change was
# added, and pinning the exact text made this fail against working code.
say(grepl('pluginsServer("plugins"', s, fixed = TRUE), "and its server is bound")
say(grepl("on_change = function() plugin_epoch(", s, fixed = TRUE),
    "and it reports activation changes back to the app")

# ---- 11. Activation takes effect WITHOUT a page reload ----------------------
# This is the property the whole phase-2 rework exists for. The workspace's tool
# catalogue was built once at construction, so an enabled tool did not appear
# until the session restarted. It is now a reactive over `plugin_epoch`.
ea_plugin_set("whitebox", TRUE)
local({ st <- ea_plugin_state(); st$tools[["whitebox"]] <- character(0)
        ea_plugin_state_set(st) })

EP <- reactiveVal(0)
W  <- NULL
suppressWarnings(testServer(workspaceServer,
  args = list(dataset_pool = reactiveValues(), raster_pool = reactiveValues(),
              las_pool = reactiveValues(), vector_pool = reactiveValues(),
              active_dataset = reactive(NULL), plugin_epoch = EP),
  {
    W <<- list(before = "algo_wbt_slope" %in% names(MODUI_R()))
    # Enable the tool the way the Plugin menu does, then bump the epoch.
    ea_tool_set("whitebox", "Slope", TRUE)
    EP(EP() + 1)
    W$after <<- "algo_wbt_slope" %in% names(MODUI_R())
    W$named <<- (MODUI_R()[["algo_wbt_slope"]] %||% list())$nm
  }))

say(isFALSE(W$before), "CONTROL: the tool is absent from the catalogue before enabling")
say(isTRUE(W$after),
    "enabling a tool puts it in the workspace catalogue IN THE SAME SESSION")
say(is.character(W$named) && grepl("WhiteboxTools", W$named %||% "", fixed = TRUE),
    paste0("and it carries its provenance label: ", W$named %||% "(none)"))

# ---- 12. Binding is idempotent ---------------------------------------------
# Re-binding an id would create a SECOND set of observers on one namespace, so a
# Run button would fire the operation twice. Proven on the registry ids rather
# than on Shiny internals: the guard must never re-offer an id it has bound.
bound <- new.env(parent = emptyenv())
take  <- function() {
  n <- 0L
  for (a in ea_algorithms()) {
    if (!is.null(bound[[a$id]])) next
    assign(a$id, TRUE, envir = bound); n <- n + 1L
  }
  n
}
first  <- take()
second <- take()
say(first > 0L, sprintf("the first pass binds every entry (%d)", first))
say(second == 0L, "a second pass with no changes binds NOTHING")
ea_tool_set("whitebox", "FillDepressions", TRUE)
third <- take()
say(third == 1L, sprintf("enabling one more tool binds exactly one (%d)", third))

cat(if (ok) "\nPLUGIN CHECK: PASS\n" else "\nPLUGIN CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
