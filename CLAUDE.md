# Project rules

- Configs and personal data (OAuth client IDs/secrets, access/refresh tokens, API keys, account e-mails, calendar IDs) are never stored in the repository. Keep them in `LocalConfigStore` (`~/Library/Application Support/DynamicIsland/config.json`, dir 0700, file 0600) or `UserDefaults` for non-sensitive preferences. Never hard-code them in sources, scripts or `Info.plist`.
- The toolchain is Command Line Tools (no Xcode, no SwiftUI macro plugin): no `@State`, `@Observable`, `#Preview` — use `ObservableObject` + `@Published`.
- Build: `swift build`; app bundle: `./scripts/build.sh`; install: `./scripts/install.sh`.
