import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandController: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BundleRename.migrateIfNeeded()
        AppSettings.registerDefaults()

        let controller = IslandController()
        controller.start()
        islandController = controller

        CalendarStore.shared.start()
        WeatherStore.shared.start()
        KeepAwakeManager.shared.start()
        DeviceBatteryStore.shared.start()
        UpdateManager.shared.startAutoCheck()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
