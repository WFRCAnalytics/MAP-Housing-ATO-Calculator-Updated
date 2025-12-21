library(rsconnect)
library(tools)

src <- "_output/h3_scored.parquet"
dst <- "_app/h3_scored.parquet"

# If this is the first time deploying fromt the device, you have to run the following.
# rsconnect::setAccountInfo(name="<ACCOUNT>", token="<TOKEN>", secret="<SECRET>")

# Check Reference at: https://shiny.posit.co/r/articles/share/shinyapps/ for details.
# Check https://www.shinyapps.io/admin/#/tokens for the ACCOUNT, TOKEN, and SECRET

# Copy if destination is missing OR if the file content (checksum) has changed
if (!file.exists(dst) || (tools::md5sum(src) != tools::md5sum(dst))) {
  message("Updating data file...")
  file.copy(src, dst, overwrite = TRUE)
}

# Deploy
rsconnect::deployApp(
  appDir = "_app",
  appName = "Housing-ATO-Calculator",
  appTitle = "Wasatch Front Housing ATO Calculator",
  # appId = 16342069,
  account = "wfrc",
  forceUpdate = TRUE
)
