import AppKit
import Foundation
import IOKit

/// Battery levels of the Bluetooth accessories paired with this Mac, refreshed in the background.
///
/// Two sources, merged by device name: the IORegistry (Magic Mouse / Keyboard / Trackpad report
/// `BatteryPercent` there) and `system_profiler SPBluetoothDataType` (AirPods report left/right/case there).
/// Neither needs any permission.
@MainActor
final class DeviceBatteryStore: ObservableObject {
    static let shared = DeviceBatteryStore()
    static let refreshInterval: TimeInterval = 60
    /// Icons the mini dashboard shows at most.
    static let maxShown = 4

    @Published private(set) var devices: [DeviceBattery] = []

    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    /// Last seen level per device; a level that went up means the device is on a charger.
    private var lastPercent: [String: Int] = [:]

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { _ in
            MainActor.assumeIsolated { DeviceBatteryStore.shared.refresh() }
        }
        timer.tolerance = 10
        self.timer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { DeviceBatteryStore.shared.refresh() }
        }

        refresh()
    }

    func refresh() {
        guard task == nil else { return }
        task = Task { [weak self] in
            let collected = await Self.collect()
            guard let self else { return }
            self.apply(collected)
            self.task = nil
        }
    }

    /// Keeps the charging flag the accessory itself does not report: AirPods only show a level,
    /// so a level that climbed since the last reading is treated as "on a charger".
    private func apply(_ collected: [Reading]) {
        devices = collected
            .map { reading in
                let climbed = (lastPercent[reading.id] ?? reading.percent) < reading.percent
                return DeviceBattery(
                    id: reading.id,
                    name: reading.name,
                    kind: reading.kind,
                    percent: reading.percent,
                    isCharging: reading.isCharging || climbed
                )
            }
            .sorted(by: DeviceBattery.order)
        lastPercent = Dictionary(collected.map { ($0.id, $0.percent) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Collecting

    /// One source's reading, before the charging flag is reconciled with the previous one.
    private struct Reading {
        let id: String
        let name: String
        let kind: DeviceBattery.Kind
        let percent: Int
        let isCharging: Bool
    }

    private static func collect() async -> [Reading] {
        var byID: [String: Reading] = [:]
        // The IORegistry reports a charging flag, so it wins over system_profiler for the same device.
        for reading in await bluetoothReadings() { byID[reading.id] = reading }
        for reading in hidReadings() { byID[reading.id] = reading }
        return Array(byID.values)
    }

    /// Magic accessories, read straight from the IORegistry.
    private nonisolated static func hidReadings() -> [Reading] {
        guard let matching = IOServiceMatching("AppleDeviceManagementHIDEventService") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var readings: [Reading] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any],
                  let percent = properties["BatteryPercent"] as? Int,
                  (0...100).contains(percent)
            else { continue }

            let name = (properties["Product"] as? String) ?? tr("Accessory", "Аксессуар")
            let category = (properties["Accessory Category"] as? String) ?? ""
            // Bit 0 of the status flags is set while the accessory charges.
            let flags = (properties["BatteryStatusFlags"] as? Int) ?? 0

            readings.append(Reading(
                id: identifier(name),
                name: name,
                kind: kind(category: category, name: name),
                percent: percent,
                isCharging: flags & 0x1 != 0
            ))
        }
        return readings
    }

    /// Connected Bluetooth devices that report a level, AirPods above all.
    private nonisolated static func bluetoothReadings() async -> [Reading] {
        guard let output = try? await Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]),
              let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var readings: [Reading] = []
        for controller in controllers {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let id = identifier(name)
                    let kind = kind(category: (info["device_minorType"] as? String) ?? "", name: name)

                    // Earbuds: the lower of the two sides is what matters.
                    let sides = ["device_batteryLevelLeft", "device_batteryLevelRight"].compactMap { percent(info[$0]) }
                    if let main = percent(info["device_batteryLevelMain"]) ?? percent(info["device_batteryLevel"]) ?? sides.min() {
                        readings.append(Reading(id: id, name: name, kind: kind, percent: main, isCharging: false))
                    }
                    if let caseLevel = percent(info["device_batteryLevelCase"]) {
                        readings.append(Reading(
                            id: id + "-case",
                            name: tr("\(name) case", "Кейс \(name)"),
                            kind: .headphonesCase,
                            percent: caseLevel,
                            isCharging: false
                        ))
                    }
                }
            }
        }
        return readings
    }

    // MARK: - Parsing

    /// "87 %" → 87.
    private nonisolated static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return value as? Int }
        let digits = text.prefix { $0.isNumber }
        guard let number = Int(digits), (0...100).contains(number) else { return nil }
        return number
    }

    /// The device name is the one key both sources agree on: BLE addresses are randomized and
    /// change on every reconnect, which would reset levels and dismissed warnings.
    private nonisolated static func identifier(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private nonisolated static func kind(category: String, name: String) -> DeviceBattery.Kind {
        let haystack = (category + " " + name).lowercased()
        if haystack.contains("trackpad") { return .trackpad }
        if haystack.contains("mouse") { return .mouse }
        if haystack.contains("keyboard") { return .keyboard }
        if haystack.contains("headphone") || haystack.contains("airpod") || haystack.contains("headset") || haystack.contains("buds") {
            return .headphones
        }
        return .other
    }
}
