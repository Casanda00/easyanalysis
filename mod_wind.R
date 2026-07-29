# mod_wind.R — Wind & Environmental Analysis
# Processes ERA5 wind data (u/v or long-format var/val CSV); draws a wind rose;
# computes speed/direction statistics; supports spatial control-point sampling.
#
# Input formats accepted:
#   (a) Long ERA5: columns [time, var, val] where var contains "wind" substrings
#   (b) Wide with u/v: columns named "u" + "v" (eastward / northward m/s)
#   (c) Pre-processed: columns "ws" (speed) + "wd" (direction 0-360°)
#   (d) Any dataset in dataset_pool — column mapping done interactively.

.WIND_VIEWS <- c(wind_rose = "Wind Rose", speed_distribu = "Speed Distribution", statistics = "Statistics")
.WIND_VIEWS_PLOT <- c("wind_rose", "speed_distribu")  # views whose body actually renders a plot


windCanvasUI <- function(id) {
  ns <- NS(id)
  # Select-and-split (helpers.R): one selection fills the area, several split it.
  card(
    card_header(ea_view_header(ns, .WIND_VIEWS)),
    div(class = "lm-viewport", uiOutput(ns("view_body")))
  )
}

windToolsUI <- function(id) {
  ns <- NS(id)
  accordion(
    open = "Data",
    accordion_panel("Data",
      p(class="text-muted small", "Select your wind dataset in the left rail, then configure columns below."),
      uiOutput(ns("col_map_ui")),
      actionButton(ns("process_btn"), tagList(icon("gears"), " Process Wind Data"),
                   class="btn-success w-100 mt-1")
    ),
    accordion_panel("Wind Rose Options",
      numericInput(ns("n_dir"), "Direction sectors", value=16, min=8, max=36, step=4),
      textInput(ns("spd_breaks"), "Speed class boundaries (m/s, comma-separated)",
                value="0,2,4,6,8"),
      selectInput(ns("rose_palette"), "Colour palette",
                  choices=c("Plasma"="plasma","Viridis"="viridis","Inferno"="inferno"),
                  selected="plasma"),
      actionButton(ns("plot_btn"), tagList(icon("chart-pie"), " Draw Wind Rose"),
                   class="btn-outline-primary w-100")
    ),
    accordion_panel("Export",
      downloadButton(ns("dl_stats"), tagList(icon("table"),    " Statistics (CSV)"),
                     class="btn-sm btn-outline-secondary w-100 mt-1"),
      downloadButton(ns("dl_proc"),  tagList(icon("download"), " Processed data (CSV)"),
                     class="btn-sm btn-outline-secondary w-100 mt-1")
    )
  )
}

windServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    output$view_tools <- renderUI({
      picked <- input$view_pick
      if (!length(picked)) picked <- names(.WIND_VIEWS)[1]
      if (any(picked %in% .WIND_VIEWS_PLOT)) ea_plot_appearance()
    })
    output$view_body <- renderUI({
      ns <- session$ns
      ea_view_panes(input$view_pick, .WIND_VIEWS, function(k, solo) switch(k,
        wind_rose = tagList(plotOutput(ns("windrose_plot"), height=if (solo) "80vh" else "100%")),
        speed_distribu = tagList(plotOutput(ns("speed_hist"),   height=if (solo) "60vh" else "100%")),
        statistics = tagList(div(class="p-3", uiOutput(ns("stats_ui")))),
        NULL))
    })

    ns <- session$ns

    rv <- reactiveValues(
      wind_df  = NULL,
      rose_obj = NULL
    )

    .raw_df <- reactive({ active_dataset() })

    # ---- Column mapping UI --------------------------------------------------
    output$col_map_ui <- renderUI({
      df <- .raw_df()
      if (is.null(df)) return(NULL)
      cn <- names(df)

      # Detect format
      has_ws_wd  <- all(c("ws","wd") %in% cn)
      has_uv     <- all(c("u","v")   %in% cn)
      has_var_val <- all(c("var","val") %in% cn)

      if (has_ws_wd) {
        return(div(class="alert alert-success p-2 mb-0",
          tags$small(icon("check"), " Pre-processed columns 'ws' and 'wd' detected — click Process.")))
      } else if (has_uv) {
        return(div(class="alert alert-success p-2 mb-0",
          tags$small(icon("check"), " Columns 'u' and 'v' detected — will compute ws/wd. Click Process.")))
      } else if (has_var_val) {
        return(div(class="alert alert-info p-2 mb-0",
          tags$small(icon("info"), " ERA5 long format detected (var/val). Click Process.")))
      } else {
        tagList(
          selectInput(ns("ws_col"), "Wind speed column (ws)", choices=c("(none)"="", cn)),
          selectInput(ns("wd_col"), "Wind direction column (wd, 0–360°)", choices=c("(none)"="", cn))
        )
      }
    })

    # ---- Process ------------------------------------------------------------
    observeEvent(input$process_btn, {
      df <- .raw_df()
      req(!is.null(df))
      cn <- names(df)

      out <- tryCatch({
        if (all(c("ws","wd") %in% cn)) {
          df[, c("ws","wd")]
        } else if (all(c("u","v") %in% cn)) {
          data.frame(
            ws = sqrt(df$u^2 + df$v^2),
            wd = {
              ang <- atan2(df$v, df$u) * 180 / pi
              ifelse(ang >= 0, ang, 360 + ang)
            }
          )
        } else if (all(c("var","val") %in% cn)) {
          # ERA5 long format: filter rows containing "wind", reshape wide
          wind_rows <- df[grepl("wind", df$var, ignore.case=TRUE), ]
          if (nrow(wind_rows) == 0) stop("No 'wind' rows found in 'var' column.")
          if (!"time" %in% cn) stop("Long-format ERA5 needs a 'time' column.")
          wide <- reshape(wind_rows[, c("time","var","val")],
                          idvar="time", timevar="var", direction="wide")
          nms_w <- names(wide)
          # Find u and v columns (east/north wind)
          u_col <- grep("u.*wind|wind.*u|eastward", nms_w, ignore.case=TRUE, value=TRUE)[1]
          v_col <- grep("v.*wind|wind.*v|northward", nms_w, ignore.case=TRUE, value=TRUE)[1]
          if (is.na(u_col) || is.na(v_col)) stop("Cannot identify u/v wind columns after reshaping.")
          data.frame(
            ws = sqrt(wide[[u_col]]^2 + wide[[v_col]]^2),
            wd = { ang <- atan2(wide[[v_col]], wide[[u_col]]) * 180/pi; ifelse(ang>=0,ang,360+ang) }
          )
        } else {
          ws_c <- input$ws_col %||% ""
          wd_c <- input$wd_col %||% ""
          if (!nzchar(ws_c) || !nzchar(wd_c))
            stop("Select wind speed and direction columns.")
          data.frame(ws=as.numeric(df[[ws_c]]), wd=as.numeric(df[[wd_c]]))
        }
      }, error=function(e) { showNotification(e$message, type="error"); NULL })

      if (is.null(out)) return()
      out <- out[!is.na(out$ws) & !is.na(out$wd), ]
      if (nrow(out) == 0) { showNotification("No valid ws/wd rows after processing.", type="error"); return() }
      rv$wind_df <- out
      showNotification(paste0(nrow(out), " valid wind observations processed."), type="message", duration=3)
    })

    # ---- Wind rose plot (ggplot2) -------------------------------------------
    .gg_rose <- function(df, n_dir, spd_breaks, palette_nm, title="Wind Rose") {
      if (is.null(df) || nrow(df)==0) return(NULL)
      sector_w <- 360/n_dir
      df$dir_sector <- floor(df$wd/sector_w) %% n_dir
      df$dir_angle  <- df$dir_sector * sector_w

      brks <- tryCatch(as.numeric(trimws(strsplit(spd_breaks,",")[[1]])),
                       error=function(e) c(0,2,4,6,8))
      brks <- sort(unique(c(brks, Inf)))
      lbl_ends <- head(brks,-1)
      lbl_start <- head(brks,-1); lbl_end <- tail(brks,-1)
      spd_lbls <- ifelse(is.infinite(lbl_end),
                         paste0(">", lbl_start),
                         paste0(lbl_start,"–",lbl_end))
      df$spd_bin <- factor(
        cut(df$ws, breaks=brks, labels=spd_lbls, include.lowest=TRUE, right=FALSE),
        levels=spd_lbls, ordered=TRUE)

      df$count <- 1
      tbl <- aggregate(count ~ dir_angle + spd_bin, data=df, FUN=sum)
      tbl$pct <- tbl$count / nrow(df) * 100

      ggplot2::ggplot(tbl, ggplot2::aes(x=dir_angle, y=pct, fill=spd_bin)) +
        ggplot2::geom_bar(stat="identity", width=sector_w*0.9,
                          position="stack", color="white", linewidth=0.2) +
        ggplot2::scale_x_continuous(limits=c(0,360), breaks=c(0,90,180,270),
                                    labels=c("N","E","S","W")) +
        ggplot2::coord_polar(start=-pi/2, direction=1) +
        ggplot2::scale_fill_viridis_d(name="Speed (m/s)", option=palette_nm, direction=-1) +
        ggplot2::labs(title=title, x=NULL, y="Frequency (%)") +
        ggplot2::theme_minimal(base_size=13) +
        ggplot2::theme(axis.text.x=ggplot2::element_text(face="bold",size=12))
    }

    # Re-draw when button pressed
    rose_plot <- eventReactive(input$plot_btn, {
      req(!is.null(rv$wind_df))
      .gg_rose(rv$wind_df,
               as.integer(input$n_dir %||% 16),
               input$spd_breaks %||% "0,2,4,6,8",
               input$rose_palette %||% "plasma")
    }, ignoreNULL=FALSE)

    output$windrose_plot <- renderPlot({
      p <- rose_plot()
      if (!is.null(p)) print(p)
      else plot.new(); text(0.5,0.5,"Process wind data first, then click Draw Wind Rose.",
                            cex=1.2, col="grey50")
    })

    # ---- Speed histogram ----------------------------------------------------
    output$speed_hist <- renderPlot({
      df <- rv$wind_df
      if (is.null(df)) {
        plot.new(); text(0.5,0.5,"No wind data processed yet.", cex=1.2, col="grey50"); return()
      }
      ggplot2::ggplot(df, ggplot2::aes(x=ws)) +
        ggplot2::geom_histogram(bins=40, fill="#1e88e5", color="white", linewidth=0.2) +
        ggplot2::labs(title="Wind Speed Distribution", x="Wind speed (m/s)", y="Count") +
        ggplot2::theme_minimal(base_size=13)
    })

    # ---- Statistics ---------------------------------------------------------
    .wind_stats <- reactive({
      df <- rv$wind_df
      if (is.null(df)) return(NULL)
      n_calm <- sum(df$ws < 0.5, na.rm=TRUE)
      # Prevailing direction (16-sector)
      df$dir16 <- floor(df$wd/22.5) %% 16
      dir_tbl   <- table(df$dir16)
      dir_lbls  <- c("N","NNE","NE","ENE","E","ESE","SE","SSE",
                     "S","SSW","SW","WSW","W","WNW","NW","NNW")
      prev_dir  <- dir_lbls[as.integer(names(which.max(dir_tbl))) + 1L]
      list(
        n          = nrow(df),
        n_calm     = n_calm,
        calm_pct   = round(100*n_calm/nrow(df),2),
        mean_ws    = round(mean(df$ws, na.rm=TRUE),3),
        median_ws  = round(median(df$ws, na.rm=TRUE),3),
        max_ws     = round(max(df$ws, na.rm=TRUE),3),
        p95_ws     = round(quantile(df$ws,.95,na.rm=TRUE),3),
        prevailing = prev_dir
      )
    })

    output$stats_ui <- renderUI({
      s <- .wind_stats()
      if (is.null(s)) return(p(class="text-muted", "No data processed yet."))
      div(class="row row-cols-2 g-3",
        lapply(seq_along(s), function(i) {
          div(class="col",
            div(class="card card-body p-2 text-center",
              div(class="small text-muted", names(s)[i]),
              div(class="fw-bold", as.character(s[[i]]))
            )
          )
        })
      )
    })

    # ---- Downloads ----------------------------------------------------------
    

    output$dl_stats <- downloadHandler(
      filename = function() paste0("wind_stats_", Sys.Date(), ".csv"),
      content  = function(f) {
        s <- .wind_stats()
        if (is.null(s)) { write.csv(data.frame(), f, row.names=FALSE); return() }
        write.csv(as.data.frame(s), f, row.names=FALSE)
      }
    )

    output$dl_proc <- downloadHandler(
      filename = function() paste0("wind_processed_", Sys.Date(), ".csv"),
      content  = function(f) {
        req(!is.null(rv$wind_df))
        write.csv(rv$wind_df, f, row.names=FALSE)
      }
    )

    list(
      context = reactive({
        df <- rv$wind_df
        if (is.null(df)) return(list())
        list(n_obs=nrow(df), mean_ws=round(mean(df$ws,na.rm=TRUE),3))
      }),
      plot = function() {
        p <- tryCatch(rose_plot(), error=function(e) NULL)
        if (!is.null(p)) { print(p); recordPlot() } else NULL
      }
    )
  })
}
