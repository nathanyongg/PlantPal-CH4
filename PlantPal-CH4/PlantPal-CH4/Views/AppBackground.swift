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
                .opacity(0.15)
                .ignoresSafeArea()

            content
        }
    }
}