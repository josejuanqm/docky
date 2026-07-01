//
//  WeatherService.swift
//  Docky
//

import AppKit
import Combine
import CoreLocation
import Foundation
import MapKit

final class WeatherService: NSObject, ObservableObject {
    static let shared = WeatherService()
    static let widgetOwnerBundleIdentifier = WidgetOwnerBundleIdentifiers.weather

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorDescription: String?

    private let locationManager = CLLocationManager()
    private var lastRefreshDate: Date?
    private var lastWeatherUnits: WeatherUnits?
    private var pendingRefreshTask: Task<Void, Never>?
    private var isAwaitingLocation = false
    private var authorizationRequestContinuation: CheckedContinuation<Bool, Never>?

    private override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localeDidChange),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )
    }

    func ensureFreshWeather() {
        refresh(force: false)
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = locationManager.authorizationStatus
    }

    var hasLocationAuthorization: Bool {
        Self.isAuthorizedStatus(authorizationStatus)
    }

    /// Docky's tri-state view of location access, used by the widget to
    /// decide between real content and the call-to-action state.
    var permissionStatus: PermissionStatus {
        if Self.isAuthorizedStatus(authorizationStatus) {
            return .granted
        }
        switch authorizationStatus {
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    /// Requests location access in response to an explicit user action
    /// (the widget's Enable button). Fetches weather immediately on grant.
    func requestAccess() async -> Bool {
        let granted = await requestLocationPermission()
        if granted {
            refresh(force: true)
        }
        return granted
    }

    func requestLocationPermission() async -> Bool {
        refreshAuthorizationStatus()

        if Self.isAuthorizedStatus(authorizationStatus) {
            return true
        }

        switch authorizationStatus {
        case .authorizedAlways:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                authorizationRequestContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return false
        }
    }

    func refresh(force: Bool) {
        guard !isLoading else {
            return
        }

        let weatherUnits = WeatherUnits.current

        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < 900,
           snapshot != nil,
           lastWeatherUnits == weatherUnits {
            return
        }

        lastErrorDescription = nil

        if Self.isAuthorizedStatus(locationManager.authorizationStatus) {
            requestLocation()
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            requestLocation()
        case .notDetermined:
            // Location is requested lazily from the widget's Enable button,
            // never automatically on render. Leave the widget in its
            // call-to-action state until the user opts in.
            snapshot = nil
        case .denied, .restricted:
            snapshot = nil
            lastErrorDescription = "Location access is needed for local weather."
        @unknown default:
            snapshot = nil
            lastErrorDescription = "Weather is unavailable right now."
        }
    }

    func openInWeatherApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
            return
        }

        if let fallbackURL = URL(string: "https://weather.com") {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    private func requestLocation() {
        isLoading = true
        isAwaitingLocation = true
        locationManager.requestLocation()
    }

    private func updateWeather(for location: CLLocation) {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let units = WeatherUnits.current
                let snapshot = try await self.fetchSnapshot(for: location, units: units)
                guard !Task.isCancelled else { return }
                self.snapshot = snapshot
                self.lastRefreshDate = Date()
                self.lastWeatherUnits = units
                self.lastErrorDescription = nil
            } catch is CancellationError {
                return
            } catch {
                self.snapshot = nil
                self.lastErrorDescription = "Couldn’t load weather."
            }

            self.isLoading = false
        }
    }

    private func fetchSnapshot(for location: CLLocation, units: WeatherUnits) async throws -> WeatherSnapshot {
        let coordinate = location.coordinate

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"),
            URLQueryItem(name: "temperature_unit", value: units.temperatureQueryValue),
            URLQueryItem(name: "wind_speed_unit", value: units.windSpeedQueryValue),
            URLQueryItem(name: "precipitation_unit", value: units.precipitationQueryValue),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6")
        ]

        guard let url = components?.url else {
            throw WeatherError.invalidRequest
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let current = response.current
        let locationName = await reverseGeocodeLocationName(for: location)
        let forecast = Self.makeForecastDays(from: response.daily)

        return WeatherSnapshot(
            locationName: locationName,
            temperature: current.temperature2m,
            highTemperature: response.daily.temperature2mMax.first,
            lowTemperature: response.daily.temperature2mMin.first,
            symbolName: WeatherCondition.symbolName(for: current.weatherCode, isDaylight: current.isDay == 1),
            conditionDescription: WeatherCondition.description(for: current.weatherCode),
            forecast: forecast
        )
    }

    private static func makeForecastDays(from daily: OpenMeteoResponse.DailyWeather) -> [WeatherForecastDay] {
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.timeZone = .autoupdatingCurrent

        let count = min(daily.time.count, daily.temperature2mMax.count, daily.temperature2mMin.count, daily.weatherCode.count)
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())

        var days: [WeatherForecastDay] = []
        days.reserveCapacity(count)

        for index in 0..<count {
            guard let parsed = isoFormatter.date(from: daily.time[index]) else { continue }
            let normalized = calendar.startOfDay(for: parsed)
            guard normalized > today else { continue }
            days.append(
                WeatherForecastDay(
                    date: normalized,
                    symbolName: WeatherCondition.symbolName(for: daily.weatherCode[index], isDaylight: true),
                    highTemperature: daily.temperature2mMax[index],
                    lowTemperature: daily.temperature2mMin[index]
                )
            )
        }

        return days
    }

    @objc private func localeDidChange() {
        guard lastWeatherUnits != WeatherUnits.current else {
            return
        }

        lastRefreshDate = nil
        refresh(force: true)
    }

    private func reverseGeocodeLocationName(for location: CLLocation) async -> String {
        if FeatureGate.shared.isAvailable(.modernReverseGeocoding), #available(macOS 26.0, *) {
            if let request = MKReverseGeocodingRequest(location: location),
               let mapItem = try? await request.mapItems.first {
                if let name = mapItem.addressRepresentations?.cityName, !name.isEmpty {
                    return name
                }
                if let cityWithContext = mapItem.addressRepresentations?.cityWithContext, !cityWithContext.isEmpty {
                    return cityWithContext
                }
                if let shortAddress = mapItem.address?.shortAddress, !shortAddress.isEmpty {
                    return shortAddress
                }
            }
        } else if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            if let locality = placemark.locality, !locality.isEmpty {
                if let admin = placemark.administrativeArea, !admin.isEmpty, admin != locality {
                    return "\(locality), \(admin)"
                }
                return locality
            }
            if let admin = placemark.administrativeArea, !admin.isEmpty {
                return admin
            }
            if let name = placemark.name, !name.isEmpty {
                return name
            }
        }

        let latitude = String(format: "%.2f", location.coordinate.latitude)
        let longitude = String(format: "%.2f", location.coordinate.longitude)
        return "\(latitude), \(longitude)"
    }

    #if DEBUG
    func seedDummyDebugSnapshot() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let isUS = WeatherUnits.current == .us
        let dummyForecast: [WeatherForecastDay] = (1...5).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let symbols = ["sun.max.fill", "cloud.sun.fill", "cloud.fill", "cloud.rain.fill", "cloud.bolt.rain.fill"]
            let highs: [Double] = isUS ? [74, 71, 68, 65, 70] : [23, 21, 19, 17, 21]
            let lows: [Double] = isUS ? [58, 55, 52, 50, 56] : [14, 13, 11, 10, 13]
            return WeatherForecastDay(
                date: date,
                symbolName: symbols[offset - 1],
                highTemperature: highs[offset - 1],
                lowTemperature: lows[offset - 1]
            )
        }

        snapshot = WeatherSnapshot(
            locationName: "San Francisco",
            temperature: isUS ? 68 : 20,
            highTemperature: isUS ? 72 : 22,
            lowTemperature: isUS ? 58 : 14,
            symbolName: "sun.max.fill",
            conditionDescription: "Clear",
            forecast: dummyForecast
        )
        lastRefreshDate = Date()
        lastWeatherUnits = WeatherUnits.current
        isLoading = false
        isAwaitingLocation = false
        lastErrorDescription = nil
    }
    #endif
}

extension WeatherService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if let authorizationRequestContinuation,
           manager.authorizationStatus != .notDetermined {
            self.authorizationRequestContinuation = nil
            authorizationRequestContinuation.resume(returning: Self.isAuthorizedStatus(manager.authorizationStatus))
        }

        guard isAwaitingLocation else {
            return
        }

        if Self.isAuthorizedStatus(manager.authorizationStatus) {
            requestLocation()
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways:
            requestLocation()
        case .denied, .restricted:
            isAwaitingLocation = false
            isLoading = false
            snapshot = nil
            lastErrorDescription = "Location access is needed for local weather."
        case .notDetermined:
            break
        @unknown default:
            isAwaitingLocation = false
            isLoading = false
            snapshot = nil
            lastErrorDescription = "Weather is unavailable right now."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isAwaitingLocation = false
            isLoading = false
            lastErrorDescription = "Couldn’t determine your location."
            return
        }

        isAwaitingLocation = false
        updateWeather(for: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isAwaitingLocation = false
        isLoading = false

        if let clError = error as? CLError, clError.code == .denied {
            snapshot = nil
            lastErrorDescription = "Location access is needed for local weather."
            return
        }

        lastErrorDescription = "Couldn’t determine your location."
    }

    private static func isAuthorizedStatus(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
        switch status {
        case .authorizedAlways:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return true
        }
        #else
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return false
        }
        #endif
    }
}

struct WeatherSnapshot: Equatable {
    let locationName: String
    let temperature: Double
    let highTemperature: Double?
    let lowTemperature: Double?
    let symbolName: String
    let conditionDescription: String
    let forecast: [WeatherForecastDay]

    init(
        locationName: String,
        temperature: Double,
        highTemperature: Double?,
        lowTemperature: Double?,
        symbolName: String,
        conditionDescription: String,
        forecast: [WeatherForecastDay] = []
    ) {
        self.locationName = locationName
        self.temperature = temperature
        self.highTemperature = highTemperature
        self.lowTemperature = lowTemperature
        self.symbolName = symbolName
        self.conditionDescription = conditionDescription
        self.forecast = forecast
    }

    var roundedTemperatureText: String {
        "\(Int(temperature.rounded()))°"
    }

    var highLowText: String {
        let high = highTemperature.map { Int($0.rounded()) }
        let low = lowTemperature.map { Int($0.rounded()) }

        return switch (high, low) {
        case let (high?, low?):
            "H:\(high)° L:\(low)°"
        case let (high?, nil):
            "High \(high)°"
        case let (nil, low?):
            "Low \(low)°"
        case (nil, nil):
            ""
        }
    }
}

struct WeatherForecastDay: Equatable, Identifiable {
    let date: Date
    let symbolName: String
    let highTemperature: Double?
    let lowTemperature: Double?

    var id: TimeInterval { date.timeIntervalSinceReferenceDate }

    var weekdayShortText: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}

private enum WeatherError: Error {
    case invalidRequest
}

private enum WeatherUnits: Equatable {
    case metric
    case uk
    case us

    static var current: WeatherUnits {
        switch Locale.autoupdatingCurrent.measurementSystem {
        case .us:
            .us
        case .uk:
            .uk
        default:
            .metric
        }
    }

    var temperatureQueryValue: String {
        switch self {
        case .us:
            "fahrenheit"
        case .metric, .uk:
            "celsius"
        }
    }

    var windSpeedQueryValue: String {
        switch self {
        case .us, .uk:
            "mph"
        case .metric:
            "kmh"
        }
    }

    var precipitationQueryValue: String {
        switch self {
        case .us:
            "inch"
        case .metric, .uk:
            "mm"
        }
    }
}

private enum WeatherCondition {
    static func description(for code: Int) -> String {
        switch code {
        case 0:
            "Clear"
        case 1:
            "Mostly Clear"
        case 2:
            "Partly Cloudy"
        case 3:
            "Overcast"
        case 45, 48:
            "Fog"
        case 51, 53, 55, 56, 57:
            "Drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            "Rain"
        case 71, 73, 75, 77, 85, 86:
            "Snow"
        case 95, 96, 99:
            "Thunderstorm"
        default:
            "Weather"
        }
    }

    static func symbolName(for code: Int, isDaylight: Bool) -> String {
        switch code {
        case 0:
            isDaylight ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:
            isDaylight ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:
            "cloud.fill"
        case 45, 48:
            "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            "cloud.snow.fill"
        case 95, 96, 99:
            "cloud.bolt.rain.fill"
        default:
            "cloud.fill"
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather
    let daily: DailyWeather

    struct CurrentWeather: Decodable {
        let temperature2m: Double
        let weatherCode: Int
        let isDay: Int

        private enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    struct DailyWeather: Decodable {
        let time: [String]
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]
        let weatherCode: [Int]

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case weatherCode = "weather_code"
        }
    }
}
