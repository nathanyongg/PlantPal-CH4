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
        // Attached as a `.background`, not a ZStack sibling, so it
        // never affects `content`'s own layout — a List/Form nested
        // inside a ZStack alongside `.ignoresSafeArea()` layers miscomputes
        // its top content inset, which threw the large-title layout off.
        //
        // `.background()` only ever covers the size `content` actually
        // takes up — a hugging VStack (e.g. a centered status message
        // with no explicit `.frame(maxWidth: .infinity)`) leaves the
        // system's default white bleeding through on the sides. Forcing
        // `content` to claim all available space first guarantees the
        // background always reaches every edge, regardless of what the
        // content underneath naturally wants.
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundLayer)
    }

    private var backgroundLayer: some View {
        ZStack {
            AppTheme.Colors.background
        }
        .ignoresSafeArea()
    }

    private var backgroundOpacity: Double {
        colorScheme == .dark ? 0.12 : 0
    }
}
