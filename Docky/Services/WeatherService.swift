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
    private var pendingRefreshTask: Task<Void, Never>?
    private var isAwaitingLocation = false
    private var authorizationRequestContinuation: CheckedContinuation<Bool, Never>?

    private override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
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

        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < 900,
           snapshot != nil {
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
            if PermissionsService.shared.hasCompletedInitialOnboarding {
                snapshot = nil
                lastErrorDescription = "Enable location in Settings to show local weather."
            } else {
                isAwaitingLocation = true
                locationManager.requestWhenInUseAuthorization()
            }
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
                let snapshot = try await self.fetchSnapshot(for: location)
                guard !Task.isCancelled else { return }
                self.snapshot = snapshot
                self.lastRefreshDate = Date()
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

    private func fetchSnapshot(for location: CLLocation) async throws -> WeatherSnapshot {
        let coordinate = location.coordinate

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]

        guard let url = components?.url else {
            throw WeatherError.invalidRequest
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let current = response.current
        let locationName = await reverseGeocodeLocationName(for: location)

        return WeatherSnapshot(
            locationName: locationName,
            temperature: current.temperature2m,
            highTemperature: response.daily.temperature2mMax.first,
            lowTemperature: response.daily.temperature2mMin.first,
            symbolName: WeatherCondition.symbolName(for: current.weatherCode, isDaylight: current.isDay == 1),
            conditionDescription: WeatherCondition.description(for: current.weatherCode)
        )
    }

    private func reverseGeocodeLocationName(for location: CLLocation) async -> String {
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

        let latitude = String(format: "%.2f", location.coordinate.latitude)
        let longitude = String(format: "%.2f", location.coordinate.longitude)
        return "\(latitude), \(longitude)"
    }
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

private enum WeatherError: Error {
    case invalidRequest
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
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]

        private enum CodingKeys: String, CodingKey {
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
        }
    }
}
