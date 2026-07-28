# ==========================================================================
# project_store.R  --  on-disk projects: the app's saved state
# --------------------------------------------------------------------------
# A PROJECT IS A FOLDER. Everything a user loads and does lives in it, so
# closing the browser (or the whole app) and coming back resumes where they
# stopped. Deliberately plain R — no Shiny in here — so it can be tested
# standalone and reused by the browser build later.
#
# Layout:
#   <home>/projects/<id>/project.json   metadata + spatial file references
#   <home>/projects/<id>/datasets.rds   named list of tabular datasets
#
# <home> = $EASYANALYSIS_HOME, else %LOCALAPPDATA%/EasyAnalysis (Windows)
#          or ~/.easyanalysis elsewhere.
#
# NOTE ON SIZE: tabular data is serialised into the project. Rasters / point
# clouds / vectors are NOT copied — we store the path to the user's source
# file and reload from it. Copying multi-GB .laz into every project would be
# hostile. Trade-off: if the user moves the source file, that layer is marked
# missing on load rather than silently vanishing.
# ==========================================================================

ea_home <- function() {
  h <- Sys.getenv("EASYANALYSIS_HOME", "")
  if (nzchar(h)) return(h)
  if (.Platform$OS.type == "windows") {
    la <- Sys.getenv("LOCALAPPDATA", "")
    if (nzchar(la)) return(file.path(la, "EasyAnalysis"))
  }
  file.path(path.expand("~"), ".easyanalysis")
}

ea_projects_dir <- function() {
  d <- file.path(ea_home(), "projects")
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# A filesystem-safe id that still reads like the project name.
ea_slug <- function(name) {
  s <- tolower(trimws(name %||% ""))
  s <- gsub("[^a-z0-9]+", "-", s)
  s <- gsub("(^-+|-+$)", "", s)
  if (!nzchar(s)) s <- "project"
  substr(s, 1, 40)
}

# --- REGISTRY: projects can live in ANY folder the user picks (RStudio-style),
# so we can't just scan one directory. A small index at <home>/registry.json
# maps each project id -> its folder path. Everything else stays id-based.
.ea_registry_path <- function() file.path(ea_home(), "registry.json")

ea_registry_read <- function() {
  p <- .ea_registry_path()
  reg <- if (file.exists(p))
    tryCatch(jsonlite::read_json(p, simplifyVector = TRUE), error = function(e) NULL) else NULL
  # jsonlite may hand back a data.frame or empty list; normalise to id->path.
  out <- list()
  if (is.data.frame(reg) && all(c("id", "path") %in% names(reg))) {
    for (i in seq_len(nrow(reg))) out[[as.character(reg$id[i])]] <- as.character(reg$path[i])
  } else if (is.list(reg) && length(reg)) {
    for (nm in names(reg)) out[[nm]] <- as.character(reg[[nm]])
  }
  # Backward compat / self-heal: register any project folders sitting in the
  # default location that aren't in the registry yet (covers pre-registry
  # installs and hand-copied folders).
  def <- ea_projects_dir()
  for (d in list.dirs(def, full.names = TRUE, recursive = FALSE)) {
    if (file.exists(file.path(d, "project.json"))) {
      id <- basename(d)
      if (is.null(out[[id]])) out[[id]] <- d
    }
  }
  out
}

ea_registry_write <- function(reg) {
  # store as an array of {id, path} objects — stable and human-readable
  rows <- lapply(names(reg), function(id) list(id = id, path = unname(reg[[id]])))
  .ea_atomic(.ea_registry_path(), function(tmp)
    jsonlite::write_json(rows, tmp, auto_unbox = TRUE, pretty = TRUE))
  invisible(reg)
}

ea_registry_set <- function(id, path) {
  reg <- ea_registry_read(); reg[[id]] <- normalizePath(path, winslash = "/", mustWork = FALSE)
  ea_registry_write(reg); invisible(reg[[id]])
}

ea_registry_remove <- function(id) {
  reg <- ea_registry_read(); reg[[id]] <- NULL; ea_registry_write(reg)
}

# id -> folder path (registry first, default location as fallback).
ea_project_path <- function(id) {
  reg <- ea_registry_read()
  p <- reg[[id]]
  if (!is.null(p) && nzchar(p)) return(p)
  file.path(ea_projects_dir(), id)   # default-location fallback
}

# --- atomic write: temp file + rename, so a crash mid-write can't corrupt ---
.ea_atomic <- function(path, write_fn) {
  tmp <- paste0(path, ".tmp-", as.integer(runif(1, 1e6, 9e6)))
  on.exit({ if (file.exists(tmp)) unlink(tmp) }, add = TRUE)
  write_fn(tmp)
  # file.rename won't clobber on some Windows cases; remove target first.
  if (file.exists(path)) unlink(path)
  ok <- file.rename(tmp, path)
  if (!ok) stop("could not write ", path)
  invisible(path)
}

.ea_meta_path <- function(id) file.path(ea_project_path(id), "project.json")
.ea_data_path <- function(id) file.path(ea_project_path(id), "datasets.rds")

ea_project_meta <- function(id) {
  p <- .ea_meta_path(id)
  if (!file.exists(p)) return(NULL)
  tryCatch(
    jsonlite::read_json(p, simplifyVector = TRUE),
    error = function(e) NULL
  )
}

ea_project_write_meta <- function(id, meta) {
  meta$modified <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  .ea_atomic(.ea_meta_path(id), function(tmp)
    jsonlite::write_json(meta, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null"))
  invisible(meta)
}

# Create a new project. `parent` = the folder the project's own folder is
# created INSIDE (RStudio-style: pick a location, it makes the folder). Defaults
# to the app's projects dir. Returns the id (unique even if names repeat).
ea_project_create <- function(name = "Untitled project", parent = NULL) {
  parent <- parent %||% ea_projects_dir()
  if (!dir.exists(parent))
    dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  reg  <- ea_registry_read()
  base <- ea_slug(name); id <- base; n <- 2
  path <- file.path(parent, id)
  while (dir.exists(path) || !is.null(reg[[id]])) {
    id <- paste0(base, "-", n); n <- n + 1; path <- file.path(parent, id)
  }
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  ea_registry_set(id, path)
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  meta <- list(
    id = id, name = name, created = now, modified = now,
    app_version = if (exists("APP_VERSION")) APP_VERSION else NA_character_,
    last_view = "project", active_dataset = NULL,
    spatial = list()          # list of {name, kind, path}
  )
  ea_project_write_meta(id, meta)
  saveRDS(list(), .ea_data_path(id))
  id
}

ea_project_rename <- function(id, new_name) {
  meta <- ea_project_meta(id); if (is.null(meta)) return(invisible(FALSE))
  meta$name <- new_name
  ea_project_write_meta(id, meta)
  invisible(TRUE)
}

ea_project_duplicate <- function(id) {
  src <- ea_project_path(id); if (!dir.exists(src)) return(NULL)
  meta <- ea_project_meta(id); base <- ea_slug(paste0(meta$name %||% id, " copy"))
  reg <- ea_registry_read()
  new_id <- base; n <- 2
  parent <- dirname(src)                        # copy lives beside the original
  dest <- file.path(parent, new_id)
  while (dir.exists(dest) || !is.null(reg[[new_id]])) {
    new_id <- paste0(base, "-", n); n <- n + 1; dest <- file.path(parent, new_id)
  }
  ok <- tryCatch({
    dir.create(dest, recursive = TRUE, showWarnings = FALSE)
    file.copy(list.files(src, full.names = TRUE), dest, recursive = TRUE)
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(all(ok))) { unlink(dest, recursive = TRUE, force = TRUE); return(NULL) }
  ea_registry_set(new_id, dest)
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  m2 <- ea_project_meta(new_id) %||% list()
  m2$id <- new_id; m2$name <- paste0(meta$name %||% id, " copy")
  m2$created <- now
  ea_project_write_meta(new_id, m2)
  new_id
}

ea_project_delete <- function(id) {
  p <- ea_project_path(id)
  if (dir.exists(p)) unlink(p, recursive = TRUE, force = TRUE)
  ea_registry_remove(id)
  invisible(!dir.exists(p))
}

# All registered projects, newest-modified first. Prunes registry entries whose
# folder or metadata has gone (moved/deleted outside the app). Always a list.
ea_project_list <- function() {
  reg <- ea_registry_read()
  ids <- names(reg)
  out <- list(); alive <- character(0)
  for (i in ids) {
    m <- ea_project_meta(i)
    if (is.null(m)) next
    m$id <- m$id %||% i
    m$path <- reg[[i]]
    out[[length(out) + 1]] <- m
    alive <- c(alive, i)
  }
  # prune dead registry entries
  if (length(alive) < length(ids)) ea_registry_write(reg[alive])
  if (!length(out)) return(list())
  mod <- vapply(out, function(m) as.character(m$modified %||% ""), character(1))
  out[order(mod, decreasing = TRUE)]
}

# ---- spatial source files -------------------------------------------------
# Uploads only ever give us a TEMP path (Shiny deletes it), so a project that
# merely *references* an upload would break the moment the app restarts. We
# therefore copy spatial files into the project. That also makes a project
# folder self-contained, so it can be moved or shared later.
ea_project_files_dir <- function(id) {
  d <- file.path(ea_project_path(id), "files")
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# Copy `src` into the project, returning the stored path ("" if it failed).
# For shapefiles, pass every sibling part in `extra` so the copy stays readable.
ea_project_import_file <- function(id, src, name = basename(src), extra = character(0)) {
  if (!nzchar(src %||% "") || !file.exists(src)) return("")
  dest_dir <- ea_project_files_dir(id)
  dest <- file.path(dest_dir, name)
  if (!identical(normalizePath(src, mustWork = FALSE),
                 normalizePath(dest, mustWork = FALSE))) {
    okc <- tryCatch(file.copy(src, dest, overwrite = TRUE), error = function(e) FALSE)
    if (!isTRUE(okc)) return("")
  }
  for (f in extra) {
    if (file.exists(f))
      try(file.copy(f, file.path(dest_dir, basename(f)), overwrite = TRUE), silent = TRUE)
  }
  dest
}

# Delete a file this project copied into its own files/ folder.
#
# SAFETY: it deletes ONLY inside `ea_project_files_dir(id)`. A layer whose path
# points at the user's own file (the fallback when no project was open, or a
# path reference) is left completely alone — removing a layer must never delete
# the user's data.
ea_project_remove_file <- function(id, path) {
  if (!nzchar(path %||% "") || !nzchar(id %||% "")) return(invisible(FALSE))
  dir <- normalizePath(ea_project_files_dir(id), winslash = "/", mustWork = FALSE)
  p   <- normalizePath(path, winslash = "/", mustWork = FALSE)
  if (!startsWith(p, paste0(dir, "/"))) return(invisible(FALSE))   # outside: refuse
  if (!file.exists(p)) return(invisible(FALSE))
  ok <- tryCatch(unlink(p, force = TRUE) == 0, error = function(e) FALSE)
  # A shapefile is several files sharing one stem — take its sidecars too.
  if (identical(tolower(tools::file_ext(p)), "shp")) {
    stem <- tools::file_path_sans_ext(p)
    for (ext in c("shx", "dbf", "prj", "cpg", "qpj", "sbn", "sbx", "shp.xml"))
      try(unlink(paste0(stem, ".", ext), force = TRUE), silent = TRUE)
  }
  invisible(ok)
}

# Delete anything in files/ that no layer references any more. Catches orphans
# left by earlier versions (removing a layer used to leave its copy behind).
# `keep` = the paths still in use.
ea_project_prune_files <- function(id, keep = character(0)) {
  dir <- ea_project_files_dir(id)
  if (!dir.exists(dir)) return(invisible(0L))
  keep_n <- normalizePath(keep[nzchar(keep)], winslash = "/", mustWork = FALSE)
  # a kept .shp implies its sidecars are kept too
  for (k in keep_n[tolower(tools::file_ext(keep_n)) == "shp"]) {
    stem <- tools::file_path_sans_ext(k)
    keep_n <- c(keep_n, paste0(stem, ".", c("shx","dbf","prj","cpg","qpj","sbn","sbx")))
  }
  have <- list.files(dir, full.names = TRUE, recursive = FALSE)
  have_n <- normalizePath(have, winslash = "/", mustWork = FALSE)
  drop <- have[!(have_n %in% keep_n)]
  for (f in drop) try(unlink(f, force = TRUE, recursive = FALSE), silent = TRUE)
  invisible(length(drop))
}

# ---- data -----------------------------------------------------------------
# tables: named list of data.frames. spatial: list of {name, kind, path}.
ea_project_save_data <- function(id, tables = list(), spatial = list(),
                                 last_view = NULL, active_dataset = NULL) {
  if (!dir.exists(ea_project_path(id))) return(invisible(FALSE))
  .ea_atomic(.ea_data_path(id), function(tmp) saveRDS(tables, tmp))
  meta <- ea_project_meta(id) %||% list(id = id, name = id)
  meta$spatial        <- unname(spatial)
  if (!is.null(last_view))      meta$last_view      <- last_view
  meta$active_dataset <- active_dataset      # NULL clears it
  meta$n_datasets     <- length(tables)
  meta$n_spatial      <- length(spatial)
  ea_project_write_meta(id, meta)
  invisible(TRUE)
}

ea_project_load_data <- function(id) {
  p <- .ea_data_path(id)
  tables <- if (file.exists(p))
    tryCatch(readRDS(p), error = function(e) list()) else list()
  if (!is.list(tables)) tables <- list()
  meta <- ea_project_meta(id)
  spatial <- meta$spatial %||% list()
  # meta read back from JSON can come through as a data.frame; normalise to rows
  if (is.data.frame(spatial)) {
    spatial <- lapply(seq_len(nrow(spatial)), function(i) as.list(spatial[i, ]))
  }
  # Flag references whose source file has since moved/been deleted.
  spatial <- lapply(spatial, function(s) {
    s$missing <- !isTRUE(nzchar(s$path %||% "")) || !file.exists(s$path)
    s
  })
  list(tables = tables, spatial = spatial, meta = meta)
}

# Convenience for the status bar / project cards.
ea_project_summary <- function(meta) {
  n_d <- meta$n_datasets %||% 0; n_s <- meta$n_spatial %||% 0
  parts <- c(
    if (n_d) sprintf("%d dataset%s", n_d, if (n_d == 1) "" else "s"),
    if (n_s) sprintf("%d spatial layer%s", n_s, if (n_s == 1) "" else "s")
  )
  if (!length(parts)) "empty" else paste(parts, collapse = " · ")
}

# ---- portable single-file format: .eap ("EasyAnalysis Project") ------------
# .eap is simply the project FOLDER zipped. Working projects stay unzipped
# folders (fast, live autosave, spatial files usable); .eap is for share /
# backup / move-between-machines. Same idea as .qgz / .xlsx.
EA_PROJECT_EXT <- "eap"

# Zip a project folder into `dest` (an .eap path). Returns dest, or "" on failure.
ea_project_export <- function(id, dest) {
  src <- ea_project_path(id)
  if (!dir.exists(src)) return("")
  if (!grepl("\\.eap$", dest, ignore.case = TRUE)) dest <- paste0(dest, ".eap")
  ok <- tryCatch({
    # zip the folder CONTENTS with the id as the top-level dir, so import can
    # recover the project cleanly. `zip::zipr` is cross-platform (no system zip).
    if (file.exists(dest)) unlink(dest)
    zip::zipr(zipfile = dest, files = src, recurse = TRUE)
    file.exists(dest)
  }, error = function(e) FALSE)
  if (isTRUE(ok)) dest else ""
}

# Import an .eap into `parent` (defaults to the app projects dir) as a NEW
# project (fresh id so it never collides with an existing one). Returns the id.
ea_project_import <- function(eap_path, parent = NULL) {
  if (!file.exists(eap_path)) return(NULL)
  parent <- parent %||% ea_projects_dir()
  tmp <- file.path(tempdir(), paste0("ea-imp-", as.integer(runif(1, 1e5, 9e5))))
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
  ok <- tryCatch({ zip::unzip(eap_path, exdir = tmp); TRUE },
                 error = function(e)
                   tryCatch({ utils::unzip(eap_path, exdir = tmp); TRUE },
                            error = function(e2) FALSE))
  if (!isTRUE(ok)) return(NULL)
  # find the folder that actually holds project.json
  hit <- list.files(tmp, pattern = "^project\\.json$", recursive = TRUE,
                    full.names = TRUE)
  if (!length(hit)) return(NULL)
  src <- dirname(hit[[1]])
  meta <- tryCatch(jsonlite::read_json(hit[[1]], simplifyVector = TRUE),
                   error = function(e) list())
  base <- ea_slug(meta$name %||% "imported project")
  reg <- ea_registry_read(); new_id <- base; n <- 2
  dest <- file.path(parent, new_id)
  while (dir.exists(dest) || !is.null(reg[[new_id]])) {
    new_id <- paste0(base, "-", n); n <- n + 1; dest <- file.path(parent, new_id)
  }
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(src, full.names = TRUE), dest, recursive = TRUE)
  ea_registry_set(new_id, dest)
  m2 <- ea_project_meta(new_id) %||% list(); m2$id <- new_id
  ea_project_write_meta(new_id, m2)     # refresh id + modified
  new_id
}
