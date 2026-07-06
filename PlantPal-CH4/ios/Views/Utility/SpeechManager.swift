//
//  SpeechManager.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 04/07/26.
//

import AVFoundation
import SwiftUI
import UIKit

// ══════════════════════════════════════════════════════════════
// MARK: — SpeechManager
//
// Central place for spoken feedback. When VoiceOver is running
// we post an announcement so it doesn't talk over the screen
// reader; otherwise we speak through AVSpeechSynthesizer.
// Controlled by the "Spoken Announcements" toggle in Settings.
// ══════════════════════════════════════════════════════════════

@MainActor
final class SpeechManager {

    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "spokenAnnouncements") as? Bool ?? true
    }

    func speak(_ text: String) {
        guard isEnabled, !text.isEmpty else { return }

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }

        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(
            language: Locale.preferredLanguages.first ?? "en-US"
        )
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
