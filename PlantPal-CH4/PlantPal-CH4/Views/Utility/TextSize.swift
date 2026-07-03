//
//  TextSize.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 03/07/26.
//


import SwiftUI

enum TextSize: String, CaseIterable, Identifiable {

    case small
    case medium
    case large

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }

    var scale: CGFloat {
        switch self {
        case .small:
            return 0.9

        case .medium:
            return 1.0

        case .large:
            return 1.2
        }
    }
}

struct ScaledFont: ViewModifier {

    @AppStorage("textSize")
    private var textSize: TextSize = .medium

    func body(content: Content) -> some View {
        content
            .scaleEffect(textSize.scale)
    }
}

extension View {

    func appTextScale() -> some View {
        modifier(ScaledFont())
    }
}

