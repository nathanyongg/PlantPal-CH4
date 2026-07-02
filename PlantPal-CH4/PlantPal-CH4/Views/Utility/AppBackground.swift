//
//  AppBackground.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 02/07/26.
//


import SwiftUI

struct AppBackground<Content: View>: View {

    @Environment(\.colorScheme)
    private var colorScheme

    @ViewBuilder
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color("Color")
                .ignoresSafeArea()

            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .opacity(backgroundOpacity)

            content
        }
    }

    private var backgroundOpacity: Double {
        colorScheme == .dark ? 0.06 : 0.9
    }
}
