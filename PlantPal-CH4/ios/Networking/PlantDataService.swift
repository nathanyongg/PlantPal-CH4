import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — PlantDataService
//
// Fetches readings from the ESP32 after BLE Wi-Fi provisioning.
// The phone discovers the ESP32's local HTTP base URL during pairing,
// stores it on PlantProfile, then calls /latest whenever it needs a
// reading. The iPhone and ESP32 must be on the same local network.
// ══════════════════════════════════════════════════════════════

@MainActor
final class PlantDataService {

    private let session: URLSession
    private let baseURL: URL
    private let apiKey: String?

    init(
        baseURL: URL,
        apiKey: String? = nil,
        timeout: TimeInterval = 6
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: — Fetch latest reading

    func fetchLatestReading() async throws -> SensorReading {
        var request = URLRequest(url: baseURL.appendingPathComponent("latest"))
        request.httpMethod = "GET"
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw PlantDataServiceError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            let reading = try SensorReading(wireData: data)
            guard reading.isValid else {
                throw PlantDataServiceError.invalidReading
            }
            return reading
        case 404:
            throw PlantDataServiceError.noReadingsYet
        case 401, 403:
            throw PlantDataServiceError.unauthorized
        default:
            throw PlantDataServiceError.serverError(http.statusCode)
        }
    }

    // MARK: — Fetch history (for trend chart)

    func fetchHistory(hours: Int = 24) async throws -> [SensorReading] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("history"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "hours", value: "\(hours)")]

        var request = URLRequest(url: components.url!)
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PlantDataServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct WireReading: Decodable {
            let timestamp: Date
            let t: Double, h: Double, m: Double, l: Double
        }
        let wireReadings = try decoder.decode([WireReading].self, from: data)

        return wireReadings.compactMap {
            let reading = SensorReading(
                timestamp: $0.timestamp,
                temperature: $0.t,
                humidity: $0.h,
                soilMoisture: $0.m,
                lightIntensity: $0.l
            )
            return reading.isValid ? reading : nil
        }
    }
}

extension PlantDataService {

    convenience init(profile: PlantProfile, timeout: TimeInterval = 6) throws {
        guard
            let rawURL = profile.sensorBaseURL,
            let url = URL(string: rawURL)
        else {
            throw PlantDataServiceError.sensorNotConfigured
        }

        self.init(baseURL: url, timeout: timeout)
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — Errors
// ══════════════════════════════════════════════════════════════

enum PlantDataServiceError: LocalizedError {
    case sensorNotConfigured
    case invalidResponse
    case invalidReading
    case noReadingsYet
    case unauthorized
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .sensorNotConfigured:
            return "This plant doesn't have a provisioned Wi-Fi sensor yet."
        case .invalidResponse:
            return "Couldn't reach the plant sensor service."
        case .invalidReading:
            return "The sensor sent an incomplete reading. Check the DHT11 wiring and wait for the next live update."
        case .noReadingsYet:
            return "Your ESP32 hasn't sent any readings yet. Check it's powered on and connected to WiFi."
        case .unauthorized:
            return "API key rejected — check your configuration."
        case .serverError(let code):
            return "Server returned an error (\(code))."
        }
    }
}
