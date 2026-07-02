//
//  AppBackground.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 02/07/26.
//


import SwiftUI

struct AppBackground<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color("Color")
                .ignoresSafeArea()

            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            content
        }
    }
}
