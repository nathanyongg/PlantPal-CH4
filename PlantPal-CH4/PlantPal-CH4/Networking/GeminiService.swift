import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — GeminiService
//
// Called once during plant setup to get species-specific
// thresholds. Returns a PlantThresholds struct that gets
// persisted into SwiftData via PlantProfile.
//
// Uses Gemini 2.0 Flash — fast, cheap, good for structured
// factual queries like "what are the ideal conditions for X".
// ══════════════════════════════════════════════════════════════

actor GeminiService {

    static let shared = GeminiService()

    private var apiKey: String { SecretsManager.geminiAPIKey }
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    func fetchThresholds(for plantName: String) async throws -> PlantThresholds {

        let prompt = buildPrompt(for: plantName)

        for attempt in 0..<3 {
            do {
                let raw = try await callGemini(prompt: prompt)
                return try parseThresholds(from: raw)

            } catch GeminiServiceError.apiError(let code)
                where code == 429 || code == 500 || code == 502 || code == 503 {

                if attempt == 2 {
                    throw GeminiServiceError.apiError(code)
                }

                try await Task.sleep(for: .seconds(2))

            } catch {
                throw error
            }
        }

        throw GeminiServiceError.invalidResponse
    }

    // MARK: — Prompt

    private func buildPrompt(for plantName: String) -> String {
        """
        Return the ideal care thresholds for \(plantName).

        Respond with ONLY this JSON object:

        {
          "minTemperature": 0,
          "maxTemperature": 0,
          "minHumidity": 0,
          "maxHumidity": 0,
          "minSoilMoisture": 0,
          "maxSoilMoisture": 0,
          "minLight": 0,
          "maxLight": 0
        }

        All values must be numbers.
        """
    }
    // MARK: — Gemini API call

    private func callGemini(prompt: String) async throws -> String {
        guard var urlComponents = URLComponents(string: baseURL) else {
            throw GeminiServiceError.invalidURL
        }
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = urlComponents.url else {
            throw GeminiServiceError.invalidURL
        }

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": prompt
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 512,
                "responseMimeType": "application/json",
                "thinkingConfig": [
                    "thinkingBudget": 0
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod  = "POST"
        request.httpBody    = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        print(String(data: data, encoding: .utf8)!)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponse
        }

        guard http.statusCode == 200 else {
            throw GeminiServiceError.apiError(http.statusCode)
        }

        return try extractText(from: data)
    }

    // MARK: — Response parsing

    private func extractText(from data: Data) throws -> String {
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                let finishReason: String?
                struct Content: Decodable {
                    struct Part: Decodable { let text: String }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }
        

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let text = decoded.candidates.first?.content.parts.first?.text else {
            throw GeminiServiceError.emptyResponse
        }
        
        #if DEBUG
        print(decoded.candidates.first?.finishReason ?? "none")
        print("Gemini text length:", text.count)
        print(text)
        #endif

        return text
    }

    private func parseThresholds(from raw: String) throws -> PlantThresholds {
        // Strip any accidental markdown fences Gemini might add despite instructions
        
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiServiceError.parseError
        }

        return try JSONDecoder().decode(PlantThresholds.self, from: data)
    }
}

// MARK: — Errors

enum GeminiServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(Int)
    case emptyResponse
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "Invalid Gemini API URL."
        case .invalidResponse:   return "Couldn't reach Gemini API."
        case .apiError(let c):   return "Gemini API returned error \(c). Check your API key."
        case .emptyResponse:     return "Gemini returned an empty response."
        case .parseError:        return "Couldn't parse thresholds from Gemini response."
        }
    }
}
