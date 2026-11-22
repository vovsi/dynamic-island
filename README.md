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

## Device battery

Every Bluetooth accessory that reports a level is shown beside the weather pill as its icon inside a battery ring — green above the threshold, red at or below it, with a bolt while charging. Levels come from the IORegistry (Magic Mouse / Keyboard / Trackpad) and `system_profiler SPBluetoothDataType` (AirPods, and their case), refreshed every minute. No permissions needed.

When a device drops to the threshold (Settings → Device Battery, 20% by default) and is not charging, the collapsed island shows a pulsing red dot beside the notch with the device badge on the other side. It stays until the device is put on a charger; hover the island and click × to hide it until that device runs low again.

### iPhone

macOS exposes no iPhone battery level to third-party apps, so the phone has to send it. Settings → Device Battery → **Show the iPhone level from a Shortcuts file**, then:

1. **Create Folder** makes `~/Library/Mobile Documents/com~apple~CloudDocs/DynamicIsland/` (iCloud Drive → DynamicIsland).
2. On the iPhone: Shortcuts → **Automation** → e.g. *Battery Level* (changes) or *Time of Day* (hourly) → **Get Battery Level** → **Save File** into that folder as `battery.txt`, "Overwrite If File Exists" on and "Ask Where to Save" off. The file holds just the number.
3. Back in Settings, **Choose…** the file once (that also grants the app access to it).

`57`, `57 %` and `0.57` are all read the same way, and a JSON file like `{"percent": 57, "name": "iPhone 16", "charging": true, "date": "2026-11-22T13:44:00Z"}` is accepted as well. Levels older than 6 hours are ignored, and without a `charging` flag a level that went up counts as charging — the same rule AirPods get.

### EcoFlow power station

The charge of an EcoFlow station (DELTA 2 and the rest) is read from the EcoFlow IoT Open Platform, so it shows up beside the accessories as one more badge — with the time to full or the time left, and the watts going in or out, in the hover hint.

1. At [developer.ecoflow.com](https://developer.ecoflow.com) sign in with the account the station is registered to and create an **access key** / **secret key** pair.
2. Settings → EcoFlow → **Show the charge of an EcoFlow power station**, pick the region of that account (Europe or Global — a key from the other region is rejected with error 8513), paste both keys.
3. **Find** lists the stations on the account; pick one and **Save**.

The keys are kept in the Keychain, never in `UserDefaults` or in the repository. The station is polled every 5 minutes (`GET /iot-open/sign/device/quota/all`, signed with HMAC-SHA256); the level is `bms_emsStatus.lcdShowSoc`, with the BMS values as a fallback.

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
- `Sources/DynamicIsland/DeviceBatteryStore.swift`, `DeviceBattery.swift`, `DeviceBatteryView.swift` — accessory, iPhone and power-station battery levels, badges and the low-battery alert.
- `Sources/DynamicIsland/EcoFlowClient.swift`, `EcoFlowService.swift`, `EcoFlowSettingsView.swift`, `Keychain.swift` — signed EcoFlow cloud calls, the cached reading and its settings.
- `Sources/DynamicIsland/UpdateManager.swift`, `scripts/self-update.sh` — git‑based updater.
- `Sources/DynamicIsland/SettingsView.swift` — settings window.
