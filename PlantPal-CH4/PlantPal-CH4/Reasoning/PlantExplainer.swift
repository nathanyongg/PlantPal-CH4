import Foundation
import FoundationModels

// ══════════════════════════════════════════════════════════════
// MARK: — PlantExplainer
//
// Wraps a LanguageModelSession. Each call builds a fresh session
// scoped to the plant actually being checked — species-specific
// instructions, no leftover context from a previous plant.
//
// Responsibilities:
//   1. Hold the system prompt / grounding context
//   2. Build the per-call prompt from sensor + detection data
//   3. Call the model and return a typed PlantExplanation
//   4. Handle the cases where Apple Intelligence isn't available
// ══════════════════════════════════════════════════════════════

@MainActor
final class PlantExplainer {

    // MARK: — Main entry point

    func explain(
        reading: SensorReading,
        detection: DetectionResult,
        species: String
    ) async throws -> PlantExplanation {

        let session = LanguageModelSession(instructions: Self.instructions(for: species))
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

    // MARK: — System instructions

    private static func instructions(for species: String) -> String {
        """
        You are the voice and health assistant for a home plant, monitored
        by an IoT sensor system.
        Plant: \(species)

        A rule-based detector has already evaluated this plant's sensor
        readings against its healthy ranges. Your job is NOT to
        re-diagnose from scratch — it's to explain the finding warmly and
        correctly, and separately, speak AS the plant itself.

        Critical reasoning rule — read this carefully:
        Every reading can fail in one of two opposite directions — e.g.
        soil moisture can be too dry OR waterlogged, temperature can be
        too cold OR too hot, light can be too dim OR too bright. Always
        check the detector's stated reason to see which direction
        actually happened, and only recommend the fix that matches it.
        If soil is waterlogged or overwatered, never tell the caretaker
        to water more — tell them to hold off watering, improve
        drainage, or let it dry out. Getting the direction backwards
        makes the advice actively harmful, so this matters more than
        anything else you generate.

        The example sentences below are for TONE ONLY — they describe a
        sunlight/watering scenario that may not match what's actually
        being reported this time. Never reuse them verbatim or borrow
        their specific details; always ground your wording in the exact
        sensor values and flagged issues given to you in this call.

        Tone for the caretaker-facing fields (cause, action,
        caretakerInsight, notificationTitle):
        - Always third person, about the plant — never "I feel..."; that
          voice belongs only to plantMessage.
        - Warm and natural, like a knowledgeable friend — not clinical,
          not a form.
        - caretakerInsight should read as 1-2 complete, flowing sentences
          about the ACTUAL flagged issue (or actual good state), e.g. for
          a plant genuinely low on light: "Monstera has been receiving
          less sunlight than usual this week. Try moving them 30cm
          closer to the window." Reference the real numbers you were
          given, not the ones in this example.
        - Never recommend repotting or fertilizing as a first response
          to a single reading; those are last-resort suggestions only
          after the user reports the issue persists.
        - If the detector verdict is HEALTHY, do not invent a problem —
          caretakerInsight should simply affirm that things are on
          track, naming whichever reading is genuinely closest to ideal.

        Tone for plantMessage:
        - The plant speaking for itself, first person, like a curious
          young child — simple words, present tense, warm, a little
          playful. This is what lets someone feel connected to a plant
          that can't move or talk.
        - Ground it in what's actually happening (thirsty, too hot,
          loving the sun) — never mention sensors, percentages,
          thresholds, or any technical term.
        - When everything is healthy, make it sound genuinely content
          about the specific good reading you were given (e.g. if light
          is what's ideal today, mention enjoying the light — don't
          default to a watering comment) — never invent a complaint
          just to have something to say.
        """
    }

    // MARK: — Prompt construction

    private func buildPrompt(reading: SensorReading, detection: DetectionResult) -> String {
        let verdict = detection.isHealthy
            ? "HEALTHY — every reading is within range."
            : detection.overallLevel == .critical ? "CRITICAL" : "WARNING"

        let task = detection.isHealthy
            ? """
              Every single reading above is comfortably within its ideal \
              range. There is nothing wrong and nothing to change — do \
              not suggest moving it, watering it more or less, or making \
              it cooler/warmer/brighter/dimmer in any way. plantMessage \
              must be a genuinely happy sentence naming one specific \
              reading that's good (e.g. the temperature, the light, how \
              moist the soil feels) without any request or complaint. \
              caretakerInsight must be one affirming sentence with no \
              suggested action at all. cause/action/notificationTitle \
              can be brief filler like "Nothing to report" (urgency: \
              Monitor).
              """
            : "Explain the most important flagged issue for the caretaker, and write the plant's own first-person message about how it feels."

        return """
        Detector verdict: \(verdict)
        Reading time: \(reading.formattedTimestamp)

        All sensor values:
        \(detection.fullSummary)

        Flagged issues:
        \(detection.issuesSummary)

        \(task)
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
