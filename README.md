# Faculty Recruitment Page Watcher

Checks a list of IIT/NIT/IIIT recruitment pages on a schedule and sends you
a Telegram message when any of them changes. Runs entirely on GitHub's free
Actions runners — your computer doesn't need to be on.

## How it works

- `institutes.csv` — the list of pages to watch (name + URL). Edit this to
  add/remove pages.
- `check_updates.R` — downloads each page, strips out things that change on
  every request even when nothing meaningful changed (scripts, styles,
  ASP.NET `__VIEWSTATE`/`__EVENTVALIDATION` tokens, CSRF tokens), hashes the
  remaining text, and compares it to the last known hash.
- `state.csv` — the last-seen hash per page. Committed back to the repo
  after every run so state persists between scheduled runs.
- `.github/workflows/monitor.yml` — runs `check_updates.R` every 3 hours
  (edit the cron line to change frequency) via GitHub Actions.

The first run for any URL just records a baseline — it won't notify you
about content that was already there, only about changes *after* that.

## Setup (10 minutes)

1. **Create a Telegram bot** (free, 2 minutes):
   - Open Telegram, message **@BotFather**, send `/newbot`, follow the
     prompts. You'll get a **bot token** like `123456:ABC-DEF...`.
   - Message your new bot anything (e.g. "hi") so it can message you back.
   - Get your **chat ID**: message **@userinfobot** on Telegram, it'll
     reply with your numeric ID.

2. **Create a GitHub repo** and push these files to it.

3. **Add secrets** in your repo: Settings → Secrets and variables → Actions
   → New repository secret:
   - `TELEGRAM_BOT_TOKEN` = your bot token
   - `TELEGRAM_CHAT_ID` = your chat ID

4. That's it. The workflow runs automatically every 3 hours. You can also
   trigger it manually: Actions tab → "Monitor faculty recruitment pages"
   → Run workflow.

## Things to know before relying on this

- **Two URLs need attention:**
  - `IIT Jodhpur` (`erponline.iitj.ac.in`) — this site's `robots.txt`
    explicitly disallows automated access. I did not build around that;
    you may want to remove this row from `institutes.csv` and check it
    manually instead.
  - `IIT Kharagpur` (`erp.iitkgp.ac.in`) — the listing table appeared to
    load its rows via JavaScript/AJAX rather than in the raw HTML, based on
    a quick check. A plain download may not "see" new rows at all. Worth
    verifying manually once, and if so, this one would need a headless
    browser (e.g. R's `chromote` package) instead of a simple download —
    let me know if you want that added.
- **Be a polite scraper**: the script waits 1 second between requests and
  checks every 3 hours by default — please don't turn this down to
  every-few-minutes across 20 institutional servers.
- **False positives are still possible** on pages with other rotating
  elements (rotating banners, "last visitor count", etc.) — if a page
  notifies you too often for no real reason, tell me which one and I can
  add a more targeted content selector for it.
- Some pages (e.g. `IIT Patna` → `/notices`) are general notice boards, not
  faculty-only — you'll get pinged for any notice, not just recruitment
  ones. Let me know if you'd rather filter by keyword (e.g. only alert if
  "faculty" or "recruitment" appears in the changed text).

## Running locally instead (optional)

You don't need GitHub Actions — this also runs fine as a local cron job:

```bash
export TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
export TELEGRAM_CHAT_ID="123456789"
Rscript check_updates.R
```

Add a line like the following to `crontab -e` to run it every 3 hours:

```
0 */3 * * * cd /path/to/this/folder && Rscript check_updates.R >> cron.log 2>&1
```
