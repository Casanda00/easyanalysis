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

R <- NULL
suppressWarnings(testServer(pluginsServer, args = list(), {
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

say(isTRUE(R$card) && isTRUE(R$res), "the Plugins screen renders its card and tool list")
say(isTRUE(R$prov_on),  "the Enable button turns the provider on")
say(isTRUE(R$tool_on),  "a per-tool switch enables that tool")
say(isTRUE(R$tool_off), "and turns it off again")
say(identical(R$feat_n, length(EA_WBT_FEATURED)),
    sprintf("'Enable all common tools' enables exactly the featured set (%s)", R$feat_n))
say(isTRUE(R$cleared), "'Disable every tool' clears them")

# ---- 10. The screen is reachable --------------------------------------------
# A screen nobody can open is the item-67 failure in a new place.
w <- paste(readLines("mod_workspace.R", warn = FALSE), collapse = " ")
say(grepl('plugins        = list(nm = "Plugins"', w, fixed = TRUE),
    "the Plugins tool is registered in the workspace catalogue")
s <- paste(readLines("server.R", warn = FALSE), collapse = " ")
say(grepl('pluginsServer("plugins")', s, fixed = TRUE), "and its server is bound")

cat(if (ok) "\nPLUGIN CHECK: PASS\n" else "\nPLUGIN CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
