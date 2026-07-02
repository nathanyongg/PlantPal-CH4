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

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .modelContainer(for: PlantProfile.self)
    }
}
