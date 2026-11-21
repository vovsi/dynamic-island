import AppKit
import ServiceManagement

/// One-time migration: older builds were installed as `DynamicIsland.app` and the updater keeps the
/// existing bundle path, so rename the installed bundle to `Dynamic Island.app` on launch.
enum BundleRename {
    static let bundleFileName = "Dynamic Island.app"

    static func migrateIfNeeded() {
        let current = Bundle.main.bundleURL
        guard current.pathExtension == "app",
              current.lastPathComponent != bundleFileName,
              !current.path.contains("/build/") else { return }

        let target = current.deletingLastPathComponent().appendingPathComponent(bundleFileName)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: target.path) else { return }

        let loginItemEnabled = SMAppService.mainApp.status == .enabled
        do {
            try fm.moveItem(at: current, to: target)
        } catch {
            NSLog("Bundle rename failed: \(error.localizedDescription)")
            return
        }
        LSRegisterURL(target as CFURL, true)

        if loginItemEnabled {
            try? SMAppService.mainApp.unregister()
            try? SMAppService.mainApp.register()
        }
    }
}
