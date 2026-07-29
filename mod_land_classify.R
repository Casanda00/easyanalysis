# ==========================================================================
# MODULE: Land Classification (Raster)
# Unsupervised k-means on a raster stack  +  supervised RF (optional)
# landClassifyCanvasUI / landClassifyToolsUI / landClassifyServer
# ==========================================================================

landClassifyToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Land Classification", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "lc_in",

      accordion_panel("Input Bands", value = "lc_in", icon = icon("layer-group"),
        uiOutput(ns("band_picker")),
        tags$p(class = "small text-muted",
          "Select one or more rasters as classification bands (e.g., spectral bands, indices).")
      ),

      accordion_panel("K-Means (unsupervised)", value = "lc_km", icon = icon("circle-nodes"),
        sliderInput(ns("k"), "Number of classes (k):", min = 2, max = 15, value = 5, step = 1),
        sliderInput(ns("iter_max"), "Max iterations:", min = 10, max = 500, value = 100, step = 10),
        numericInput(ns("nstart"), "Random starts:", value = 5, min = 1, max = 20, step = 1,
          width = "100%"),
        numericInput(ns("seed"), "Random seed:", value = 42, min = 1, step = 1, width = "100%"),
        textInput(ns("out_name"), "Output layer name", value = "classified", width = "100%"),
        actionButton(ns("run_km"), "Run K-Means",
          class = "btn-success w-100", icon = icon("play"))
      ),

      accordion_panel("Export", value = "lc_exp", icon = icon("download"),
        selectInput(ns("map_fmt"), "Format",
          choices = c("PNG" = "png", "JPEG" = "jpg", "PDF" = "pdf"), width = "100%"),
        numericInput(ns("map_dpi"), "DPI", value = 150, min = 72, max = 600, width = "100%"),
        radioButtons(ns("map_orient"), "Orientation",
          choices = c("Landscape" = "landscape", "Portrait" = "portrait"),
          selected = "landscape", inline = TRUE),
        div(style = "display:flex;gap:6px;margin-top:4px;",
          downloadButton(ns("dl_map"),    "Image",   class = "btn-sm btn-outline-success flex-fill"),
          downloadButton(ns("dl_raster"), "GeoTIFF", class = "btn-sm btn-success flex-fill")
        )
      )
    )
  )
}

landClassifyCanvasUI <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(col_widths = c(8, 4),
      card(
        card_header("Classification Map"),
        plotOutput(ns("preview"), height = "480px")
      ),
      tagList(
        card(card_header("Class Summary"),
          div(style = "padding:8px; font-size:13px;",
            verbatimTextOutput(ns("class_stats")))),
        card(card_header("Cluster Centres"),
          div(style = "overflow-y:auto; max-height:300px; padding:8px; font-size:12px;",
            verbatimTextOutput(ns("centres"))))
      )
    )
  )
}

landClassifyServer <- function(id, raster_pool) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    result_r <- reactiveVal(NULL)

    output$band_picker <- renderUI({
      pool <- reactiveValuesToList(raster_pool)
      nms  <- names(pool)
      if (length(nms) == 0)
        return(tags$p(class = "small text-warning",
          "Upload raster layers via Add Data."))
      selectInput(ns("band_layers"), "Rasters / bands to classify:",
        choices  = nms,
        selected = nms[1],
        multiple = TRUE,
        width    = "100%")
    })

    observeEvent(input$run_km, {
      pool   <- reactiveValuesToList(raster_pool)
      nms    <- input$band_layers
      req(length(nms) >= 1)

      result <- tryCatch({
        # Stack selected layers (use first band of each)
        stack <- terra::rast(lapply(nms, function(nm) {
          r <- pool[[nm]]
          r[[1]]
        }))

        # Extract pixel values as matrix
        vals  <- terra::values(stack, mat = TRUE, na.rm = FALSE)
        valid <- complete.cases(vals)
        if (sum(valid) < 10) stop("Too few valid pixels for classification.")

        k     <- as.integer(input$k       %||% 5)
        iter  <- as.integer(input$iter_max %||% 100)
        ns_   <- as.integer(input$nstart  %||% 5)
        seed_ <- as.integer(input$seed    %||% 42)

        set.seed(seed_)
        km <- kmeans(vals[valid, , drop = FALSE], centers = k,
                     iter.max = iter, nstart = ns_)

        # Build output raster
        classified <- terra::rast(stack[[1]])
        classified[] <- NA_real_
        classified[valid] <- km$cluster
        names(classified) <- "class"

        list(
          raster  = classified,
          kmeans  = km,
          k       = k,
          bands   = nms,
          n_valid = sum(valid)
        )
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 8)
        NULL
      })

      req(!is.null(result))
      out_nm <- trimws(input$out_name %||% "classified")
      if (!nzchar(out_nm)) out_nm <- "classified"
      names(result$raster) <- out_nm
      raster_pool[[out_nm]] <- result$raster
      result_r(c(result, list(name = out_nm)))
      showNotification(
        paste0("Classification '", out_nm, "' saved (k=", result$k, ", n=",
               format(result$n_valid, big.mark=","), " pixels)."),
        type = "message")
    })

    .class_pal <- function(k) {
      set.seed(1)
      grDevices::hcl.colors(k, palette = "Set2")
    }

    output$preview <- renderPlot({
      res <- result_r()
      if (is.null(res)) {
        show_placeholder("Configure and click Run K-Means.")
        return()
      }
      pal <- .class_pal(res$k)
      terra::plot(res$raster, col = pal, type = "classes",
                  main = res$name, mar = c(3.5, 3.5, 2, 7),
                  levels = paste("Class", seq_len(res$k)))
    })

    output$class_stats <- renderPrint({
      res <- result_r()
      if (is.null(res)) { cat("No result yet.\n"); return() }
      freq_tbl <- table(terra::values(res$raster))
      total    <- sum(freq_tbl, na.rm = TRUE)
      cat(sprintf("%-10s %8s %7s\n", "Class", "Pixels", "Share"))
      cat(strrep("-", 28), "\n")
      for (nm in names(freq_tbl))
        cat(sprintf("%-10s %8s %6.1f%%\n",
          paste("Class", nm), format(freq_tbl[[nm]], big.mark=","),
          100 * freq_tbl[[nm]] / total))
      cat(strrep("-", 28), "\n")
      cat(sprintf("%-10s %8s\n", "Total", format(total, big.mark=",")))
    })

    output$centres <- renderPrint({
      res <- result_r()
      if (is.null(res)) { cat("No result yet.\n"); return() }
      ct  <- res$kmeans$centers
      rownames(ct) <- paste("Class", seq_len(nrow(ct)))
      colnames(ct) <- res$bands
      print(round(ct, 4))
      cat(sprintf("\nWithin-cluster SS: %.4f\n", res$kmeans$tot.withinss))
      cat(sprintf("Between / Total SS: %.4f\n",
          res$kmeans$betweenss / res$kmeans$totss))
    })

    output$dl_raster <- downloadHandler(
      filename = function() paste0(result_r()$name %||% "classified", ".tif"),
      content  = function(file) {
        res <- result_r(); req(!is.null(res))
        terra::writeRaster(res$raster, file, overwrite = TRUE)
      }
    )

    output$dl_map <- downloadHandler(
      filename = function() {
        fmt <- input$map_fmt %||% "png"
        paste0(result_r()$name %||% "classified", ".", fmt)
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
        pal <- .class_pal(res$k)
        terra::plot(res$raster, col = pal, type = "classes",
                    main = res$name, mar = c(3.5, 3.5, 2, 7),
                    levels = paste("Class", seq_len(res$k)))
        dev.off()
      }
    )

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("Land Classification: no result yet.")
        paste0("Land Classification | K=", res$k, " classes | Bands: ",
               paste(res$bands, collapse=", "))
      }),
      plot = function() {
        res <- result_r()
        if (is.null(res)) return(invisible())
        pal <- .class_pal(res$k)
        terra::plot(res$raster, col = pal, type = "classes", main = ea_main(res$name),
                    levels = paste("Class", seq_len(res$k)))
      }
    )
  })
}
