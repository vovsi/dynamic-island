# Project rules

- Configs and personal data (OAuth client IDs/secrets, access/refresh tokens, API keys, account e-mails, calendar IDs) are never stored in the repository. Keep them locally: `UserDefaults` for non-sensitive preferences; files in `~/Library/Application Support/DynamicIsland/` (dir 0700, files 0600) or the Keychain for anything sensitive. Never hard-code them in sources, scripts or `Info.plist`.
- The toolchain is Command Line Tools (no Xcode, no SwiftUI macro plugin): no `@State`, `@Observable`, `#Preview` — use `ObservableObject` + `@Published`.
- Build: `swift build`; app bundle: `./scripts/build.sh`; install: `./scripts/install.sh`.
