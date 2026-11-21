# Project rules

- Configs and personal data (OAuth client IDs/secrets, access/refresh tokens, API keys, account e-mails, calendar IDs) are never stored in the repository. Keep them locally: `UserDefaults` for non-sensitive preferences; files in `~/Library/Application Support/DynamicIsland/` (dir 0700, files 0600) or the Keychain for anything sensitive. Never hard-code them in sources, scripts or `Info.plist`.
- The toolchain is Command Line Tools (no Xcode, no SwiftUI macro plugin): no `@State`, `@Observable`, `#Preview` — use `ObservableObject` + `@Published`.
- Build: `swift build`; app bundle: `./scripts/build.sh`; install: `./scripts/install.sh`. One-time: `./scripts/create-signing-identity.sh` creates the stable signing identity so updates keep macOS permissions.
- UI is bilingual (English + Russian). Every user-facing string goes through `tr("English", "Русский")` from `Localization.swift` — never a bare literal. Dates/times are formatted with `L10n.locale`. System permission prompts from `Info.plist` are translated in `Support/ru.lproj/InfoPlist.strings`.
