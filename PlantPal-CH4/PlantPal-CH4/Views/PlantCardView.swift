//
//  PlantCardView.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 03/07/26.
//

import SwiftUI
import SwiftData

struct PlantCardView: View {

    let plant: PlantProfile

    var body: some View {

        VStack(spacing: 0) {

            imageSection
                .padding(.horizontal, 10)
                .padding(.top, 10)

            Text(plant.nickname)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.Colors.leafGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, 16)
        }
        .background(AppTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plant.nickname), \(plant.name), \(statusText)")
    }


    private var statusColor: Color {

        switch plant.alertLevel {

        case .healthy:
            return .green

        case .warning:
            return .orange

        case .critical:
            return .red
        }
    }

    private var statusText: String {

        switch plant.alertLevel {

        case .healthy:
            return "Healthy"

        case .warning:
            return "Needs Attention"

        case .critical:
            return "Critical"
        }
    }
}

extension PlantCardView {
    
    fileprivate var imageSection: some View {
        Group {
            if let imageData = plant.imageData,
               let uiImage = UIImage(data: imageData) {

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 160, maxHeight: 200)
                    .aspectRatio(3/4, contentMode: .fit)
                    .clipped()

            } else {

                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.Colors.success.opacity(0.15))
                    .overlay {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppTheme.Colors.success)
                    }
                    .aspectRatio(3/4, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    PlantSetupView()
        .modelContainer(for: PlantProfile.self, inMemory: true)
}
