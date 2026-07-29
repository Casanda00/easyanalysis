# ==========================================================================
# MODULE: Co-Analyst chat  (floating panel, app-level)
# chatUI(id) / chatServer(id, dataset_pool, active_dataset, current_view, module_ctx)
# --------------------------------------------------------------------------
# The Co-Analyst is now an AGENT: besides describing the current screen it can
# RUN analyses itself via OpenAI tool-calling (tools defined in agent_tools.R,
# executed against dataset_pool with the app's own fitting functions).
#
# Context fed to the model =
#   active dataset (name + dims + structure)
# + the CURRENT screen's live analysis text  (module_ctx[[view]]$context())
# + an IMAGE of the current screen's plot     (module_ctx[[view]]$plot())
# + TOOLS it may call to compute new results.
#
# Transport auto-selects: in the browser build (webR/wasm) there is no libcurl,
# so requests go through a synchronous XHR in the webR worker; on a normal
# server httr is used. The API key is supplied by the user in the panel (kept
# only in the session) and falls back to OPENAI_API_KEY on a server.
# ==========================================================================

.CHAT_MODEL <- "gpt-5.4-nano"  # must be a vision- AND tool-calling-capable model

# The methods EasyAnalysis actually provides (fed to the agent so it never claims
# a method is missing when the app has a screen for it). Keep in sync with the app.
.APP_METHODS <- paste(
  "- Statistics: descriptive stats; t-tests & other hypothesis tests; ANOVA (+ Tukey HSD);",
  "  linear regression (multiple, polynomial, ridge/lasso, Poisson); linear mixed effects (LME);",
  "  logistic/multinomial regression; PCA; GAM; survival analysis; time series; SEM; Bayesian.",
  "- Discriminant analysis screen: LDA, weighted LDA, QDA, regularized LDA (RLDA), kernel DA (KDA),",
  "  locally linear DA (LLDA), and maximum-margin (MMC) — all built in.",
  "- Machine learning: random forest, one-vs-all classification, clustering (k-means / hierarchical /",
  "  Gower-PAM), decision tree, neural network, SVM, XGBoost.",
  "- Spatial / remote sensing / LiDAR: raster analysis, terrain, hydrology, land classification,",
  "  suitability, wind, night-time lights, climate trend, satellite/STAC download, surface models,",
  "  LiDAR point cloud / CHM / individual-tree detection / metrics.",
  "- Data tools: upload & clean data, an R Console for custom R code, and a References screen.")

.VIEW_LABELS <- c(
  data = "Data & Exploration", lm = "Linear Regression", lme = "Linear Mixed Effects",
  anova = "ANOVA", logistic = "Logistic Regression", rf = "Random Forest",
  da = "Discriminant Analysis", clustering = "Clustering",
  classification = "Classification (one-vs-all)", pointcloud = "LiDAR Point Cloud / 3D",
  chm_itd = "CHM & Individual Tree Detection", metrics = "LiDAR Metrics & Evaluation",
  rconsole = "R Console", references = "References")

.view_label <- function(v) {
  if (!isTruthy(v) || is.na(.VIEW_LABELS[v])) return("the app")
  unname(.VIEW_LABELS[v])
}

# --- platform detection + HTTP transport -----------------------------------
# In the browser (webR/wasm) there is no socket layer, so httr cannot work.
# There we issue the request via a synchronous XMLHttpRequest in the webR
# worker (sync XHR is allowed in workers). Everywhere else: httr as before.
.is_wasm <- function() identical(R.version$os, "emscripten")

# Resolve webR's JS-eval function without a hard dependency on the webr pkg.
.webr_eval_js <- function(js) {
  f <- tryCatch(utils::getFromNamespace("eval_js", "webr"), error = function(e) NULL)
  if (is.null(f)) stop("webr::eval_js unavailable")
  f(js)
}

.http_post_json <- function(url, bearer, body_json) {
  auth <- if (nzchar(bearer %||% "")) paste("Bearer", bearer) else ""
  if (.is_wasm()) {
    js <- paste0(
      "(function(){ try {",
      "var u = ", jsonlite::toJSON(url, auto_unbox = TRUE), ";",
      # relative /api/... must resolve against the SITE origin, not the worker's
      # script path (the XHR runs inside the webR worker under /shinylive/webr/).
      "if (u.charAt(0) === '/') { u = self.location.origin + u; }",
      "var xhr = new XMLHttpRequest();",
      "xhr.open('POST', u, false);",
      "xhr.setRequestHeader('Content-Type','application/json');",
      if (nzchar(auth)) paste0("xhr.setRequestHeader('Authorization', ", jsonlite::toJSON(auth, auto_unbox = TRUE), ");") else "",
      "xhr.send(", jsonlite::toJSON(body_json, auto_unbox = TRUE), ");",
      "return JSON.stringify({status: xhr.status, body: xhr.responseText});",
      "} catch(e) { return JSON.stringify({status: -1, body: String(e)}); } })()")
    out <- tryCatch(.webr_eval_js(js), error = function(e) NULL)
    if (is.null(out)) return(list(status = -1, body = "webR JS bridge unavailable"))
    res <- tryCatch(jsonlite::fromJSON(out), error = function(e) list(status = -1, body = "bad bridge response"))
    list(status = res$status, body = res$body)
  } else {
    if (!requireNamespace("httr", quietly = TRUE)) return(list(status = -1, body = "httr not installed"))
    hdrs <- if (nzchar(auth)) httr::add_headers(Authorization = auth) else httr::add_headers()
    r <- tryCatch(httr::POST(url, hdrs,
           httr::content_type_json(), body = body_json), error = function(e) NULL)
    if (is.null(r)) return(list(status = -1, body = "network error"))
    list(status = httr::status_code(r), body = httr::content(r, "text", encoding = "UTF-8"))
  }
}

# --- one raw call to chat/completions --------------------------------------
# Returns the parsed assistant `message` list, or list(.error = "text").
# With a key: straight to OpenAI. Without one: the same-origin proxy
# (/api/chat, a serverless function holding the key in an env var) — so a
# hosted deployment can offer the agent without users needing their own key.
.CHAT_PROXY_PATH <- "/api/chat"

.chat_completion <- function(messages, key, tools = NULL) {
  payload <- list(model = .CHAT_MODEL, messages = messages)
  # GPT-5 family models (incl. *-nano) REJECT `temperature` outright:
  #   400 "Unsupported value: 'temperature' does not support 0.1 with this
  #        model. Only the default (1) value is supported."
  # Only send it for models that actually accept it.
  if (!grepl("^(gpt-5|o[0-9])", .CHAT_MODEL)) payload$temperature <- 0.1
  if (!is.null(tools)) { payload$tools <- tools; payload$tool_choice <- "auto" }
  body <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null")
  use_proxy <- !nzchar(key %||% "")
  url <- if (use_proxy) .CHAT_PROXY_PATH else "https://api.openai.com/v1/chat/completions"
  resp <- .http_post_json(url, if (use_proxy) "" else key, body)
  if (resp$status != 200) {
    if (use_proxy && resp$status %in% c(-1, 404, 405))
      return(list(.error = paste0("This deployment has no built-in AI key. ",
                                  "Click the gear icon and paste your own OpenAI API key.")))
    detail <- tryCatch(jsonlite::fromJSON(resp$body)$error$message, error = function(e) NULL)
    return(list(.error = paste0("API error (", resp$status, ")",
                                if (!is.null(detail)) paste0(": ", detail) else
                                paste0(": ", substr(resp$body, 1, 200)))))
  }
  parsed <- tryCatch(jsonlite::fromJSON(resp$body, simplifyVector = FALSE), error = function(e) NULL)
  msg <- tryCatch(parsed$choices[[1]]$message, error = function(e) NULL)
  if (is.null(msg)) return(list(.error = "Empty or unparsable response from the AI service."))
  msg
}

# --- agent loop -------------------------------------------------------------
# While the model requests tool calls, execute them against dataset_pool and
# feed results back; stop when it answers in plain text (or after max_rounds).
# Returns list(text = <final answer>, actions = <chr vec of tool calls made>).
# Human-readable label for what the agent is doing right now (drives the live
# status text instead of a hardcoded "Thinking...").
.agent_status_label <- function(fname, fargs) {
  switch(fname,
    "list_datasets"    = "Checking your datasets…",
    "describe_dataset" = "Reading your data…",
    "column_stats"     = "Computing column statistics…",
    "correlate"        = "Computing correlations…",
    "run_analysis"     = {
      m <- tolower(fargs$method %||% "")
      lbl <- switch(m,
        "descriptive" = "descriptive statistics", "lm" = "a linear regression",
        "anova" = "an ANOVA", "ttest" = "a t-test", "lme" = "a mixed-effects model",
        "logistic" = "a logistic regression", "rf" = "a random forest",
        "clustering" = "clustering", "pca" = "a PCA", m)
      if (nzchar(lbl)) paste0("Running ", lbl, "…") else "Running the analysis…"
    },
    paste0("Running ", fname, "…"))
}

.ask_openai_agent <- function(context, history, user_msg, key, dataset_pool,
                              image_b64 = NULL, max_rounds = 6, status_cb = NULL) {
  .say <- function(m) if (is.function(status_cb)) try(status_cb(m), silent = TRUE)
  # No personal key is fine: .chat_completion() falls back to the /api/chat
  # proxy (which supplies the deployment's own key). If neither exists, the
  # proxy call fails and the user is told to paste a key.
  if (!requireNamespace("jsonlite", quietly = TRUE))
    return(list(text = "Error: Package 'jsonlite' is required for the Co-Analyst.", actions = character(0)))

  sys_prompt <- paste(
    "You are the Co-Analyst embedded in EasyAnalysis, a universal scientific-analysis app.",
    "You can RUN some analyses yourself with the tools: list_datasets, describe_dataset,",
    "column_stats, correlate, run_analysis.",
    "",
    "GROUNDING — this is critical, the user does NOT want hallucination:",
    "- Use ONLY the tool outputs, the CONTEXT block, and the attached plot image. Do NOT use outside or",
    "general knowledge about the user's specific data, and NEVER invent column names, values, coefficients,",
    "p-values, accuracies, cluster counts or trends. If it is not in a tool result / context / image, you",
    "do not know it — say so plainly.",
    "- Report the actual numbers from tool output. If a tool returns a line starting with ERROR, fix the",
    "arguments and retry (at most twice), or tell the user what is needed.",
    "",
    "SCOPE — answer the question that was asked, nothing more:",
    "- Do NOT volunteer 'best next step' suggestions, recommend switching variables, or propose alternative",
    "analyses UNLESS the user explicitly asks for a recommendation or what to do next. Unsolicited advice",
    "biases the user. Just answer what they asked, using the data.",
    "",
    "THE APP'S CAPABILITIES — never tell the user a method is 'not available' if it is in this list; if you",
    "cannot run it with your own tools, point them to the screen that does it:",
    .APP_METHODS,
    "You can directly run (via run_analysis): descriptive, lm, anova, ttest, lme, logistic, rf, clustering,",
    "pca. For any OTHER method above (e.g. LLDA/QDA/LDA discriminant analysis, SVM, XGBoost, GAM, survival,",
    "SEM, Bayesian, time-series, spatial/LiDAR), say the app HAS it on its dedicated screen and direct the",
    "user there — do not claim it is missing.",
    "",
    "Be concise; prefer short bullets. If something cannot be determined from what you have, say so.")

  msgs <- list(
    list(role = "system", content = sys_prompt),
    list(role = "system", content = paste0("CONTEXT:\n", context)))
  for (m in utils::tail(history, 6))
    if (!is.null(m$content) && nzchar(m$content))
      msgs[[length(msgs) + 1]] <- list(role = m$role, content = m$content)

  user_content <- if (!is.null(image_b64)) {
    list(list(type = "text", text = user_msg),
         list(type = "image_url", image_url = list(url = paste0("data:image/png;base64,", image_b64))))
  } else user_msg
  msgs[[length(msgs) + 1]] <- list(role = "user", content = user_content)

  actions <- character(0)
  .EA_AGENT_UI$action <- NULL      # side channel: one request, one action
  tools <- .agent_tools_spec()

  for (round in seq_len(max_rounds)) {
    .say(if (round == 1) "Thinking…" else "Thinking it through…")
    msg <- .chat_completion(msgs, key, tools = tools)
    if (!is.null(msg$.error))
      return(list(text = paste0("Error: ", msg$.error), actions = actions,
                  ui_action = .EA_AGENT_UI$action))

    tool_calls <- msg$tool_calls
    if (is.null(tool_calls) || !length(tool_calls)) {
      txt <- msg$content %||% "(no answer)"
      if (is.list(txt)) txt <- paste(vapply(txt, function(p) p$text %||% "", character(1)), collapse = "")
      return(list(text = txt, actions = actions, ui_action = .EA_AGENT_UI$action))
    }

    # Record the assistant turn (with its tool_calls) verbatim, then run each tool.
    msgs[[length(msgs) + 1]] <- list(role = "assistant", content = NULL, tool_calls = tool_calls)
    for (tc in tool_calls) {
      fname <- tc$`function`$name
      fargs <- tryCatch(jsonlite::fromJSON(tc$`function`$arguments %||% "{}"), error = function(e) list())
      arg_desc <- paste(names(fargs), unlist(lapply(fargs, function(x) paste(x, collapse = "+"))),
                        sep = "=", collapse = ", ")
      actions <- c(actions, if (nzchar(arg_desc)) paste0(fname, "(", arg_desc, ")") else fname)
      .say(.agent_status_label(fname, fargs))
      result <- .agent_exec_tool(fname, fargs, dataset_pool)
      msgs[[length(msgs) + 1]] <- list(role = "tool", tool_call_id = tc$id, content = result)
    }
  }
  list(text = "Error: Reached the analysis step limit without a final answer. Try a more specific request.",
       actions = actions, ui_action = .EA_AGENT_UI$action)
}

chatUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$style(HTML(paste0("
      .copilot-fab { display: none !important; }
      /* First-class RIGHT DOCK: full viewport height (below topbar, above status
         bar), wider than the old floating bubble. Dark-themed to match the app. */
      .copilot-panel { position: fixed; top: 46px; right: 0; bottom: 30px; width: 460px; max-width: 96vw;
        z-index: 1059; background: var(--panel); border-radius: 12px 0 0 12px; overflow: hidden;
        flex-direction: column; box-shadow: -12px 0 40px rgba(0,0,0,.45);
        border: 1px solid var(--line); border-right: none; display: none; }
      .copilot-panel.open { display: flex; animation: copilotIn .18s ease; }
      @keyframes copilotIn { from { opacity: 0; transform: translateX(24px); } to { opacity: 1; transform: none; } }
      .copilot-head { background: linear-gradient(135deg, #1b3a1d, #2e7d32); color: #fff; padding: 13px 15px; display: flex; align-items: center; gap: 11px; }
      .copilot-avatar { width: 36px; height: 36px; border-radius: 50%; background: rgba(255,255,255,.18); display: flex; align-items: center; justify-content: center; font-size: 16px; }
      .copilot-title { font-weight: 700; line-height: 1.1; font-size: 15px; }
      .copilot-sub { font-size: 11px; opacity: .9; font-family: var(--mono); }
      .copilot-gear { color: #fff; opacity: .85; cursor: pointer; font-size: 15px; padding: 2px 4px; margin-left: auto; }
      .copilot-gear:hover { opacity: 1; }
      .copilot-x { color: #fff; opacity: .85; cursor: pointer; font-size: 18px; padding: 2px 6px; }
      .copilot-x:hover { opacity: 1; }
      .copilot-key { background: var(--sunk); border-bottom: 1px solid var(--line); padding: 10px 12px; display: none; }
      .copilot-key.open { display: block; }
      .copilot-key .form-group { margin-bottom: 6px; }
      .copilot-key small { color: var(--bark); }
      .copilot-body { flex: 1 1 auto; overflow-y: auto; padding: 16px; background: var(--sunk); }
      .copilot-foot { border-top: 1px solid var(--line); padding: 11px; background: var(--panel); }
      .copilot-row { display: flex; gap: 8px; align-items: flex-end; }
      .copilot-row .form-group { margin-bottom: 0; flex: 1 1 auto; }
      .copilot-send { border: none; background: var(--forest); color: var(--onbrand); width: 40px; height: 38px; border-radius: 10px; cursor: pointer; }
      .copilot-send:hover { background: var(--canopy); }
      .msg { display: flex; gap: 8px; margin-bottom: 12px; }
      .msg .ava { flex: 0 0 auto; width: 26px; height: 26px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 12px; color: #fff; }
      .msg.ai  .ava { background: var(--forest); color: var(--onbrand); }
      .msg.user { flex-direction: row-reverse; }
      .msg.user .ava { background: var(--bark); }
      .bubble { padding: 9px 12px; border-radius: 12px; max-width: 84%; font-size: 13.5px; line-height: 1.45; box-shadow: 0 1px 2px rgba(0,0,0,.2); }
      .msg.ai .bubble  { background: var(--panel); border: 1px solid var(--line); color: var(--ink); border-top-left-radius: 3px; }
      .msg.user .bubble { background: var(--forest); color: var(--onbrand); border-top-right-radius: 3px; }
      .bubble p:last-child { margin-bottom: 0; }
      .copilot-actions { font-size: 11px; color: var(--bark); margin: -6px 0 12px 34px; }
      .copilot-actions code { background: var(--tint); color: var(--canopy); padding: 1px 5px; border-radius: 4px; }
      .copilot-chips { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; }
      .copilot-chip { border: 1px solid var(--line); background: var(--panel); color: var(--canopy); border-radius: 14px; padding: 5px 11px; font-size: 12px; cursor: pointer; }
      .copilot-chip:hover { border-color: var(--canopy); }
      /* typing indicator while the agent works */
      .copilot-typing { display: flex; gap: 4px; align-items: center; padding: 12px 14px; }
      .copilot-typing .dot { width: 7px; height: 7px; border-radius: 50%; background: #9bb69c;
        animation: copilotBlink 1.2s infinite ease-in-out both; }
      .copilot-typing .dot:nth-child(2) { animation-delay: .18s; }
      .copilot-typing .dot:nth-child(3) { animation-delay: .36s; }
      @keyframes copilotBlink { 0%, 80%, 100% { opacity: .25; } 40% { opacity: 1; } }
      .copilot-send:disabled { background: #a5c9a7; cursor: not-allowed; }
      /* merged Recommend + Ask tabs */
      .copilot-tabs { display: flex; gap: 4px; padding: 8px 10px 0; background: var(--panel);
        border-bottom: 1px solid var(--line); flex: none; }
      .copilot-tab { flex: 1; border: 1px solid var(--line); border-bottom: none; background: var(--sunk);
        color: var(--bark); border-radius: 8px 8px 0 0; padding: 8px 10px; font: 600 12px var(--ui);
        cursor: pointer; }
      .copilot-tab.on { background: var(--forest); border-color: var(--forest); color: var(--onbrand); }
      .copilot-pane { display: none; flex: 1 1 auto; min-height: 0; flex-direction: column; overflow: hidden; }
      .copilot-pane.on { display: flex; }
      #chat-pane_rec { overflow-y: auto; padding: 12px; background: var(--sunk); }
      .copilot-recintro { font-size: 12.5px; color: var(--bark); line-height: 1.5; background: var(--panel);
        border: 1px solid var(--line); border-left: 2px solid var(--forest); border-radius: 8px;
        padding: 10px 12px; margin-bottom: 12px; }
    "))),
    tags$button(class = "copilot-fab", type = "button",
                onclick = sprintf("document.getElementById('%s').classList.toggle('open')", ns("panel")),
                tags$span(icon("wand-magic-sparkles")), " Ask Co-Analyst"),
    tags$div(id = ns("panel"), class = "copilot-panel",
      tags$div(class = "copilot-head",
        tags$div(class = "copilot-avatar", icon("wand-magic-sparkles")),
        tags$div(
          tags$div(class = "copilot-title", "Co-Analyst"),
          tags$div(class = "copilot-sub", textOutput(ns("screen_label"), inline = TRUE))),
        tags$span(class = "copilot-gear", id = ns("gear"), icon("gear"), title = "API key"),
        tags$span(class = "copilot-x", icon("xmark"), title = "Close")
      ),
      tags$div(class = "copilot-key", id = ns("keybox"),
        passwordInput(ns("api_key"), "OpenAI API key (kept only in this session):",
                      placeholder = "sk-..."),
        tags$small("Runs in your browser — the key stays on your machine and is sent only to OpenAI.")
      ),
      # MERGED: Recommend is the Co-Analyst's opening move — "what do you want to
      # find out?" comes first, then the free-form chat. One assistant surface.
      tags$div(class = "copilot-tabs",
        tags$button(class = "copilot-tab on", type = "button", `data-pane` = ns("pane_rec"),
                    icon("wand-magic-sparkles"), " Recommend"),
        tags$button(class = "copilot-tab", type = "button", `data-pane` = ns("pane_ask"),
                    icon("comments"), " Ask")),
      tags$div(id = ns("pane_rec"), class = "copilot-pane on",
        tags$div(class = "copilot-recintro",
          "Not sure which method fits? Describe what you want to find out and I'll ",
          "recommend the right analysis — then run it for you in the Ask tab."),
        recommendToolsUI("recommend"),
        recommendCanvasUI("recommend")
      ),
      tags$div(id = ns("pane_ask"), class = "copilot-pane",
        tags$div(class = "copilot-body", id = ns("body"),
          uiOutput(ns("suggestions")),
          uiOutput(ns("history")),
          uiOutput(ns("busy_ui"))
        ),
      tags$div(class = "copilot-foot",
        tags$div(class = "copilot-row",
          textInput(ns("input"), label = NULL, placeholder = "Ask about this screen, or ask me to run an analysis..."),
          tags$button(id = ns("send"), class = "action-button copilot-send", type = "button", icon("paper-plane")))
      )
      )   # /pane_ask
    ),
    tags$script(HTML(sprintf(paste0(
      "$(document).on('keydown', '#%s', function(e){ if(e.key==='Enter' && !e.shiftKey){ e.preventDefault(); Shiny.setInputValue('%s', this.value, {priority:'event'}); }});",
      "$(document).on('click', '.copilot-x', function(){ $(this).closest('.copilot-panel').removeClass('open'); });",
      # merged Recommend/Ask tabs inside the dock
      "$(document).on('click', '.copilot-tab', function(){ var p=$(this).closest('.copilot-panel');",
      "  p.find('.copilot-tab').removeClass('on'); $(this).addClass('on');",
      "  p.find('.copilot-pane').removeClass('on');",
      "  var t=document.getElementById($(this).data('pane')); if(t) t.classList.add('on'); });",
      "$(document).on('click', '#%s', function(){ document.getElementById('%s').classList.toggle('open'); });",
      # disable send + keep the newest message in view while the agent works
      "Shiny.addCustomMessageHandler('copilotBusy', function(m){",
      "  var b=document.getElementById(m.id); if(b){ b.disabled=!!m.busy; }",
      "  var body=document.getElementById('%s'); if(body){ body.scrollTop=body.scrollHeight; }",
      "});"),
      ns("input"), ns("enter"), ns("gear"), ns("keybox"), ns("body"))))
  )
}

chatServer <- function(id, dataset_pool, active_dataset, current_view, module_ctx = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # API key: session-scoped reactive; seed from env for the server build.
    api_key <- reactiveVal(Sys.getenv("OPENAI_API_KEY"))
    observeEvent(input$api_key, { if (nzchar(input$api_key)) api_key(input$api_key) },
                 ignoreInit = TRUE)

    greet <- paste0(
      "Hi! I'm your analysis agent — I can describe what's on your screen AND run models for you. ",
      "Try: \"fit an LME of tree height by soil class with plot as random effect\", or ",
      "\"which predictors matter most for growth?\" ",
      "(If this deployment has no built-in AI key, click the gear icon and paste your own — it stays in your browser.)")
    chat_state <- reactiveVal(list(list(role = "assistant", content = greet, actions = character(0))))

    output$screen_label <- renderText({ paste("Context:", .view_label(current_view())) })

    get_context <- reactive({
      v <- current_view()
      screen <- .view_label(v)
      ds <- active_dataset()
      base <- if (is.null(ds)) paste0("Current screen: ", screen, ". No dataset is active yet.")
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
      bubbles <- list()
      for (m in msgs) {
        if (m$role == "user") {
          bubbles[[length(bubbles) + 1]] <-
            div(class = "msg user", div(class = "ava", icon("user")), div(class = "bubble", m$content))
        } else {
          bubbles[[length(bubbles) + 1]] <-
            div(class = "msg ai", div(class = "ava", icon("wand-magic-sparkles")), div(class = "bubble", markdown(m$content)))
          if (!is.null(m$actions) && length(m$actions))
            bubbles[[length(bubbles) + 1]] <- div(class = "copilot-actions",
              HTML(paste0("<i class='fa fa-gear'></i> ran ", paste0("<code>", m$actions, "</code>", collapse = " → "))))
        }
      }
      bubbles[[length(bubbles) + 1]] <- tags$script(HTML(sprintf(
        "var b=document.getElementById('%s'); if(b){ b.scrollTop=b.scrollHeight; }", ns("body"))))
      do.call(tagList, bubbles)
    })

    output$suggestions <- renderUI({
      if (sum(vapply(chat_state(), function(m) m$role == "user", logical(1))) > 0) return(NULL)
      chips <- c("Summarise the active dataset", "Which predictors matter most?",
                 "Fit a suitable model for me", "Interpret what's on this screen")
      div(class = "copilot-chips",
        lapply(chips, function(p) tags$span(class = "copilot-chip", p,
          onclick = sprintf("Shiny.setInputValue('%s', %s, {priority:'event'})", ns("suggest"), jsonlite::toJSON(p, auto_unbox = TRUE)))))
    })

    # TRUE while the agent is working — drives the typing indicator and stops
    # double-sends. An agent turn can take 10-30s (tool calls + vision), so the
    # panel must visibly show it is busy rather than looking dead.
    busy <- reactiveVal(FALSE)

    send_message <- function(txt) {
      txt <- trimws(txt)
      req(nchar(txt) > 0)
      if (isTRUE(busy())) return(invisible(NULL))   # ignore while a turn is in flight
      busy(TRUE)
      on.exit(busy(FALSE), add = TRUE)

      h <- chat_state(); h[[length(h) + 1]] <- list(role = "user", content = txt); chat_state(h)
      updateTextInput(session, "input", value = "")
      v <- current_view()
      ctx <- get_context()
      img <- NULL
      if (!is.null(module_ctx) && isTruthy(v) && !is.null(module_ctx[[v]]) && is.function(module_ctx[[v]]$plot)) {
        img <- tryCatch(capture_plot_as_base64(module_ctx[[v]]$plot), error = function(e) NULL)
      }
      res <- withProgress(message = if (is.null(img)) "Thinking…" else "Reading the screen…",
                          value = 0.5, {
        .ask_openai_agent(ctx, isolate(chat_state()), txt, key = api_key(),
                          dataset_pool = dataset_pool, image_b64 = img,
                          status_cb = function(m) try(setProgress(message = m), silent = TRUE))
      })
      h <- chat_state()
      h[[length(h) + 1]] <- list(role = "assistant", content = res$text, actions = res$actions)
      # Drive the real screen: switch dataset, open the tool, fill it, press Run.
      if (!is.null(res$ui_action))
        session$sendCustomMessage("ea_agent_ui", res$ui_action)
      chat_state(h)
    }

    # Typing indicator + disabled send while the agent works.
    output$busy_ui <- renderUI({
      if (!isTRUE(busy())) return(NULL)
      div(class = "msg ai",
        div(class = "ava", icon("wand-magic-sparkles")),
        div(class = "bubble copilot-typing",
            span(class = "dot"), span(class = "dot"), span(class = "dot")))
    })
    observe({
      session$sendCustomMessage("copilotBusy",
        list(id = ns("send"), busy = isTRUE(busy())))
    })

    observeEvent(input$send, { send_message(input$input) })
    observeEvent(input$enter, { send_message(input$enter) })   # Enter key: value passed directly (race-free)
    observeEvent(input$suggest, { send_message(input$suggest) })
  })
}
