# ==========================================================================
# MODULE: AI Co-Pilot chat  (floating panel, app-level)
# chatUI(id) / chatServer(id, dataset_pool, active_dataset, current_view, module_ctx)
# --------------------------------------------------------------------------
# Context fed to the model =
#   active dataset (name + dims + structure)
# + the CURRENT screen's live analysis text  (module_ctx[[view]]$context())
# + an IMAGE of the current screen's plot     (module_ctx[[view]]$plot()).
# The model is instructed to use ONLY that context + image and never speculate.
# Open/close is pure client-side (toggle .open) so the X reliably closes it.
# Uses OpenAI via OPENAI_API_KEY. httr/jsonlite/base64enc are optional (qualified).
# ==========================================================================

.CHAT_MODEL <- "gpt-5.4-nano"  # change to any vision-capable model your key can use

.VIEW_LABELS <- c(
  data = "Data & Exploration", lm = "Linear Regression", lme = "Linear Mixed Effects",
  anova = "ANOVA", logistic = "Logistic Regression", rf = "Random Forest",
  da = "Discriminant Analysis", clustering = "Clustering",
  classification = "Classification (one-vs-all)", pointcloud = "LiDAR Point Cloud / 3D",
  chm_itd = "CHM & Individual Tree Detection", metrics = "LiDAR Metrics & Evaluation")

.view_label <- function(v) {
  if (!isTruthy(v) || is.na(.VIEW_LABELS[v])) return("the app")
  unname(.VIEW_LABELS[v])
}

.ask_openai <- function(context, history, user_msg, image_b64 = NULL) {
  key <- Sys.getenv("OPENAI_API_KEY")
  if (!nzchar(key)) return("⚠️ AI is not configured. Set OPENAI_API_KEY in your .Renviron and restart R.")
  if (!requireNamespace("httr", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE))
    return("⚠️ Packages 'httr' and 'jsonlite' are required for the AI Co-Pilot.")
  sys_prompt <- paste(
    "You are a careful data-analysis assistant embedded in a forestry / forest-inventory",
    "statistics app. STRICT RULES — follow them exactly:",
    "1) Use ONLY the information in the CONTEXT block and the attached plot image. Do not use",
    "outside knowledge about the user's specific data.",
    "2) If an image is attached, describe and interpret only what is actually visible in it",
    "(axes, points, spread, outliers, separation, residual pattern, bar heights, etc.).",
    "3) If NO image is attached, state that you cannot see the plot and ask the user to open the",
    "relevant view — do NOT guess what the plot shows.",
    "4) Never invent variable names, predictors, coefficients, p-values, cluster counts or trends",
    "that are not explicitly in the CONTEXT or visible in the image.",
    "5) If something cannot be determined from what is provided, say so plainly.",
    "Be concise and practical; prefer short bullets.")
  msgs <- list(list(role = "system", content = sys_prompt),
               list(role = "system", content = paste0("CONTEXT:\n", context)))
  for (m in utils::tail(history, 6)) msgs[[length(msgs) + 1]] <- list(role = m$role, content = m$content)
  user_content <- if (!is.null(image_b64)) {
    list(list(type = "text", text = user_msg),
         list(type = "image_url", image_url = list(url = paste0("data:image/png;base64,", image_b64))))
  } else user_msg
  msgs[[length(msgs) + 1]] <- list(role = "user", content = user_content)

  res <- tryCatch(
    httr::POST(
      url = "https://api.openai.com/v1/chat/completions",
      httr::add_headers(Authorization = paste("Bearer", key)),
      httr::content_type_json(),
      body = jsonlite::toJSON(list(model = .CHAT_MODEL, messages = msgs, temperature = 0.1), auto_unbox = TRUE)
    ), error = function(e) NULL)
  if (is.null(res)) return("⚠️ Could not reach the AI service (network error).")
  if (httr::status_code(res) != 200) return(paste0("⚠️ API error (HTTP ", httr::status_code(res),
    "). Your model id may be wrong or not vision-capable — set .CHAT_MODEL in mod_chat.R."))
  parsed <- httr::content(res, "parsed")
  cont <- tryCatch(parsed$choices[[1]]$message$content, error = function(e) NULL)
  if (is.null(cont)) "⚠️ Empty response from the AI service." else cont
}

chatUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$style(HTML(paste0("
      .copilot-fab { display: none !important; }
      .copilot-panel { position: fixed; bottom: 56px; right: 22px; width: 410px; max-width: 94vw; height: 66vh; min-height: 420px;
        z-index: 1059; background: #fff; border-radius: 16px; overflow: hidden; flex-direction: column;
        box-shadow: 0 18px 50px rgba(0,0,0,.28); border: 1px solid #e3e8e3; display: none; }
      .copilot-panel.open { display: flex; animation: copilotIn .16s ease; }
      @keyframes copilotIn { from { opacity: 0; transform: translateY(10px) scale(.98); } to { opacity: 1; transform: none; } }
      .copilot-head { background: linear-gradient(135deg, #2e7d32, #43a047); color: #fff; padding: 12px 14px; display: flex; align-items: center; gap: 10px; }
      .copilot-avatar { width: 34px; height: 34px; border-radius: 50%; background: rgba(255,255,255,.18); display: flex; align-items: center; justify-content: center; font-size: 16px; }
      .copilot-title { font-weight: 700; line-height: 1.1; }
      .copilot-sub { font-size: 11px; opacity: .9; }
      .copilot-x { margin-left: auto; color: #fff; opacity: .85; cursor: pointer; font-size: 18px; padding: 2px 6px; }
      .copilot-x:hover { opacity: 1; }
      .copilot-body { flex: 1 1 auto; overflow-y: auto; padding: 14px; background: #f4f7f4; }
      .copilot-foot { border-top: 1px solid #e3e8e3; padding: 10px; background: #fff; }
      .copilot-row { display: flex; gap: 8px; align-items: flex-end; }
      .copilot-row .form-group { margin-bottom: 0; flex: 1 1 auto; }
      .copilot-send { border: none; background: #2e7d32; color: #fff; width: 40px; height: 38px; border-radius: 10px; cursor: pointer; }
      .copilot-send:hover { background: #43a047; }
      .msg { display: flex; gap: 8px; margin-bottom: 12px; }
      .msg .ava { flex: 0 0 auto; width: 26px; height: 26px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 12px; color: #fff; }
      .msg.ai  .ava { background: #2e7d32; }
      .msg.user { flex-direction: row-reverse; }
      .msg.user .ava { background: #6c757d; }
      .bubble { padding: 9px 12px; border-radius: 12px; max-width: 84%; font-size: 13.5px; line-height: 1.45; box-shadow: 0 1px 2px rgba(0,0,0,.06); }
      .msg.ai .bubble  { background: #fff; border: 1px solid #e3e8e3; border-top-left-radius: 3px; }
      .msg.user .bubble { background: #2e7d32; color: #fff; border-top-right-radius: 3px; }
      .bubble p:last-child { margin-bottom: 0; }
      .copilot-chips { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; }
      .copilot-chip { border: 1px solid #cfe3d0; background: #fff; color: #2e7d32; border-radius: 14px; padding: 4px 10px; font-size: 12px; cursor: pointer; }
      .copilot-chip:hover { background: #e8f5e9; }
    "))),
    tags$button(class = "copilot-fab", type = "button",
                onclick = sprintf("document.getElementById('%s').classList.toggle('open')", ns("panel")),
                tags$span(icon("robot")), " Ask Co-Pilot"),
    tags$div(id = ns("panel"), class = "copilot-panel",
      tags$div(class = "copilot-head",
        tags$div(class = "copilot-avatar", icon("robot")),
        tags$div(
          tags$div(class = "copilot-title", "AI Co-Pilot"),
          tags$div(class = "copilot-sub", textOutput(ns("screen_label"), inline = TRUE))),
        tags$span(class = "copilot-x", icon("xmark"), title = "Close")
      ),
      tags$div(class = "copilot-body", id = ns("body"),
        uiOutput(ns("suggestions")),
        uiOutput(ns("history"))
      ),
      tags$div(class = "copilot-foot",
        tags$div(class = "copilot-row",
          textInput(ns("input"), label = NULL, placeholder = "Ask about this screen or dataset..."),
          tags$button(id = ns("send"), class = "action-button copilot-send", type = "button", icon("paper-plane")))
      )
    ),
    tags$script(HTML(sprintf(paste0(
      # Enter-to-send
      "$(document).on('keydown', '#%s', function(e){ if(e.key==='Enter' && !e.shiftKey){ e.preventDefault(); $('#%s').click(); }});",
      # Close: delegated so it fires for clicks on the X span OR the icon inside it.
      "$(document).on('click', '.copilot-x', function(){ $(this).closest('.copilot-panel').removeClass('open'); });"),
      ns("input"), ns("send"))))
  )
}

chatServer <- function(id, dataset_pool, active_dataset, current_view, module_ctx = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    chat_state <- reactiveVal(list(list(role = "assistant",
      content = "Hi! I can only describe what's actually on your current screen — the active dataset and the plot/results in view. Ask me to interpret them.")))

    output$screen_label <- renderText({ paste("Context:", .view_label(current_view())) })

    get_context <- reactive({
      v <- current_view()
      screen <- .view_label(v)
      ds <- active_dataset()
      base <- if (is.null(ds)) paste0("Current screen: ", screen, ". No dataset is loaded yet.")
              else {
                df <- dataset_pool[[ds]]
                paste0("Current screen: ", screen, ".\nActive dataset: '", ds, "' (",
                       nrow(df), " rows x ", ncol(df), " columns).\nColumn structure:\n",
                       paste(utils::capture.output(str(df)), collapse = "\n"))
              }
      extra <- NULL
      if (!is.null(module_ctx) && isTruthy(v) && !is.null(module_ctx[[v]])) {
        extra <- tryCatch(module_ctx[[v]]$context(), error = function(e) NULL)
      }
      if (!is.null(extra) && nzchar(extra)) paste0(base, "\n\n=== Current analysis on screen ===\n", extra) else base
    })

    output$history <- renderUI({
      msgs <- chat_state()
      bubbles <- lapply(msgs, function(m) {
        if (m$role == "user")
          div(class = "msg user", div(class = "ava", icon("user")), div(class = "bubble", m$content))
        else
          div(class = "msg ai", div(class = "ava", icon("robot")), div(class = "bubble", markdown(m$content)))
      })
      bubbles[[length(bubbles) + 1]] <- tags$script(HTML(sprintf(
        "var b=document.getElementById('%s'); if(b){ b.scrollTop=b.scrollHeight; }", ns("body"))))
      do.call(tagList, bubbles)
    })

    output$suggestions <- renderUI({
      if (sum(vapply(chat_state(), function(m) m$role == "user", logical(1))) > 0) return(NULL)
      chips <- c("Describe what this plot shows", "Interpret these results",
                 "Any outliers or problems visible?", "What should I check next?")
      div(class = "copilot-chips",
        lapply(chips, function(p) tags$span(class = "copilot-chip", p,
          onclick = sprintf("Shiny.setInputValue('%s', %s, {priority:'event'})", ns("suggest"), jsonlite::toJSON(p, auto_unbox = TRUE)))))
    })

    send_message <- function(txt) {
      txt <- trimws(txt)
      req(nchar(txt) > 0)
      h <- chat_state(); h[[length(h) + 1]] <- list(role = "user", content = txt); chat_state(h)
      updateTextInput(session, "input", value = "")
      v <- current_view()
      ctx <- get_context()
      img <- NULL
      if (!is.null(module_ctx) && isTruthy(v) && !is.null(module_ctx[[v]]) && is.function(module_ctx[[v]]$plot)) {
        img <- tryCatch(capture_plot_as_base64(module_ctx[[v]]$plot), error = function(e) NULL)
      }
      withProgress(message = if (is.null(img)) "Thinking..." else "Reading the plot...", value = 0.5, {
        ans <- .ask_openai(ctx, isolate(chat_state()), txt, image_b64 = img)
      })
      h <- chat_state(); h[[length(h) + 1]] <- list(role = "assistant", content = ans); chat_state(h)
    }

    observeEvent(input$send, { send_message(input$input) })
    observeEvent(input$suggest, { send_message(input$suggest) })
  })
}
