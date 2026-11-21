# Dynamic Island for macOS

Turns the MacBook notch into an iPhone‑style Dynamic Island. Click the notch to expand it: today's events from macOS Calendar, today's schedule from Google Calendar and a settings button; click outside (or move the cursor away) to collapse. Right‑click the island for quick actions. The app has no Dock icon and no menu bar item.

## Requirements

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`) — Swift and git are used both for building and for self‑updates.

## Install

```bash
./scripts/install.sh
```

Builds `build/DynamicIsland.app`, installs it to `/Applications` (or `~/Applications`) and launches it. Build only: `./scripts/build.sh`.

## Calendars

Both calendars refresh every 5 minutes in the background (and on wake / Calendar changes).

- **macOS Calendar** — grant access on first launch; choose calendars in Settings → macOS Calendar.
- **Google Calendar** — in [Google Cloud Console](https://console.cloud.google.com/): enable *Google Calendar API*, configure the OAuth consent screen (add yourself as a test user, or publish the app — in *Testing* mode refresh tokens expire after 7 days), create an OAuth client ID of type **Desktop app**. Paste Client ID / Client Secret into Settings → Google Calendar → **Connect**, sign in in the browser.

## Local config and secrets

Credentials, tokens and calendar selection are stored outside the repository in `~/Library/Application Support/DynamicIsland/config.json` (directory `0700`, file `0600`). Never commit configs or secrets.

## Updates

Settings → Updates → **Check for Updates** compares the commit the app was built from with the tip of `main` on `origin`. If a newer commit is pushed, **Update & Restart** clones/fetches the repo into `~/Library/Application Support/DynamicIsland/source`, builds it, replaces the installed app and relaunches it. Your working copy is never touched. Installer log: `~/Library/Application Support/DynamicIsland/update.log`.

## Layout

- `Sources/DynamicIsland/IslandController.swift` — panel above the menu bar, mouse tracking, expand/collapse.
- `Sources/DynamicIsland/NotchShape.swift` — animatable notch silhouette.
- `Sources/DynamicIsland/DashboardView.swift` — expanded island: events, schedule, settings button.
- `Sources/DynamicIsland/CalendarStore.swift` — background refresh of both calendars.
- `Sources/DynamicIsland/MacCalendarSource.swift` — EventKit.
- `Sources/DynamicIsland/GoogleCalendarClient.swift`, `LoopbackServer.swift` — Google OAuth (loopback + PKCE) and Calendar API.
- `Sources/DynamicIsland/LocalConfig.swift` — local config/secrets storage outside git.
- `Sources/DynamicIsland/UpdateManager.swift`, `scripts/self-update.sh` — git‑based updater.
- `Sources/DynamicIsland/SettingsView.swift` — settings window.
