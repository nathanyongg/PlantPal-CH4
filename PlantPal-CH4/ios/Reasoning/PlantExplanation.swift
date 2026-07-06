import FoundationModels

// ══════════════════════════════════════════════════════════════
// MARK: — PlantExplanation
//
// This is the structured output schema for the Foundation Model.
// @Generable tells the model to produce JSON matching this shape.
// @Guide annotations are the per-field instructions the model
// reads when deciding what to generate — keep them short and
// specific, they directly shape output quality.
//
// Two distinct voices come out of one call: `caretakerInsight` is
// the human-facing explanation, `plantMessage` is the plant
// speaking for itself — the whole point being a connection with
// something that can't move or talk.
// ══════════════════════════════════════════════════════════════

@Generable
struct PlantExplanation {

    @Guide(description: "Which sensor reading is most responsible, in one short plain-language phrase. Must match the real direction of the problem — e.g. 'too much water in the soil', not just 'water' — never assume the fix just because moisture was involved.")
    var cause: String

    @Guide(description: "The single most important next step for the caretaker, one short natural sentence. Must match the direction of the actual problem: if soil is waterlogged or overwatered, never say to water it — say to hold off watering, improve drainage, or move it somewhere it can dry out; if soil is too dry, say to water it.")
    var action: String

    @Guide(description: "A warm, natural explanation for the plant's caretaker, 1-2 complete flowing sentences — not a clinical fragment. Written like a knowledgeable friend, e.g. 'Monstera has been receiving less sunlight than usual this week. Try moving them 30cm closer to the window.' Reference real numbers when it helps ground the advice.")
    var caretakerInsight: String

    @Guide(description: "Urgency level. Must be exactly one of: 'Now', 'Today', 'Monitor'.")
    var urgency: String

    @Guide(description: "A short, friendly notification title. Max 6 words. No emoji.")
    var notificationTitle: String

    @Guide(description: "A first-person message from the plant itself, as if a curious young child were speaking — simple words, present tense, warm and a little playful, one short sentence, at most one emoji if it fits naturally. Ground it in what's actually happening (thirsty, too hot, loving the sun) without ever mentioning sensors, percentages, thresholds, or any technical term — the plant doesn't know it has sensors.")
    var plantMessage: String
}

// ══════════════════════════════════════════════════════════════
// MARK: — Convenience helpers
// ══════════════════════════════════════════════════════════════

extension PlantExplanation {

    /// The warm, flowing explanation — used as the notification body too.
    var notificationBody: String {
        caretakerInsight
    }

    /// Maps urgency string to a UNNotificationSound
    var isCritical: Bool {
        urgency == "Now"
    }
}
