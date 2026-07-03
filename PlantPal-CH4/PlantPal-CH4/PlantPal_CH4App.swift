//
//  PlantPal_CH4App.swift
//  PlantPal-CH4
//
//  Created by Nathan Yong on 30/06/26.
//

import SwiftData
import SwiftUI

@main
struct PlantPalApp: App {

    @AppStorage("appearance")
    private var appearance: Appearance = .system

    @AppStorage("textSize")
    private var textSize: TextSize = .system

    var body: some Scene {

        WindowGroup {
            RootTabView()
                .preferredColorScheme(appearance.colorScheme)
                .appTextSize(textSize)
                .modelContainer(for: PlantProfile.self)
        }
    }
}
