import AppKit
import CoreLocation
import SwiftUI

/// Current weather and a 7-day forecast from Open-Meteo (no API key), refreshed hourly in the background.
/// Location comes from Location Services or from the city set in Settings (kept in UserDefaults only).
@MainActor
final class WeatherStore: NSObject, ObservableObject {
    static let shared = WeatherStore()
    static let refreshInterval: TimeInterval = 60 * 60
    /// Backoff after a failed refresh. An hour is a long time to show an empty pill because the network
    /// was not up yet at launch, or because the service blinked.
    private static let retryDelays: [TimeInterval] = [20, 60, 300]

    private static let locationPrivacyURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
    )!

    struct Current: Equatable {
        let temperature: Double
        let apparentTemperature: Double
        let code: Int
        let isDay: Bool
        let windSpeed: Double
        let humidity: Double
    }

    struct Day: Identifiable, Equatable {
        /// Midnight UTC of the forecast day (format with a UTC time zone).
        let date: Date
        let code: Int
        let min: Double
        let max: Double
        let precipitationChance: Int?

        var id: Date { date }
    }

    enum Status: Equatable {
        case loading
        case ready
        case needsLocation
        case failed(String)
    }

    @Published private(set) var status: Status = .loading
    @Published private(set) var city: String?
    @Published private(set) var current: Current?
    @Published private(set) var days: [Day] = []
    @Published private(set) var lastUpdate: Date?

    let usesMetric = Locale.current.measurementSystem != .us

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var retryTimer: Timer?
    /// How many backoff steps the current run of failures has used up.
    private var retryAttempt = 0
    /// Location the cached `city` name was resolved for.
    private var geocodedLocation: CLLocation?
    private var manualPlace: (query: String, name: String, latitude: Double, longitude: Double)?

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        let timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { _ in
            MainActor.assumeIsolated { WeatherStore.shared.refresh() }
        }
        timer.tolerance = 60
        self.timer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { WeatherStore.shared.refresh() }
        }

        refresh()
    }

    /// `resettingRetries` is false only for the backoff timer's own call, so a run of failures keeps
    /// walking down the delays instead of restarting at the shortest one.
    func refresh(resettingRetries: Bool = true) {
        if resettingRetries { clearRetries() }

        let manualCity = AppSettings.weatherCity
        if !manualCity.isEmpty {
            Task { await loadManualCity(manualCity) }
            return
        }
        manualPlace = nil

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .needsLocation
        default:
            locationManager.requestLocation()
        }
    }

    func setCity(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != AppSettings.weatherCity else { return }
        AppSettings.weatherCity = trimmed
        city = nil
        geocodedLocation = nil
        refresh()
    }

    func openLocationPrivacySettings() {
        NSWorkspace.shared.open(Self.locationPrivacyURL)
    }

    // MARK: - Failures

    /// Reports the failure and lines up another attempt; the backoff gives up after the last delay,
    /// leaving the hourly refresh to try again.
    private func fail(_ message: String) {
        status = .failed(message)

        guard retryTimer == nil, retryAttempt < Self.retryDelays.count else { return }
        let delay = Self.retryDelays[retryAttempt]
        retryAttempt += 1

        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                WeatherStore.shared.retryTimer = nil
                WeatherStore.shared.refresh(resettingRetries: false)
            }
        }
        timer.tolerance = delay / 4
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func clearRetries() {
        retryTimer?.invalidate()
        retryTimer = nil
        retryAttempt = 0
    }

    // MARK: - Loading

    private func load(location: CLLocation) async {
        if city == nil || geocodedLocation.map({ $0.distance(from: location) > 5_000 }) ?? true {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            city = placemark?.locality ?? placemark?.administrativeArea ?? placemark?.country
            geocodedLocation = location
        }
        await fetchForecast(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func loadManualCity(_ query: String) async {
        do {
            if manualPlace?.query != query {
                manualPlace = try await geocode(query)
            }
            guard let place = manualPlace else { return }
            city = place.name
            await fetchForecast(latitude: place.latitude, longitude: place.longitude)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func geocode(_ query: String) async throws -> (query: String, name: String, latitude: Double, longitude: Double) {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: L10n.languageCode),
            URLQueryItem(name: "format", value: "json"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        guard let result = try JSONDecoder().decode(GeocodingDTO.self, from: data).results?.first else {
            throw WeatherError(message: tr("City “\(query)” not found.", "Город «\(query)» не найден."))
        }
        return (query, result.name, result.latitude, result.longitude)
    }

    private func fetchForecast(latitude: Double, longitude: Double) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            // ~1 km precision is enough for weather.
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "temperature_unit", value: usesMetric ? "celsius" : "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: usesMetric ? "ms" : "mph"),
        ]

        do {
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                // Open-Meteo explains itself in the body; without that the message says nothing useful.
                let reason = (try? JSONDecoder().decode(APIErrorDTO.self, from: data))?.reason
                throw WeatherError(message: reason.map {
                    tr("Weather service: \($0) (\(code)).", "Сервис погоды: \($0) (\(code)).")
                } ?? tr("Weather service is unavailable (\(code)).", "Сервис погоды недоступен (\(code))."))
            }
            let dto = try JSONDecoder().decode(ForecastDTO.self, from: data)

            current = Current(
                temperature: dto.current.temperature,
                apparentTemperature: dto.current.apparentTemperature,
                code: dto.current.weatherCode,
                isDay: dto.current.isDay == 1,
                windSpeed: dto.current.windSpeed,
                humidity: dto.current.humidity
            )
            days = Self.days(from: dto.daily)
            lastUpdate = Date()
            status = .ready
            clearRetries()
        } catch {
            // Keep the last forecast; only report the error.
            fail(error.localizedDescription)
        }
    }

    private static func days(from daily: ForecastDTO.Daily) -> [Day] {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"

        return daily.time.indices.compactMap { index in
            guard let date = parser.date(from: daily.time[index]),
                  let code = daily.weatherCode[safe: index] ?? nil,
                  let min = daily.temperatureMin[safe: index] ?? nil,
                  let max = daily.temperatureMax[safe: index] ?? nil else { return nil }
            return Day(
                date: date,
                code: code,
                min: min,
                max: max,
                precipitationChance: daily.precipitationProbability?[safe: index] ?? nil
            )
        }
    }

    // MARK: - Location callbacks

    private func authorizationChanged() {
        guard AppSettings.weatherCity.isEmpty,
              locationManager.authorizationStatus != .notDetermined else { return }
        refresh()
    }

    private func locationFailed(_ message: String) {
        if let cached = locationManager.location {
            Task { await load(location: cached) }
        } else if current == nil {
            fail(message)
        }
    }
}

extension WeatherStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await self.load(location: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.locationFailed(message) }
    }
}

// MARK: - Conditions

enum WeatherCondition {
    /// SF Symbol for a WMO weather code.
    static func symbol(code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func title(code: Int) -> String {
        switch code {
        case 0: return tr("Clear", "Ясно")
        case 1: return tr("Mostly clear", "Преимущественно ясно")
        case 2: return tr("Partly cloudy", "Переменная облачность")
        case 3: return tr("Cloudy", "Пасмурно")
        case 45, 48: return tr("Fog", "Туман")
        case 51, 53, 55: return tr("Drizzle", "Морось")
        case 56, 57: return tr("Freezing drizzle", "Ледяная морось")
        case 61, 63: return tr("Rain", "Дождь")
        case 65: return tr("Heavy rain", "Сильный дождь")
        case 66, 67: return tr("Freezing rain", "Ледяной дождь")
        case 71, 73, 77: return tr("Snow", "Снег")
        case 75: return tr("Heavy snow", "Сильный снег")
        case 80, 81, 82: return tr("Showers", "Ливень")
        case 85, 86: return tr("Snow showers", "Снегопад")
        case 95: return tr("Thunderstorm", "Гроза")
        case 96, 99: return tr("Thunderstorm, hail", "Гроза с градом")
        default: return "—"
        }
    }
}

struct WeatherError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - DTOs

private struct ForecastDTO: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let apparentTemperature: Double
        let weatherCode: Int
        let isDay: Int
        let windSpeed: Double
        let humidity: Double

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case isDay = "is_day"
            case windSpeed = "wind_speed_10m"
            case humidity = "relative_humidity_2m"
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int?]
        let temperatureMax: [Double?]
        let temperatureMin: [Double?]
        let precipitationProbability: [Int?]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case precipitationProbability = "precipitation_probability_max"
        }
    }

    let current: Current
    let daily: Daily
}

private struct APIErrorDTO: Decodable {
    let reason: String
}

private struct GeocodingDTO: Decodable {
    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    let results: [Result]?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
