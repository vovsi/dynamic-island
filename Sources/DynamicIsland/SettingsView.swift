import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private static var title: String { tr("Dynamic Island Settings", "Настройки Dynamic Island") }

    /// Re-titles the open window after the language changes.
    func languageDidChange() {
        window?.title = Self.title
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = Self.title
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            self.window = window
        }
        window?.title = Self.title
        CalendarStore.shared.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var calendars = CalendarStore.shared
    @ObservedObject private var weather = WeatherStore.shared
    @ObservedObject private var batteries = DeviceBatteryStore.shared

    @AppStorage(AppSettings.collapseOnMouseExitKey) private var collapseOnMouseExit = true
    @AppStorage(AppSettings.hapticFeedbackKey) private var hapticFeedback = true
    @AppStorage(AppSettings.autoCheckUpdatesKey) private var autoCheckUpdates = true
    @AppStorage(AppSettings.eventAlertLeadKey) private var eventAlertLead = 5
    @AppStorage(AppSettings.eventAlertTrailKey) private var eventAlertTrail = 5
    @AppStorage(AppSettings.eventAlertSoundKey) private var eventAlertSound = true
    @AppStorage(AppSettings.lowBatteryAlertKey) private var lowBatteryAlert = true
    @AppStorage(AppSettings.lowBatteryThresholdKey) private var lowBatteryThreshold = 20
    @AppStorage(AppSettings.phoneBatteryEnabledKey) private var phoneBatteryEnabled = false
    @AppStorage(AppSettings.phoneBatteryPathKey) private var phoneBatteryPath = ""
    @AppStorage(AppSettings.languageKey) private var language = AppLanguage.system.rawValue

    @StateObject private var state = SettingsState()

    var body: some View {
        Form {
            Section(tr("General", "Основные")) {
                Picker(tr("Language", "Язык"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle(tr("Launch at login", "Запускать при входе в систему"), isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                if let loginItemError = state.loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle(tr("Collapse when cursor leaves the island", "Сворачивать, когда курсор уходит с острова"), isOn: $collapseOnMouseExit)
                Toggle(tr("Haptic feedback", "Тактильный отклик"), isOn: $hapticFeedback)
            }

            calendarSections

            Section(tr("Event Alert", "Напоминание о событии")) {
                Stepper(tr("Show \(eventAlertLead) min before start", "Показывать за \(eventAlertLead) мин до начала"), value: $eventAlertLead, in: 0...60)
                Stepper(tr("Keep \(eventAlertTrail) min after start", "Держать \(eventAlertTrail) мин после начала"), value: $eventAlertTrail, in: 0...60)
                Toggle(tr("Play a short sound when the alert appears", "Короткий звук при появлении напоминания"), isOn: $eventAlertSound)
                Text(tr("The collapsed island shows a pulsing red dot beside the notch when a Schedule event is near. Hover the island and click × to dismiss it until the next event.", "Когда приближается событие из «Расписания», рядом с вырезом на свёрнутом острове мигает красная точка. Наведите курсор на остров и нажмите ×, чтобы скрыть её до следующего события."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            batterySection

            weatherSection

            Section(tr("Refresh", "Обновление")) {
                LabeledContent(tr("Last updated", "Обновлено")) {
                    if let lastRefresh = calendars.lastRefresh {
                        Text(lastRefresh, format: .dateTime.hour().minute().second())
                    } else {
                        Text("—")
                    }
                }
                HStack {
                    Text(tr("Calendars refresh every 5 minutes in the background.", "Календари обновляются в фоне каждые 5 минут."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("Refresh Now", "Обновить сейчас")) { calendars.refresh() }
                }
            }

            Section(tr("Updates", "Обновления приложения")) {
                LabeledContent(tr("Version", "Версия"), value: "\(updates.version) (\(updates.shortCommit))")
                LabeledContent(tr("Branch", "Ветка"), value: updates.branch)
                if let lastChecked = updates.lastChecked {
                    LabeledContent(tr("Last checked", "Последняя проверка")) {
                        Text(lastChecked, format: .relative(presentation: .named))
                    }
                }
                Toggle(tr("Check for updates automatically", "Проверять обновления автоматически"), isOn: $autoCheckUpdates)

                statusRow

                HStack {
                    Button(tr("Check for Updates", "Проверить обновления")) {
                        Task { await updates.check() }
                    }
                    .disabled(updates.isBusy)

                    Spacer()

                    Button(tr("Update & Restart", "Обновить и перезапустить")) {
                        Task { await updates.performUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!updates.isUpdateAvailable || updates.isBusy)
                }

                if !updates.log.isEmpty {
                    DisclosureGroup(tr("Build log", "Лог сборки"), isExpanded: $state.showLog) {
                        ScrollView {
                            Text(updates.log)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 140)
                    }
                }
            }

            Section {
                HStack {
                    Text(tr("Right-click the island for quick actions.", "Правый клик по острову — быстрые действия."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("Quit Dynamic Island", "Завершить Dynamic Island"), role: .destructive) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .id(language)
        .environment(\.locale, L10n.locale)
        .onChange(of: language) {
            SettingsWindowController.shared.languageDidChange()
            calendars.refresh()
            weather.refresh()
        }
        .frame(width: 520)
        .frame(minHeight: 600)
    }

    // MARK: - Devices

    @ViewBuilder
    private var batterySection: some View {
        Section(tr("Device Battery", "Заряд устройств")) {
            Toggle(tr("Warn about a low accessory battery", "Предупреждать о низком заряде аксессуара"), isOn: $lowBatteryAlert)
            Stepper(
                tr("Warn at \(lowBatteryThreshold)% and below", "Предупреждать при \(lowBatteryThreshold)% и ниже"),
                value: $lowBatteryThreshold,
                in: 5...50,
                step: 5
            )
            .disabled(!lowBatteryAlert)
            if batteries.devices.isEmpty {
                Text(tr("No connected accessory reports its battery level.", "Ни одно подключённое устройство не сообщает заряд."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(batteries.devices) { device in
                    LabeledContent(device.name) {
                        HStack(spacing: 6) {
                            Text("\(device.percent)%")
                                .monospacedDigit()
                                .foregroundStyle(device.needsCharging ? .red : .primary)
                            if device.isCharging {
                                Image(systemName: "bolt.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            Toggle(tr("Show the iPhone level from a Shortcuts file", "Показывать заряд iPhone из файла Ярлыка"), isOn: $phoneBatteryEnabled)
            if phoneBatteryEnabled {
                phoneFileRow
            }
            Text(tr("The expanded island shows every connected accessory as an icon inside its battery ring. A device that runs low raises a red dot beside the collapsed notch until it is put on a charger; hover the island and click × to hide it sooner.", "В раскрытом острове каждое подключённое устройство показано иконкой в кольце заряда. Когда заряд падает, рядом с вырезом свёрнутого острова горит красная точка — пока устройство не поставят на зарядку. Наведите курсор и нажмите ×, чтобы скрыть раньше."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// File a Shortcuts automation on the iPhone writes into iCloud Drive; macOS itself never
    /// exposes the phone's battery level.
    @ViewBuilder
    private var phoneFileRow: some View {
        LabeledContent(tr("File", "Файл")) {
            HStack(spacing: 8) {
                Text(URL(fileURLWithPath: currentPhonePath).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(currentPhonePath)
                Button(tr("Choose…", "Выбрать…"), action: choosePhoneFile)
                Button(tr("Create Folder", "Создать папку"), action: createPhoneFolder)
            }
        }
        phoneStatusRow
        Text(tr("On the iPhone: Shortcuts → Automation → \"Get Battery Level\" → \"Save File\" into iCloud Drive as the file above (overwrite on, \"Ask where to save\" off) — the file holds just the number. Hourly or on battery-level changes is enough; a level older than 6 hours is ignored.", "На iPhone: Ярлыки → Автоматизация → «Получить уровень заряда» → «Сохранить файл» в iCloud Drive под именем выше (перезапись включена, «Спрашивать, куда сохранить» выключено) — в файле лежит просто число. Достаточно раз в час или при изменении заряда; значение старше 6 часов не показывается."))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var phoneStatusRow: some View {
        switch batteries.phoneStatus {
        case .off:
            EmptyView()
        case .missing:
            Label(tr("File not found yet.", "Файл пока не найден."), systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unreadable:
            Label(tr("File found, but no level could be read from it.", "Файл найден, но заряд из него не прочитан."), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .stale(let date):
            Label {
                Text(tr("Last level is too old — ", "Последнее значение устарело — ")) + Text(date, format: .relative(presentation: .named))
            } icon: {
                Image(systemName: "clock.badge.exclamationmark")
            }
            .font(.caption)
            .foregroundStyle(.orange)
        case .ready(let date):
            Label {
                Text(tr("Updated ", "Обновлено ")) + Text(date, format: .relative(presentation: .named))
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.green)
        }
    }

    private var currentPhonePath: String {
        phoneBatteryPath.isEmpty ? AppSettings.defaultPhoneBatteryPath : phoneBatteryPath
    }

    /// Picking the file here also hands the app access to it.
    private func choosePhoneFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: currentPhonePath).deletingLastPathComponent()
        panel.message = tr("Choose the file the iPhone shortcut writes.", "Выберите файл, который пишет Ярлык на iPhone.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        phoneBatteryPath = url.path
        DeviceBatteryStore.shared.refresh()
    }

    /// Creates the iCloud Drive folder so the shortcut has somewhere to save to.
    private func createPhoneFolder() {
        let folder = URL(fileURLWithPath: currentPhonePath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: - Weather

    private var weatherSection: some View {
        Section(tr("Weather", "Погода")) {
            HStack {
                TextField(tr("City", "Город"), text: $state.weatherCity, prompt: Text(tr("Current location", "Текущее местоположение")))
                    .onSubmit { weather.setCity(state.weatherCity) }
                Button(tr("Save", "Сохранить")) { weather.setCity(state.weatherCity) }
                    .disabled(state.weatherCity.trimmingCharacters(in: .whitespaces) == AppSettings.weatherCity)
            }
            switch weather.status {
            case .needsLocation:
                HStack {
                    Text(tr("Location access is denied. Enter a city or allow access.", "Доступ к геопозиции запрещён. Укажите город или разрешите доступ."))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(tr("Open Privacy Settings", "Открыть настройки конфиденциальности")) { weather.openLocationPrivacySettings() }
                }
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            case .loading, .ready:
                EmptyView()
            }
            HStack {
                if let lastUpdate = weather.lastUpdate {
                    Text(tr("Updated \(Self.time(lastUpdate)) · refreshes hourly", "Обновлено в \(Self.time(lastUpdate)) · раз в час"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("Refresh", "Обновить")) { weather.refresh() }
            }
            Text(tr("Leave the city empty to use your current location. Weather data by Open-Meteo.com.", "Оставьте город пустым, чтобы использовать текущее местоположение. Данные о погоде — Open-Meteo.com."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Calendars

    @ViewBuilder
    private var calendarSections: some View {
        Section(tr("Calendars", "Календари")) {
            switch calendars.access {
            case .notDetermined:
                HStack {
                    Text(tr("Access to Calendar is required.", "Нужен доступ к Календарю."))
                    Spacer()
                    Button(tr("Allow Access", "Разрешить доступ")) { Task { await calendars.requestAccess() } }
                }
            case .denied:
                HStack {
                    Text(tr("Access to Calendar is denied.", "Доступ к Календарю запрещён."))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(tr("Open Privacy Settings", "Открыть настройки конфиденциальности")) { calendars.openPrivacySettings() }
                }
            case .ready:
                HStack {
                    Text(calendars.hasScheduleCalendars
                         ? tr("Google account connected.", "Аккаунт Google подключён.")
                         : tr("Google account is not connected.", "Аккаунт Google не подключён."))
                        .foregroundStyle(calendars.hasScheduleCalendars ? Color.secondary : Color.orange)
                    Spacer()
                    Button(calendars.hasScheduleCalendars ? tr("Add Account…", "Добавить аккаунт…") : tr("Connect Google…", "Подключить Google…")) {
                        calendars.openInternetAccounts()
                    }
                }
            }
            Text(tr("Google is connected through System Settings → Internet Accounts → Google (enable Calendars). How often macOS syncs it is set in Calendar → Settings → Accounts.", "Google подключается в Системных настройках → Учётные записи интернета → Google (включите «Календари»). Частота синхронизации задаётся в Календаре → Настройки → Учётные записи."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ForEach(accounts, id: \.id) { account in
            Section(account.title) {
                ForEach(calendars.calendars.filter { $0.accountID == account.id }) { option in
                    Picker(selection: Binding(
                        get: { option.block },
                        set: { calendars.setBlock($0, for: option.id) }
                    )) {
                        ForEach(CalendarBlock.allCases) { Text($0.title).tag($0) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(option.color).frame(width: 8, height: 8)
                            Text(option.title)
                        }
                    }
                }
            }
        }
    }

    /// One section per account; same-named accounts (e.g. two "Google") get a number.
    private var accounts: [(id: String, title: String)] {
        var seen = Set<String>()
        var titleCount: [String: Int] = [:]
        return calendars.calendars.compactMap { option in
            guard seen.insert(option.accountID).inserted else { return nil }
            let base = option.account.isEmpty ? tr("Other", "Другие") : option.account
            titleCount[base, default: 0] += 1
            let number = titleCount[base]!
            return (option.accountID, number == 1 ? base : "\(base) \(number)")
        }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L10n.locale))
    }

    @ViewBuilder
    private var statusRow: some View {
        switch updates.status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("Checking for updates…", "Проверка обновлений…"))
            }
        case .upToDate:
            Label(tr("You're up to date.", "Установлена последняя версия."), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available(let remote):
            Label(tr("Update available: \(remote.prefix(7))", "Доступно обновление: \(remote.prefix(7))"), systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .updating(let step):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(step)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

}

/// View-local state (the CLT toolchain has no SwiftUI macro plugin, so `@State` is unavailable).
@MainActor
private final class SettingsState: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginItemError: String?
    @Published var showLog = false
    @Published var weatherCity = AppSettings.weatherCity

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
