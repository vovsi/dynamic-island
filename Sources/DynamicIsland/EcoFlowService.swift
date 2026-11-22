import Foundation

/// What the last EcoFlow poll ended with, for the Settings window.
enum EcoFlowStatus: Equatable {
    case off
    /// The access key, the secret key or the serial number is still missing.
    case needsCredentials
    case failed(String)
    case ready(Date)
}

/// Keeps the last reading of the power station so the accessory poll (every minute) does not hit the
/// EcoFlow cloud that often: the station is refetched every five minutes, or at once after its
/// settings change.
actor EcoFlowService {
    static let shared = EcoFlowService()

    static let refreshInterval: TimeInterval = 5 * 60

    /// Everything one poll needs; a change to any of it invalidates the cached reading.
    struct Config: Equatable {
        let region: EcoFlowClient.Region
        let accessKey: String
        let secretKey: String
        let serial: String
        let name: String
    }

    private var reading: EcoFlowClient.Reading?
    private var status: EcoFlowStatus = .off
    private var fetched: Date?
    private var config: Config?

    /// Cached reading, refetched when it ages out, the settings change or `invalidate()` was called.
    func current() async -> (reading: EcoFlowClient.Reading?, name: String, status: EcoFlowStatus) {
        guard AppSettings.ecoFlowEnabled else {
            reset()
            return (nil, "", .off)
        }
        guard let config = AppSettings.ecoFlowConfig else {
            reset()
            status = .needsCredentials
            return (nil, "", status)
        }

        if config != self.config {
            self.config = config
            reading = nil
            fetched = nil
        }
        if let fetched, Date().timeIntervalSince(fetched) < Self.refreshInterval {
            return (reading, config.name, status)
        }

        let client = EcoFlowClient(region: config.region, accessKey: config.accessKey, secretKey: config.secretKey)
        do {
            reading = try await client.reading(serial: config.serial)
            status = .ready(Date())
        } catch {
            reading = nil
            status = .failed(error.localizedDescription)
        }
        fetched = Date()
        return (reading, config.name, status)
    }

    /// Drops the cached reading so the next poll goes to the cloud again.
    func invalidate() {
        fetched = nil
    }

    private func reset() {
        reading = nil
        fetched = nil
        config = nil
        status = .off
    }
}
