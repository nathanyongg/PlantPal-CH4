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
    private let baseURL =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    private let session = URLSession.shared

    func fetchThresholds(for plantName: String) async throws -> PlantThresholds
    {
        let prompt = buildPrompt(for: plantName)
        let raw = try await callGemini(prompt: prompt)
        return try parseThresholds(from: raw)
    }

    // MARK: — Prompt

    private func buildPrompt(for plantName: String) -> String {
        """
        You are a plant care expert. Return ONLY a valid JSON object — no markdown,
        no explanation, no extra text. Just the raw JSON.

        Return the ideal environmental conditions for \(plantName) as:
        {
          "minTemperatureC": <number in Celsius>,
          "maxTemperatureC": <number in Celsius>,
          "minHumidityPercent": <number as percentage 0-100>,
          "maxHumidityPercent": <number as percentage 0-100>,
          "minSoilMoisturePercent": <number as percentage 0-100>,
          "maxSoilMoisturePercent": <number as percentage 0-100>,
          "minLightLux": <number as light percentage 0-100>,
          "maxLightLux": <number as light percentage 0-100>
        }

        Treat light as the app's calibrated light level percentage, where
        0 is dark and 100 is very bright. If the plant is unknown, use
        average tropical houseplant values as a safe fallback.
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
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 512,
                "responseMimeType": "application/json",
                "thinkingConfig": [
                    "thinkingBudget": 0
                ],
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

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
                struct Content: Decodable {
                    struct Part: Decodable { let text: String }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let text = decoded.candidates.first?.content.parts.first?.text
        else {
            throw GeminiServiceError.emptyResponse
        }
        
        print(text)
        return text
    }

    private func parseThresholds(from raw: String) throws -> PlantThresholds {
        // Strip any accidental markdown fences Gemini might add despite instructions
        let cleaned =
            raw
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
        case .invalidURL: return "Invalid Gemini API URL."
        case .invalidResponse: return "Couldn't reach Gemini API."
        case .apiError(let c):
            return "Gemini API returned error \(c). Check your API key."
        case .emptyResponse: return "Gemini returned an empty response."
        case .parseError:
            return "Couldn't parse thresholds from Gemini response."
        }
    }
}
