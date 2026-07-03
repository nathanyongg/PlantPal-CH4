////
////  PlantExplainer.swift
////  PlantPal-CH4
////
////  Created by Nathan Yong on 03/07/26.
////
//import Foundation
//import FoundationModels
//
//// ══════════════════════════════════════════════════════════════
//// MARK: — PlantExplanation
////
//// Structured output from the on-device model. @Generable lets
//// LanguageModelSession fill this in directly — no manual JSON
//// parsing, no risk of malformed text.
//// ══════════════════════════════════════════════════════════════
//
//@Generable
//struct PlantExplanation2: Codable, Sendable {
//
//    @Guide(description: "A short notification title, under 6 words, no emoji, no quotation marks")
//    var notificationTitle: String
//
//    @Guide(description: "A first-person message written as if the plant itself is speaking — warm, a little playful, under 25 words")
//    var notificationBody: String
//
//    @Guide(description: "A plain-language explanation of the most likely cause of the flagged reading(s), 1-2 sentences, no jargon")
//    var cause: String
//
//    @Guide(description: "One specific, actionable step the owner should take right now, 1-2 sentences")
//    var action: String
//
//    @Guide(.anyOf(["low", "medium", "high"]))
//    var urgency: String
//}
//
//// ══════════════════════════════════════════════════════════════
//// MARK: — PlantExplainer
////
//// Wraps Apple's on-device Foundation Model (SystemLanguageModel).
//// Given a SensorReading + the detector's verdict, produces
//// friendly, specific feedback grounded only in the actual numbers
//// — the model is instructed not to invent details it wasn't given.
//// ══════════════════════════════════════════════════════════════
//
//@available(iOS 26.0, macOS 26.0, *)
//final class PlantExplainer2 {
//
//    // MARK: — Availability
//
//    /// Whether the on-device model is ready to use right now.
//    static func isAvailable() -> Bool {
//        if case .available = SystemLanguageModel.default.availability {
//            return true
//        }
//        return false
//    }
//
//    /// A user-facing reason when the model isn't available, or nil if it is.
//    static func unavailableReason() -> String? {
//        switch SystemLanguageModel.default.availability {
//        case .available:
//            return nil
//        case .unavailable(.deviceNotEligible):
//            return "This device doesn't support Apple Intelligence."
//        case .unavailable(.appleIntelligenceNotEnabled):
//            return "Turn on Apple Intelligence in Settings to get care insights for your plant."
//        case .unavailable(.modelNotReady):
//            return "The on-device model is still downloading — try again shortly."
//        case .unavailable:
//            return "Apple Intelligence isn't available right now."
//        }
//    }
//
//    // MARK: — Explain
//
//    /// Runs the flagged reading(s) through the on-device model and returns
//    /// structured, plant-voiced feedback. Throws if the model is unavailable
//    /// or generation fails (e.g. guardrail rejection, context issues).
//    func explain(reading: SensorReading, detection: DetectionResult) async throws -> PlantExplanation2 {
//        let session = LanguageModelSession(instructions: Self.instructions)
//        let prompt = Self.prompt(reading: reading, detection: detection)
//
//        let response = try await session.respond(
//            to: prompt,
//            generating: PlantExplanation.self
//        )
//
//        return response.content
//    }
//
//    // MARK: — Prompt construction
//
//    private static var instructions: String {
//        """
//        You are the voice of a houseplant that just had its vitals checked by a \
//        smart sensor. The person reading your response is caring for you, so be \
//        warm, concise, and specific — never alarmist, never overly clinical.
//
//        Base every statement only on the sensor readings and flagged issues you're \
//        given below. Do not invent details about the plant's species, location, \
//        history, or anything else that wasn't provided. If several readings are \
//        flagged, focus on the single most important one rather than listing all of them.
//        """
//    }
//
//    private static func prompt(reading: SensorReading, detection: DetectionResult) -> String {
//        let flagged = detection.statuses.filter { $0.level != .healthy }
//
//        var lines = [
//            "Current sensor readings:",
//            "- Temperature: \(formatted(reading.temperature, decimals: 1))°C",
//            "- Humidity: \(formatted(reading.humidity, decimals: 0))%",
//            "- Soil moisture: \(formatted(reading.soilMoisture, decimals: 0))%",
//            "- Light intensity: \(formatted(reading.lightIntensity, decimals: 0)) lux",
//            "",
//            "Overall status: \(String(describing: detection.overallLevel))",
//            "Flagged readings:"
//        ]
//
//        if flagged.isEmpty {
//            lines.append("- none")
//        } else {
//            for status in flagged {
//                lines.append("- \(status.name): \(status.formattedValue) — \(String(describing: status.level))")
//            }
//        }
//
//        lines.append("")
//        lines.append("Write the notification content describing what's wrong and what to do about it.")
//
//        return lines.joined(separator: "\n")
//    }
//
//    private static func formatted(_ value: Double, decimals: Int) -> String {
//        String(format: "%.\(decimals)f", value)
//    }
//}
