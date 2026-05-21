library(rsconnect)

# First-time setup on a new device:
# rsconnect::setAccountInfo(name="<ACCOUNT>", token="<TOKEN>", secret="<SECRET>")
# See: https://shiny.posit.co/r/articles/share/shinyapps/
# Tokens: https://www.shinyapps.io/admin/#/tokens

# Note: Run 4-ato-scoring.qmd (sync-app-data chunk) before deploying
# to ensure _app/data/ is populated with the latest scored data.

rsconnect::deployApp(
  appDir = "_app",
  appName = "housing-site-evaluator",
  appTitle = "Wasatch Front Housing Site Evaluator",
  # appId = 16816193,
  account = "wfrc",
  forceUpdate = TRUE
)
