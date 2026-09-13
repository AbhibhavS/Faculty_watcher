#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# check_updates.R
# Monitors a list of career/recruitment pages for content changes and sends
# a Telegram notification when a page changes. Base R only - no packages to
# install, no compiling, works anywhere R runs (including GitHub Actions).
# ---------------------------------------------------------------------------

CONFIG_FILE <- "institutes.csv"
STATE_FILE  <- "state.csv"
LOG_FILE    <- "run_log.txt"

TELEGRAM_BOT_TOKEN <- Sys.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID   <- Sys.getenv("TELEGRAM_CHAT_ID")

log_msg <- function(...) {
  msg <- paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", paste0(..., collapse = " "))
  cat(msg, "\n")
  cat(msg, "\n", file = LOG_FILE, append = TRUE)
}

# -- Clean raw HTML into stable, comparable text -----------------------------
# Strips things that change on every request/render even when the actual
# content hasn't: <script>/<style> blocks, HTML comments, ASP.NET viewstate /
# eventvalidation / CSRF hidden fields, and collapses whitespace.
clean_html <- function(html) {
  txt <- html
  txt <- gsub("(?is)<script.*?</script>", " ", txt, perl = TRUE)
  txt <- gsub("(?is)<style.*?</style>",   " ", txt, perl = TRUE)
  txt <- gsub("(?is)<!--.*?-->",          " ", txt, perl = TRUE)
  # Strip volatile hidden-field tokens (ASP.NET ERP portals, CSRF tokens, nonces)
  txt <- gsub('(?i)name="__VIEWSTATE[^"]*"\\s+value="[^"]*"', "", txt, perl = TRUE)
  txt <- gsub('(?i)name="__EVENTVALIDATION"\\s+value="[^"]*"', "", txt, perl = TRUE)
  txt <- gsub('(?i)(csrf|nonce|token|__RequestVerificationToken)[a-z_-]*"\\s+value="[^"]*"', "", txt, perl = TRUE)
  # Strip all remaining tags
  txt <- gsub("(?is)<[^>]+>", " ", txt, perl = TRUE)
  # Decode a few common HTML entities
  txt <- gsub("&nbsp;", " ", txt, fixed = TRUE)
  txt <- gsub("&amp;",  "&", txt, fixed = TRUE)
  # Collapse whitespace
  txt <- gsub("[ \t\r\n]+", " ", txt)
  trimws(txt)
}

hash_text <- function(txt) {
  f <- tempfile()
  writeLines(txt, f, useBytes = TRUE)
  h <- unname(tools::md5sum(f))
  file.remove(f)
  h
}

fetch_page <- function(url) {
  destfile <- tempfile()
  on.exit(if (file.exists(destfile)) file.remove(destfile), add = TRUE)
  ok <- tryCatch({
    utils::download.file(
      url, destfile, quiet = TRUE, mode = "wb", method = "libcurl",
      headers = c(
        "User-Agent" = "Mozilla/5.0 (compatible; FacultyPageWatcher/1.0; +personal-use-monitor)",
        "Accept" = "text/html"
      )
    )
    TRUE
  }, error = function(e) {
    log_msg("ERROR fetching", url, ":", conditionMessage(e))
    FALSE
  })
  if (!ok) return(NA_character_)
  raw <- tryCatch(readLines(destfile, warn = FALSE, encoding = "UTF-8"), error = function(e) NA)
  if (length(raw) == 1 && is.na(raw)) return(NA_character_)
  paste(raw, collapse = "\n")
}

send_telegram <- function(text) {
  if (nchar(TELEGRAM_BOT_TOKEN) == 0 || nchar(TELEGRAM_CHAT_ID) == 0) {
    log_msg("Telegram not configured (TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID missing) - skipping notification. Message was:", text)
    return(invisible(FALSE))
  }
  api_url <- sprintf(
    "https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s&disable_web_page_preview=true",
    TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, utils::URLencode(text, reserved = TRUE)
  )
  tryCatch({
    resp <- readLines(url(api_url), warn = FALSE)
    log_msg("Telegram notification sent.")
  }, error = function(e) {
    log_msg("ERROR sending Telegram message:", conditionMessage(e))
  })
}

# -- Main ---------------------------------------------------------------------
main <- function() {
  if (!file.exists(CONFIG_FILE)) stop("Missing ", CONFIG_FILE)

  config <- read.csv(CONFIG_FILE, stringsAsFactors = FALSE)

  if (file.exists(STATE_FILE)) {
    state <- read.csv(STATE_FILE, stringsAsFactors = FALSE)
  } else {
    state <- data.frame(name = character(), url = character(),
                         hash = character(), last_checked = character(),
                         last_changed = character(), stringsAsFactors = FALSE)
  }

  changed_list <- character()

  for (i in seq_len(nrow(config))) {
    name <- config$name[i]
    url  <- config$url[i]
    log_msg("Checking:", name, "-", url)

    html <- fetch_page(url)
    if (is.na(html)) {
      log_msg("  -> skipped (fetch failed)")
      next
    }

    cleaned  <- clean_html(html)
    new_hash <- hash_text(cleaned)

    prev_row <- state[state$url == url, ]

    if (nrow(prev_row) == 0) {
      # First time seeing this URL - just record baseline, don't alert
      state <- rbind(state, data.frame(
        name = name, url = url, hash = new_hash,
        last_checked = as.character(Sys.time()),
        last_changed = as.character(Sys.time()),
        stringsAsFactors = FALSE
      ))
      log_msg("  -> baseline recorded")
    } else if (prev_row$hash[1] != new_hash) {
      log_msg("  -> CHANGE DETECTED")
      changed_list <- c(changed_list, sprintf("%s\n%s", name, url))
      state[state$url == url, "hash"] <- new_hash
      state[state$url == url, "last_checked"] <- as.character(Sys.time())
      state[state$url == url, "last_changed"] <- as.character(Sys.time())
    } else {
      state[state$url == url, "last_checked"] <- as.character(Sys.time())
      log_msg("  -> no change")
    }

    Sys.sleep(1) # be polite to the servers
  }

  write.csv(state, STATE_FILE, row.names = FALSE)

  if (length(changed_list) > 0) {
    msg <- paste0(
      "\U0001F4E2 Recruitment page update detected!\n\n",
      paste(changed_list, collapse = "\n\n")
    )
    send_telegram(msg)
  } else {
    log_msg("No changes this run.")
  }
}

if (identical(environment(), globalenv()) && sys.nframe() == 0) {
  main()
}
