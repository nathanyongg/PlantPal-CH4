import Foundation
import FoundationModels

// ══════════════════════════════════════════════════════════════
// MARK: — PlantExplainer
//
// Wraps a LanguageModelSession. Called only when the detector
// (rule-based today, CoreML later) flags a reading as warning
// or critical — never on every 15-minute tick.
//
// Responsibilities:
//   1. Hold the system prompt / grounding context
//   2. Build the per-call prompt from sensor + detection data
//   3. Call the model and return a typed PlantExplanation
//   4. Handle the cases where Apple Intelligence isn't available
// ══════════════════════════════════════════════════════════════

@MainActor
final class PlantExplainer {

    private let session: LanguageModelSession
    
    private let plantSpecies: String = ""
    

    // Pass in the plant's profile once at init — species and
    // healthy ranges live here so you don't repeat them every call.
    init(plantSpecies: String = "Monstera deliciosa") {
        self.session = LanguageModelSession(
            instructions: """
            You are a plant health assistant for a home IoT sensor system.
            Plant: \(plantSpecies)

            A rule-based detector has already identified that this plant's
            readings fall outside healthy ranges. Your job is NOT to
            re-diagnose from scratch — it's to explain the detector's
            finding in plain, friendly language and give one clear,
            actionable next step.

            Rules:
            - Be direct. No greetings, no preamble, no filler.
            - Reference the actual numbers when relevant (e.g. "18% moisture").
            - One action only — the single most important thing to do first.
            - Never recommend repotting or fertilizing as a first response
              to a single reading; those are last-resort suggestions only
              after the user reports the issue persists.
            """
        )
    }

    // MARK: — Main entry point

    func explain(
        reading: SensorReading,
        detection: DetectionResult
    ) async throws -> PlantExplanation {

        let prompt = buildPrompt(reading: reading, detection: detection)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: PlantExplanation.self
            )
            return response.content

        } catch let error as LanguageModelSession.GenerationError {
            // Model-specific failures — guardrail violations, unsupported
            // language, context window exceeded, etc.
            throw PlantExplainerError.generationFailed(error.localizedDescription)

        } catch {
            throw PlantExplainerError.unknown(error.localizedDescription)
        }
    }

    // MARK: — Prompt construction

    private func buildPrompt(reading: SensorReading, detection: DetectionResult) -> String {
        """
        Detector verdict: \(detection.overallLevel == .critical ? "CRITICAL" : "WARNING")
        Reading time: \(reading.formattedTimestamp)

        All sensor values:
        \(detection.fullSummary)

        Flagged issues:
        \(detection.issuesSummary)

        Explain the most important issue and tell the user what to do.
        """
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — Errors
// ══════════════════════════════════════════════════════════════

enum PlantExplainerError: LocalizedError {
    case modelUnavailable
    case generationFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Apple Intelligence isn't available on this device or is still downloading."
        case .generationFailed(let reason):
            return "The plant assistant couldn't generate a response: \(reason)"
        case .unknown(let reason):
            return "Unexpected error: \(reason)"
        }
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — Availability check
//
// Call this before relying on the FM — e.g. on app launch or
// before scheduling the background task. If unavailable, fall
// back to the rule-based summary text (no FM call at all).
// ══════════════════════════════════════════════════════════════

extension PlantExplainer {

    static func isAvailable() -> Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        case .unavailable:
            return false
        @unknown default:
            return false
        }
    }

    /// Human-readable reason when unavailable — useful for a
    /// settings screen or onboarding message.
    static func unavailableReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to get plant health explanations."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading. This can take a few minutes."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }
}
