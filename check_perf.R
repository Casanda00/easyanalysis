# check_perf.R -- a repeatable performance matrix with declared budgets
#
# WHY THIS EXISTS
# ---------------
# Every performance number this project has ever quoted came from a throwaway
# script in a temp directory. So "is it faster?" had no answer that survived the
# session, and a regression could sit unnoticed for months. Worse: a change could
# be *claimed* to help without anyone able to check.
#
# This is the answer to that. It generates its own fixtures (nothing is committed),
# measures each phase separately, and compares against a stated budget. A budget
# is not a benchmark score -- it is a line that says "past here, something broke".
#
# THE POINT OF SEPARATING PHASES: the app's slowness was assumed to be reading or
# drawing. Measured, it is neither -- opening a 100 M-cell raster is lazy and the
# display path is already optimised. Phases keep that honest: a fix has to move a
# specific number, not "feel faster".
#
# Budgets are deliberately LOOSE (roughly 3-5x the measured time on the dev
# machine). A tight budget on a shared or slower machine fails for reasons nobody
# will act on, and a check that cries wolf gets ignored -- which is worse than
# not having it.
#
# Run:            Rscript check_perf.R          (small fixtures, ~1 min)
# Run big:        EASYANALYSIS_PERF=large Rscript check_perf.R
#   `large` uses fixtures near the sizes actually complained about. It is slow by
#   design and is not part of the default suite.

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
suppressMessages(source("global.R"))

BIG <- identical(tolower(Sys.getenv("EASYANALYSIS_PERF", "")), "large")
ok  <- TRUE
res <- list()

# `budget` is seconds. NA = measure and report, do not judge (used where the
# cost is dominated by fixture creation rather than by the app).
phase <- function(group, what, budget, expr) {
  t0 <- Sys.time(); v <- force(expr)
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  verdict <- if (is.na(budget)) "  --  " else if (el <= budget) "  OK  " else " SLOW "
  if (!is.na(budget) && el > budget) ok <<- FALSE
  res[[length(res) + 1]] <<- data.frame(group = group, phase = what,
                                        secs = round(el, 2),
                                        budget = budget, verdict = verdict,
                                        stringsAsFactors = FALSE)
  invisible(v)
}

tmp <- file.path(tempdir(), paste0("perf_", as.integer(runif(1, 1e5, 9e5))))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

cat(sprintf("EasyAnalysis performance matrix  (%s fixtures)\n\n",
            if (BIG) "LARGE" else "small"))

# ============================================================================
# CSV -- the one ingest path that genuinely reads everything, on the main thread
# ============================================================================
n_csv <- if (BIG) 2e6 else 3e5
csv <- file.path(tmp, "t.csv")
d <- data.frame(id = seq_len(n_csv), a = runif(n_csv), b = runif(n_csv),
                g = sample(letters[1:8], n_csv, TRUE))
phase("csv", "write fixture", NA, utils::write.csv(d, csv, row.names = FALSE))
mb_csv <- file.info(csv)$size / 1024^2
rm(d); invisible(gc())

# read.csv is the CURRENT behaviour; fread is the candidate. Measuring both in
# one place is what makes "fread would help" a number rather than a belief.
df <- phase("csv", sprintf("read.csv  [%0.f MB]", mb_csv),
            if (BIG) 60 else 12, utils::read.csv(csv))
# The app's actual reader. Budgeted TIGHTLY relative to read.csv above: if this
# ever creeps back toward it, the fast path has silently stopped being taken --
# a fallback that quietly becomes the norm is exactly how a 60x win disappears.
phase("csv", "ea_read_table  [what the app uses]", if (BIG) 6 else 2,
      ea_read_table(csv, ","))
phase("csv", "init_data  [the app's own cleaning]", 2, init_data(df))
rm(df); invisible(gc())

# EQUIVALENCE, not just speed. fread keeps column names verbatim while read.csv
# mangles them, so "my col" would stay "my col" and "TRUE" would stay "TRUE" --
# and every formula in the app is built by pasting names together, so either
# would produce a formula that cannot parse. check.names = TRUE restores parity;
# this fails the day somebody removes it thinking it is noise.
awk <- file.path(tmp, "awkward.csv")
writeLines(c("my col,2nd-col,ok_name,with space,TRUE,NA col",
             "1,2.5,alpha,x,1,", "2,3.5,beta,y,0,7"), awk)
.a <- utils::read.csv(awk); .b <- ea_read_table(awk, ",")
if (!identical(names(.a), names(.b))) {
  ok <- FALSE
  cat("  FAIL  ea_read_table names differ from read.csv:
        ",
      paste(names(.a), collapse = " | "), "
        ",
      paste(names(.b), collapse = " | "), "
")
} else if (!identical(class(.b), "data.frame")) {
  ok <- FALSE
  cat("  FAIL  ea_read_table returned a", class(.b)[1],
      "- data.table `[` has different semantics from data.frame
")
} else {
  cat("  OK    ea_read_table matches read.csv on names, types and class
")
}

# ============================================================================
# Raster -- open must stay LAZY, display must stay downsample-first
# ============================================================================
n_r <- if (BIG) 10000L else 4000L
tif <- file.path(tmp, "t.tif")
r <- terra::rast(nrows = n_r, ncols = n_r, xmin = 0, xmax = n_r,
                 ymin = 0, ymax = n_r, crs = "EPSG:32635")
terra::values(r) <- rep_len(as.numeric(seq_len(n_r)), terra::ncell(r))
phase("raster", "write fixture", NA,
      terra::writeRaster(r, tif, overwrite = TRUE,
                         gdal = c("COMPRESS=NONE", "BIGTIFF=YES")))
mb_tif <- file.info(tif)$size / 1024^2
rm(r); invisible(gc())

# THE assertion for rasters: opening must not depend on size. If this ever goes
# above a second, something started reading values at ingest.
rr <- phase("raster", sprintf("terra::rast  [%0.f MB, must stay lazy]", mb_tif),
            1.0, terra::rast(tif))
phase("raster", "metadata (ncell/ext/crs)", 0.5,
      { terra::ncell(rr); terra::ext(rr); terra::crs(rr) })

shrink <- function(x) if (terra::ncell(x) > 4e5)
  terra::aggregate(x, fact = ceiling(sqrt(terra::ncell(x) / 4e5)),
                   fun = "mean", na.rm = TRUE) else x
sm <- phase("display", "aggregate to <=400k cells", if (BIG) 8 else 3, shrink(rr))
phase("display", "project to WGS84 (after shrink)", if (BIG) 6 else 3, .to_wgs84(sm))

# CONTROL: the order that was fixed. Kept because a refactor could silently
# restore it, and the whole display budget depends on it not coming back.
if (BIG)
  phase("display", "CONTROL project-first at full res (must be SLOW)", NA,
        tryCatch(terra::project(rr, "EPSG:4326"), error = function(e) NULL))

# ============================================================================
# Vector -- st_read materialises, unlike terra
# ============================================================================
n_v <- if (BIG) 2e5 else 2e4
gp <- file.path(tmp, "t.gpkg")
pts <- sf::st_as_sf(data.frame(id = seq_len(n_v), x = runif(n_v, 0, 10),
                               y = runif(n_v, 0, 10)),
                    coords = c("x", "y"), crs = 4326)
phase("vector", "write fixture", NA,
      suppressMessages(sf::st_write(pts, gp, layer = "pts", quiet = TRUE,
                                    delete_dsn = TRUE)))
mb_gp <- file.info(gp)$size / 1024^2
rm(pts); invisible(gc())
phase("vector", sprintf("ea_read_vector  [%0.f MB, %d features]", mb_gp, n_v),
      if (BIG) 20 else 6, ea_read_vector(gp, basename(gp)))

# ============================================================================
# Transport -- the floor the browser upload can never beat
# ============================================================================
cp <- file.path(tmp, "copy.bin")
phase("transport", sprintf("plain disk copy of the raster  [%0.f MB]", mb_tif),
      NA, file.copy(tif, cp, overwrite = TRUE))
el_cp <- res[[length(res)]]$secs
unlink(cp)

# ============================================================================
out <- do.call(rbind, res)
cat(sprintf("  %-10s %-46s %8s %8s  %s\n", "GROUP", "PHASE", "SECS", "BUDGET", ""))
for (i in seq_len(nrow(out)))
  cat(sprintf("  %-10s %-46s %8.2f %8s  %s\n", out$group[i], out$phase[i],
              out$secs[i],
              if (is.na(out$budget[i])) "-" else format(out$budget[i]),
              out$verdict[i]))

if (el_cp > 0)
  cat(sprintf("\n  disk throughput: %.0f MB/s  ->  a 4 GB transfer costs >= %.0f s\n",
              mb_tif / el_cp, 4 * 1024 / (mb_tif / el_cp)))
cat("  (the browser upload path is slower still: HTTP multipart + chunked writes.\n")
cat("   That is the cost item 82's path-based ingest removes rather than hides.)\n")

cat(if (ok) "\nPERF CHECK: PASS\n" else "\nPERF CHECK: OVER BUDGET\n")
quit(status = if (ok) 0L else 1L)
