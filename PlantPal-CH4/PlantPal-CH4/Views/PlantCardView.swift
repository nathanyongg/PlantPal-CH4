//
//  PlantCardView.swift
//  PlantPal-CH4
//
//  Created by Agustinus Juan Kurniawan on 03/07/26.
//

import SwiftUI

struct PlantCardView: View {

    let plant: PlantProfile

    var body: some View {

        VStack(spacing: 0) {

            imageSection
                .padding(.horizontal, 10)
                .padding(.top, 10)

            Text(plant.nickname)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.52, blue: 0.36))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, 16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
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
                    .fill(Color.green.opacity(0.15))
                    .overlay {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                    }
                    .aspectRatio(3/4, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
