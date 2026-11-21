import AppKit

/// Compares the commit the app was built from with the tip of the remote branch,
/// and rebuilds/reinstalls the app from source when a newer commit is pushed.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(remoteCommit: String)
        case updating(step: String)
        case failed(message: String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?
    @Published private(set) var log = ""

    let currentCommit: String
    let repoURL: String
    let branch: String
    let version: String

    private var autoCheckTimer: Timer?
    private static let autoCheckInterval: TimeInterval = 3 * 60 * 60

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        currentCommit = info["DIGitCommit"] as? String ?? "unknown"
        repoURL = info["DIRepoURL"] as? String ?? ""
        branch = info["DIBranch"] as? String ?? "main"
        version = info["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var shortCommit: String { String(currentCommit.prefix(7)) }

    var isUpdateAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    var isBusy: Bool {
        switch status {
        case .checking, .updating: return true
        default: return false
        }
    }

    /// Managed clone used for building updates, so the user's working copy is never touched.
    private var sourceDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DynamicIsland/source", isDirectory: true)
    }

    // MARK: - Checking

    func startAutoCheck() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            if AppSettings.autoCheckUpdates { await check() }
        }
        autoCheckTimer = Timer.scheduledTimer(withTimeInterval: Self.autoCheckInterval, repeats: true) { _ in
            Task { @MainActor in
                if AppSettings.autoCheckUpdates { await UpdateManager.shared.check() }
            }
        }
    }

    func check() async {
        guard !isBusy else { return }
        guard !repoURL.isEmpty else {
            status = .failed(message: tr("Repository URL is unknown. Build the app with scripts/build.sh.", "URL репозитория неизвестен. Соберите приложение через scripts/build.sh."))
            return
        }

        status = .checking
        do {
            let output = try await Shell.run("/usr/bin/git", ["ls-remote", repoURL, "refs/heads/\(branch)"])
            guard let remote = output.split(whereSeparator: \.isWhitespace).first.map(String.init),
                  remote.count == 40 else {
                throw Shell.Failure(status: 1, output: tr("Branch '\(branch)' not found on remote.", "Ветка «\(branch)» не найдена на remote."))
            }
            lastChecked = Date()
            status = remote == currentCommit ? .upToDate : .available(remoteCommit: remote)
        } catch {
            status = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Updating

    func performUpdate() async {
        guard !isBusy else { return }
        guard let script = Bundle.main.url(forResource: "self-update", withExtension: "sh") else {
            status = .failed(message: tr("Updater script is missing from the app bundle.", "В бандле приложения нет скрипта обновления."))
            return
        }

        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else {
            status = .failed(message: tr("Updates are available only for the bundled app.", "Обновления доступны только для собранного .app."))
            return
        }

        log = ""
        status = .updating(step: tr("Fetching latest sources…", "Загрузка исходников…"))

        do {
            let output = try await Shell.run(
                "/bin/bash",
                [script.path, "build", repoURL, branch, sourceDirectory.path]
            ) { chunk in
                Task { @MainActor in UpdateManager.shared.appendLog(chunk) }
            }

            guard let builtApp = output
                .split(separator: "\n")
                .last(where: { $0.hasPrefix("APP_PATH=") })?
                .dropFirst("APP_PATH=".count) else {
                throw Shell.Failure(status: 1, output: tr("Build finished without producing an app.", "Сборка завершилась, но .app не создан."))
            }

            status = .updating(step: tr("Installing and restarting…", "Установка и перезапуск…"))
            try installAndRelaunch(script: script.path, newApp: String(builtApp), target: appPath)
        } catch {
            status = .failed(message: error.localizedDescription)
        }
    }

    private func appendLog(_ chunk: String) {
        log += chunk
        if log.count > 20_000 { log = String(log.suffix(20_000)) }

        if chunk.contains("Cloning") || chunk.contains("Fetching") {
            status = .updating(step: tr("Fetching latest sources…", "Загрузка исходников…"))
        } else if chunk.contains("Compiling") || chunk.contains("Building") {
            status = .updating(step: tr("Building…", "Сборка…"))
        }
    }

    /// Spawns a detached installer that waits for this process to exit, swaps the bundle and relaunches it.
    private func installAndRelaunch(script: String, newApp: String, target: String) throws {
        let logPath = sourceDirectory.deletingLastPathComponent().appendingPathComponent("update.log").path
        let pid = ProcessInfo.processInfo.processIdentifier
        let command = "nohup /bin/bash \(quote(script)) install \(quote(newApp)) \(quote(target)) \(pid) "
            + ">> \(quote(logPath)) 2>&1 &"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.environment = Shell.environment
        try process.run()
        process.waitUntilExit()

        NSApp.terminate(nil)
    }

    private func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
