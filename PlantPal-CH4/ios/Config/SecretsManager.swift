//
//  SecretsManager.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 01/07/26.
//


import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — SecretsManager
//
// Reads API keys injected from Secrets.xcconfig via Info.plist.
// Keys never appear as string literals anywhere in source code.
//
// Setup checklist (do this once):
//   □ Secrets.xcconfig exists and is in .gitignore
//   □ Project → Info → Configurations → Debug = Secrets
//   □ Project → Info → Configurations → Release = Secrets
//   □ Info.plist has GEMINI_API_KEY = $(GEMINI_API_KEY)
// ══════════════════════════════════════════════════════════════

enum SecretsManager {

    static var geminiAPIKey: String {
        key(named: "GEMINI_API_KEY")
    }

    // Add more keys here as needed:
    // static var braveAPIKey: String { key(named: "BRAVE_API_KEY") }

    // MARK: — Private

    private static func key(named name: String) -> String {
        guard let value = Bundle.main.infoDictionary?[name] as? String,
              !value.isEmpty,
              value != "paste_your_key_here"
        else {
            // Crash loud in debug so you catch missing keys immediately.
            // In release this would be caught by your CI before shipping.
            assertionFailure("⚠️ \(name) is missing or not set in Secrets.xcconfig")
            return ""
        }
        return value
    }
}