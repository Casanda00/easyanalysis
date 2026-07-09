# ==========================================================================
# MODULE: Suitability Modeling  (weighted overlay)
# suitabilityCanvasUI / suitabilityToolsUI / suitabilityServer
# ==========================================================================

suitabilityToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Suitability Modeling", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "suit_in",

      accordion_panel("Criterion Layers", value = "suit_in", icon = icon("layer-group"),
        uiOutput(ns("criterion_ui")),
        actionButton(ns("add_criterion"), "Add Criterion",
          class = "btn-outline-success btn-sm w-100 mt-1", icon = icon("plus"))
      ),

      accordion_panel("Reclassification", value = "suit_rec", icon = icon("sliders"),
        tags$p(class = "small text-muted",
          "Each layer is reclassified to a 1–5 suitability scale.",
          "Choose direction: High values = High suitability, or inverse."),
        uiOutput(ns("reclass_ui"))
      ),

      accordion_panel("Run & Export", value = "suit_run", icon = icon("play"),
        textInput(ns("out_name"), "Output layer name", value = "suitability", width = "100%"),
        actionButton(ns("run"), "Compute Suitability",
          class = "btn-success w-100", icon = icon("play")),
        hr(style = "margin:8px 0;"),
        selectInput(ns("map_fmt"), "Export format",
          choices = c("PNG" = "png", "JPEG" = "jpg", "PDF" = "pdf"), width = "100%"),
        numericInput(ns("map_dpi"), "DPI", value = 150, min = 72, max = 600, width = "100%"),
        radioButtons(ns("map_orient"), "Orientation",
          choices = c("Landscape" = "landscape", "Portrait" = "portrait"),
          selected = "landscape", inline = TRUE),
        div(style = "display:flex; gap:6px; margin-top:4px;",
          downloadButton(ns("dl_map"),    "Image",   class = "btn-sm btn-outline-success flex-fill"),
          downloadButton(ns("dl_raster"), "GeoTIFF", class = "btn-sm btn-success flex-fill")
        )
      )
    )
  )
}

suitabilityCanvasUI <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(col_widths = c(8, 4),
      card(
        card_header("Suitability Map  (1 = least · 5 = most suitable)"),
        plotOutput(ns("preview"), height = "480px")
      ),
      tagList(
        card(card_header("Layer Weights"),
          div(style = "padding:8px; font-size:13px;",
            verbatimTextOutput(ns("weight_log")))),
        card(card_header("Statistics"),
          div(style = "padding:8px; font-size:13px;",
            verbatimTextOutput(ns("stats"))))
      )
    )
  )
}

suitabilityServer <- function(id, raster_pool) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Reactive list of selected criterion layers (names only)
    criteria <- reactiveVal(character(0))
    result_r <- reactiveVal(NULL)

    observeEvent(input$add_criterion, {
      pool <- reactiveValuesToList(raster_pool)
      existing <- criteria()
      available <- setdiff(names(pool), existing)
      if (length(available) == 0) {
        showNotification("All loaded rasters already added.", type = "warning")
        return()
      }
      criteria(c(existing, available[1]))
    })

    output$criterion_ui <- renderUI({
      pool <- reactiveValuesToList(raster_pool)
      nms  <- names(pool)
      crit <- criteria()
      if (length(nms) == 0)
        return(tags$p(class = "small text-warning",
          "Upload raster layers first (Add Data)."))
      if (length(crit) == 0)
        return(tags$p(class = "small text-muted fst-italic",
          "Click 'Add Criterion' to start."))

      lapply(seq_along(crit), function(i) {
        div(
          style = "display:flex;align-items:center;gap:6px;margin-bottom:6px;",
          div(style = "flex:1;",
            selectInput(ns(paste0("crit_", i)), NULL,
              choices  = nms,
              selected = if (crit[i] %in% nms) crit[i] else nms[1],
              width    = "100%")
          ),
          div(style = "width:70px;",
            numericInput(ns(paste0("wt_", i)), "Wt",
              value = round(1 / length(crit), 2),
              min = 0, max = 1, step = 0.05, width = "100%")
          ),
          tags$button(
            class   = "btn btn-outline-danger btn-sm",
            style   = "padding:2px 7px; flex-shrink:0;",
            onclick = sprintf(
              "Shiny.setInputValue('%s', %d, {priority:'event'})",
              ns("remove_criterion"), i),
            "×"
          )
        )
      })
    })

    observeEvent(input$remove_criterion, {
      i <- as.integer(input$remove_criterion)
      cr <- criteria()
      if (i >= 1 && i <= length(cr)) criteria(cr[-i])
    })

    output$reclass_ui <- renderUI({
      crit <- criteria()
      if (length(crit) == 0)
        return(tags$p(class = "small text-muted", "Add criteria first."))
      lapply(seq_along(crit), function(i) {
        nm <- tryCatch(input[[paste0("crit_", i)]], error = function(e) crit[i]) %||% crit[i]
        div(style = "margin-bottom:6px;",
          tags$small(class = "fw-bold", nm),
          radioButtons(
            ns(paste0("dir_", i)), NULL,
            choices  = c("High = Suitable" = "pos", "Low = Suitable" = "neg"),
            selected = "pos", inline = TRUE
          )
        )
      })
    })

    observeEvent(input$run, {
      pool <- reactiveValuesToList(raster_pool)
      crit <- criteria()
      req(length(crit) >= 1)
      n <- length(crit)

      result <- tryCatch({
        layers  <- vector("list", n)
        weights <- numeric(n)

        for (i in seq_len(n)) {
          nm_i <- tryCatch(input[[paste0("crit_", i)]], error = function(e) crit[i]) %||% crit[i]
          wt_i <- as.numeric(tryCatch(input[[paste0("wt_", i)]], error = function(e) 1/n) %||% 1/n)
          dir_i <- tryCatch(input[[paste0("dir_", i)]], error = function(e) "pos") %||% "pos"
          req(nm_i %in% names(pool))
          r <- pool[[nm_i]][[1]]
          mn <- terra::global(r, "min", na.rm = TRUE)$min
          mx <- terra::global(r, "max", na.rm = TRUE)$max
          # Reclassify to 1–5
          rc <- 1 + 4 * (r - mn) / max(mx - mn, 1e-12)
          if (dir_i == "neg") rc <- 6 - rc   # invert: low raw = high suitability
          layers[[i]]  <- rc * wt_i
          weights[[i]] <- wt_i
        }

        total_wt <- sum(weights, na.rm = TRUE)
        suit <- Reduce("+", layers) / max(total_wt, 1e-12)
        names(suit) <- "suitability"
        list(raster = suit, weights = weights,
             names  = sapply(seq_len(n), function(i)
               tryCatch(input[[paste0("crit_", i)]], error=function(e) crit[i]) %||% crit[i]))
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 8)
        NULL
      })

      req(!is.null(result))
      out_nm <- trimws(input$out_name %||% "suitability")
      if (!nzchar(out_nm)) out_nm <- "suitability"
      raster_pool[[out_nm]] <- result$raster
      result_r(c(result, list(name = out_nm)))
      showNotification(paste0("'", out_nm, "' saved to layer pool."), type = "message")
    })

    # ---- Color palette: RdYlGn 1-5 -----------------------------------------
    .suit_pal <- colorRampPalette(c("#d73027","#fc8d59","#ffffbf","#91cf60","#1a9850"))(100)

    output$preview <- renderPlot({
      res <- result_r()
      if (is.null(res)) {
        show_placeholder("Add criteria and click Compute Suitability.")
        return()
      }
      terra::plot(res$raster, col = .suit_pal, main = res$name,
                  range = c(1, 5), mar = c(3.5, 3.5, 2, 7))
    })

    output$weight_log <- renderPrint({
      res <- result_r()
      if (is.null(res)) { cat("No result yet.\n"); return() }
      total <- sum(res$weights)
      for (i in seq_along(res$weights))
        cat(sprintf("%-22s wt = %.3f  (%.1f%%)\n",
          res$names[i], res$weights[i], 100 * res$weights[i] / total))
    })

    output$stats <- renderPrint({
      res <- result_r()
      if (is.null(res)) { cat("No result yet.\n"); return() }
      st <- tryCatch(
        terra::global(res$raster, fun = c("min","mean","max","sd"), na.rm = TRUE),
        error = function(e) NULL)
      if (is.null(st)) return()
      cat(sprintf("Min  : %.3f\nMean : %.3f\nMax  : %.3f\nSD   : %.3f\n",
                  st$min, st$mean, st$max, st$sd))
    })

    output$dl_raster <- downloadHandler(
      filename = function() paste0(result_r()$name %||% "suitability", ".tif"),
      content  = function(file) {
        res <- result_r(); req(!is.null(res))
        terra::writeRaster(res$raster, file, overwrite = TRUE)
      }
    )

    output$dl_map <- downloadHandler(
      filename = function() {
        fmt <- input$map_fmt %||% "png"
        paste0(result_r()$name %||% "suitability", ".", fmt)
      },
      content = function(file) {
        res <- result_r(); req(!is.null(res))
        fmt  <- input$map_fmt    %||% "png"
        dpi  <- max(72L, min(600L, as.integer(input$map_dpi   %||% 150L)))
        ornt <- input$map_orient %||% "landscape"
        if (ornt == "landscape") { pw <- 11.69; ph <- 8.27 }
        else                     { pw <-  8.27; ph <- 11.69 }
        if (fmt == "pdf")      pdf(file, width = pw, height = ph)
        else if (fmt == "jpg") jpeg(file, width=pw*dpi, height=ph*dpi, res=dpi, quality=95)
        else                   png(file, width=pw*dpi, height=ph*dpi, res=dpi)
        terra::plot(res$raster, col = .suit_pal, main = res$name,
                    range = c(1, 5), mar = c(3.5, 3.5, 2, 7))
        dev.off()
      }
    )

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("Suitability Modeling: no result yet.")
        paste0("Suitability Modeling | Output: ", res$name, "\n",
               "Criteria: ", paste(res$names, collapse = ", "))
      }),
      plot = function() {
        res <- result_r()
        if (is.null(res)) return(invisible())
        terra::plot(res$raster, col = .suit_pal, main = res$name, range = c(1, 5))
      }
    )
  })
}
