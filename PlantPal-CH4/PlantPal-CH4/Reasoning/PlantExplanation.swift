import FoundationModels

// ══════════════════════════════════════════════════════════════
// MARK: — PlantExplanation
//
// This is the structured output schema for the Foundation Model.
// @Generable tells the model to produce JSON matching this shape.
// @Guide annotations are the per-field instructions the model
// reads when deciding what to generate — keep them short and
// specific, they directly shape output quality.
// ══════════════════════════════════════════════════════════════

@Generable
struct PlantExplanation {

    @Guide(description: "Which sensor reading is most responsible for the stress, in plain words. One short sentence, no jargon.")
    var cause: String

    @Guide(description: "The single most important action the user should take right now. One short sentence, imperative mood (e.g. 'Water your plant now').")
    var action: String

    @Guide(description: "Urgency level. Must be exactly one of: 'Now', 'Today', 'Monitor'.")
    var urgency: String

    @Guide(description: "A short, friendly notification title. Max 6 words. No emoji.")
    var notificationTitle: String
}

// ══════════════════════════════════════════════════════════════
// MARK: — Convenience helpers
// ══════════════════════════════════════════════════════════════

extension PlantExplanation {

    /// Combines cause + action into a single notification body
    var notificationBody: String {
        "\(cause) \(action)"
    }

    /// Maps urgency string to a UNNotificationSound
    var isCritical: Bool {
        urgency == "Now"
    }
}
