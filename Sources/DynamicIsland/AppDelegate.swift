import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandController: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()

        let controller = IslandController()
        controller.start()
        islandController = controller

        CalendarStore.shared.start()
        UpdateManager.shared.startAutoCheck()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
