//
//  Appearance.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 03/07/26.
//


import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {

    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system:
            return "System"

        case .light:
            return "Light"

        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil

        case .light:
            return .light

        case .dark:
            return .dark
        }
    }
}