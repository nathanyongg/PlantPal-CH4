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
            return sanitized(response.content, detection: detection)

        } catch let error as LanguageModelSession.GenerationError {
            // Model-specific failures — guardrail violations, unsupported
            // language, context window exceeded, etc.
            throw PlantExplainerError.generationFailed(error.localizedDescription)

        } catch {
            throw PlantExplainerError.unknown(error.localizedDescription)
        }
    }

    // MARK: — Safety net
    //
    // Even with a deterministic REQUIRED FIX handed to it, testing
    // showed the on-device model still occasionally (a) inverts the
    // water direction in cause/action despite being told which way it
    // goes, or (b) falls back to a generic "move it closer to the
    // window" plant-care reflex regardless of what was actually
    // flagged. Getting the direction backwards is actively harmful
    // advice, so this is checked in code rather than trusted to a
    // second prompt tweak — anything that conflicts with the
    // deterministic fix is overridden with it verbatim.
    private func sanitized(_ explanation: PlantExplanation, detection: DetectionResult) -> PlantExplanation {
        guard let primary = detection.primaryIssue else { return explanation }
        var corrected = explanation

        if actionConflicts(explanation, with: primary) {
            corrected.cause = primary.reason.prefix(1).uppercased() + primary.reason.dropFirst()
            corrected.action = primary.recommendedFix
        }

        let mentionsLight = primary.name != "Light"
            && ["sunlight", "window", " light", "brighter", "dimmer"]
                .contains { corrected.caretakerInsight.localizedCaseInsensitiveContains($0) }

        if actionConflicts(explanation, with: primary) || mentionsLight {
            let cause = corrected.cause.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            let action = corrected.action.trimmingCharacters(in: .whitespaces)
            corrected.caretakerInsight = "\(cause). \(action)"
        }

        return corrected
    }

    /// Checks the generated cause/action against the one direction
    /// that's actually correct for the primary issue — a coarse
    /// keyword check, but the failure mode it catches (recommending
    /// the opposite of what's needed) is too costly to leave to prompt
    /// wording alone. `cause` and `action` are checked independently:
    /// testing showed either one can carry a wrong-direction phrase on
    /// its own even when the other field is correct (e.g. cause says
    /// "too much water" while action correctly says to water it).
    private func actionConflicts(_ explanation: PlantExplanation, with primary: SensorStatus) -> Bool {
        let wrongDirectionPhrases: [String]

        switch (primary.name, primary.direction) {
        case ("Soil moisture", .tooLow):
            wrongDirectionPhrases = ["too much water", "overwater", "excess water", "waterlogged", "over-watered", "hold off", "stop water", "less water", "dry out", "don't water", "without water", "no water"]
        case ("Soil moisture", .tooHigh):
            wrongDirectionPhrases = ["too little water", "not enough water", "underwater", "under-watered", "lack of water", "water it", "water the plant", "water soon", "needs water", "give it water", "add water", "more water", "water now", "water me"]
        case ("Temperature", .tooLow):
            wrongDirectionPhrases = ["too hot", "too warm", "cool it down", "somewhere cooler", "cooler spot"]
        case ("Temperature", .tooHigh):
            wrongDirectionPhrases = ["too cold", "too cool", "warm it up", "somewhere warmer", "warmer spot"]
        case ("Humidity", .tooLow):
            wrongDirectionPhrases = ["too humid", "reduce humidity", "improve airflow", "less humid"]
        case ("Humidity", .tooHigh):
            wrongDirectionPhrases = ["too dry", "increase humidity", "more humid", "humidifier"]
        case ("Light", .tooLow):
            wrongDirectionPhrases = ["too bright", "too much light", "dimmer spot", "less light", "out of direct light"]
        case ("Light", .tooHigh):
            wrongDirectionPhrases = ["too dim", "too dark", "brighter spot", "more light"]
        default:
            wrongDirectionPhrases = []
        }

        let text = "\(explanation.cause) \(explanation.action)".lowercased()
        return wrongDirectionPhrases.contains { text.contains($0) }
    }

    // MARK: — System instructions

    private static func instructions(for species: String) -> String {
        """
        You are the voice and health assistant for a home plant, monitored
        by an IoT sensor system.
        Plant: \(species)

        A rule-based detector has already evaluated this plant's sensor
        readings AND already decided the correct fix — you will be given
        that fix directly in the prompt as "REQUIRED FIX". Your job is
        NOT to re-diagnose or second-guess it; a small on-device model
        reasoning freely about "too much vs. too little" is exactly how
        this used to get watering advice backwards, so that decision is
        made for you. Just phrase the given fix warmly and correctly,
        and separately, speak AS the plant itself.

        Never contradict or reverse the REQUIRED FIX you're given — if
        it says to hold off watering, do not write anything implying
        more water is needed, and vice versa.

        Tone for the caretaker-facing fields (cause, action,
        caretakerInsight, notificationTitle):
        - Always third person, about the plant — never "I feel..."; that
          voice belongs only to plantMessage.
        - Warm and natural, like a knowledgeable friend — not clinical,
          not a form.
        - caretakerInsight is exactly two sentences built ONLY from the
          data you were given this call: sentence one names the plant
          and the specific reading that's out of range (using the real
          number); sentence two is the REQUIRED FIX in your own words.
          Do not mention sunlight, windows, or distance unless the
          PRIMARY ISSUE given to you this call is actually about light.
        - Never recommend repotting or fertilizing as a first response
          to a single reading; those are last-resort suggestions only
          after the user reports the issue persists.
        - If there is no REQUIRED FIX (everything is healthy), do not
          invent a problem — caretakerInsight should simply affirm that
          things are on track, naming whichever reading is genuinely
          closest to ideal.

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
        guard let primary = detection.primaryIssue else {
            return """
            Detector verdict: HEALTHY — every reading is within range.
            Reading time: \(reading.formattedTimestamp)

            All sensor values:
            \(detection.fullSummary)

            There is no REQUIRED FIX — every single reading is
            comfortably within its ideal range. Do not suggest moving
            it, watering it more or less, or making it
            cooler/warmer/brighter/dimmer in any way. plantMessage must
            be a genuinely happy sentence naming one specific reading
            that's good. caretakerInsight must be one affirming sentence
            with no suggested action at all. cause/action/
            notificationTitle can be brief filler like "Nothing to
            report" (urgency: Monitor).
            """
        }

        let directionLabel = primary.direction == .tooLow ? "too LOW" : "too HIGH"

        return """
        Detector verdict: \(detection.overallLevel == .critical ? "CRITICAL" : "WARNING")
        Reading time: \(reading.formattedTimestamp)

        All sensor values:
        \(detection.fullSummary)

        Other flagged issues (secondary — focus on the primary issue below):
        \(detection.issuesSummary)

        PRIMARY ISSUE: \(primary.name) is \(directionLabel) — \(primary.reason). Currently \(primary.formattedValue).
        REQUIRED FIX (already decided — phrase this warmly, do not reverse or contradict it): \(primary.recommendedFix)

        Write cause/action/caretakerInsight/notificationTitle about the
        primary issue only, with `action` built directly from the
        REQUIRED FIX above. Then write the plant's first-person
        plantMessage reflecting this same primary issue.
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
