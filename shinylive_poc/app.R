library(shiny)
library(bslib)
library(nlme)
library(ggplot2)

ui <- page_sidebar(
  title = "SimpleAnalysis wasm proof-of-concept",
  sidebar = sidebar(
    selectInput("grp", "Random effect grouping", choices = c("Subject")),
    actionButton("fit", "Fit LME", class = "btn-success")
  ),
  card(card_header("Model summary"), verbatimTextOutput("summ")),
  card(card_header("Fitted vs observed"), plotOutput("plt"))
)

server <- function(input, output, session) {
  mod <- eventReactive(input$fit, {
    lme(distance ~ age, random = ~ 1 | Subject, data = Orthodont,
        control = lmeControl(opt = "optim", msMaxIter = 1000))
  })
  output$summ <- renderPrint({ req(mod()); summary(mod()) })
  output$plt <- renderPlot({
    req(mod())
    df <- data.frame(obs = Orthodont$distance, fit = fitted(mod()))
    ggplot(df, aes(fit, obs)) + geom_point(color = "#2e7d32") +
      geom_abline(slope = 1, intercept = 0, linetype = 2) + theme_minimal()
  })
}

shinyApp(ui, server)
