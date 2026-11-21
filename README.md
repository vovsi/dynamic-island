# Dynamic Island for macOS

Turns the MacBook notch into an iPhone‑style Dynamic Island. Click the notch to expand it: weather, today's events, today's schedule (Google account calendars) and a settings button; click outside (or move the cursor away) to collapse. Right‑click the island for quick actions. The app has no Dock icon and no menu bar item.

## Requirements

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`) — Swift and git are used both for building and for self‑updates.

## Install

```bash
./scripts/install.sh
```

Builds `build/DynamicIsland.app`, installs it as `Dynamic Island.app` to `/Applications` (or `~/Applications`) and launches it. Build only: `./scripts/build.sh`. App icon: `Support/AppIcon.icns`, regenerate with `./scripts/make-icon.sh` (source: `scripts/make-icon.swift`).

## Calendars

Everything comes from macOS Calendar (EventKit) — no API keys or tokens in the app.

- Grant Calendar access on first launch.
- Google: Settings → **Connect Google…** (or **Connect** on the island) opens System Settings → Internet Accounts → sign in to Google with Calendars enabled.
- Calendars of Google (and other non‑iCloud CalDAV) accounts go to **Schedule**, the rest to **Events**; any calendar can be moved or hidden in Settings.
- The island refreshes every 5 minutes in the background (also on wake and on Calendar changes). How often macOS syncs Google is set in Calendar → Settings → Accounts.

## Weather

A small weather pill (city, temperature, condition icon) sits beside the notch; click it for a 7‑day forecast, move the cursor away to shrink it back. Data: [Open-Meteo](https://open-meteo.com) (no API key), refreshed hourly in the background. Location comes from Location Services, or set a city in Settings → Weather (stored in `UserDefaults`, coordinates are not persisted).

## Local config and secrets

Never commit configs or secrets. Preferences live in `UserDefaults`; anything sensitive goes to `~/Library/Application Support/DynamicIsland/` (directory `0700`, files `0600`) or the Keychain.

## Updates

Settings → Updates → **Check for Updates** compares the commit the app was built from with the tip of `main` on `origin`. If a newer commit is pushed, **Update & Restart** clones/fetches the repo into `~/Library/Application Support/DynamicIsland/source`, builds it, replaces the installed app and relaunches it. Your working copy is never touched. Installer log: `~/Library/Application Support/DynamicIsland/update.log`.

## Layout

- `Sources/DynamicIsland/IslandController.swift` — panel above the menu bar, mouse tracking, expand/collapse.
- `Sources/DynamicIsland/NotchShape.swift` — animatable notch silhouette.
- `Sources/DynamicIsland/DashboardView.swift` — expanded island: events, schedule, settings button.
- `Sources/DynamicIsland/CalendarStore.swift` — background refresh, split into Events / Schedule.
- `Sources/DynamicIsland/MacCalendarSource.swift` — EventKit.
- `Sources/DynamicIsland/WeatherStore.swift`, `WeatherView.swift` — Open-Meteo weather and the weather block.
- `Sources/DynamicIsland/UpdateManager.swift`, `scripts/self-update.sh` — git‑based updater.
- `Sources/DynamicIsland/SettingsView.swift` — settings window.
