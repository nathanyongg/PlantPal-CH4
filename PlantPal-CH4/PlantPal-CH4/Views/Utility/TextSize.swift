//
//  TextSize.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 03/07/26.
//


import SwiftUI

enum TextSize: String, CaseIterable, Identifiable {

    case system
    case small
    case medium
    case large

    var id: Self { self }

    var title: String {
        switch self {
        case .system:
            return "System"

        case .small:
            return "Small"

        case .medium:
            return "Medium"

        case .large:
            return "Large"
        }
    }

    // Maps to Dynamic Type so text reflows properly instead of
    // being visually scaled. `nil` follows the device setting,
    // which is what VoiceOver / low-vision users rely on.
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system:
            return nil

        case .small:
            return .small

        case .medium:
            return .large

        case .large:
            return .xxxLarge
        }
    }
}

extension View {

    @ViewBuilder
    func appTextSize(_ size: TextSize) -> some View {
        if let dynamicTypeSize = size.dynamicTypeSize {
            self.dynamicTypeSize(dynamicTypeSize)
        } else {
            self
        }
    }
}
