//
//  PlantSetupView.swift
//  PlantPal-CH4
//
//  Created by Nathan Yong on 30/06/26.
//

import PhotosUI
import SwiftData
import SwiftUI

// ══════════════════════════════════════════════════════════════
// MARK: — PlantSetupView
//
// Shown when user adds a new plant. Takes a name, hits Gemini
// to get species-specific thresholds, persists a PlantProfile.
// This is the only moment Gemini is ever called — everything
// after this runs offline against the saved thresholds.
// ══════════════════════════════════════════════════════════════

struct PlantSetupView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var plantName = ""
    @State private var nickname = ""
    @State private var isLoading = false
    @State private var phase = SetupPhase.idle
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var plantImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPhotoOptions = false
    @State private var errorMessage: String?

    enum SetupPhase {
        case idle
        case fetchingThresholds  // calling Gemini
        case saving  // writing to SwiftData
        case done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Color")
                    .ignoresSafeArea()

                Image("Background")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.18)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 30) {

                        photoSection

                        inputCard

                        saveButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Plant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: — Phase label

    private var phaseLabel: String {
        switch phase {
        case .idle: return ""
        case .fetchingThresholds:
            return "Looking up care requirements for \(plantName)…"
        case .saving: return "Saving plant profile…"
        case .done: return "Plant added successfully!"
        }
    }

    // MARK: — Setup flow

    private func setupPlant() async {
        let trimmedName = plantName.trimmingCharacters(in: .whitespaces)
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespaces)
        let displayNickname =
            trimmedNickname.isEmpty ? trimmedName : trimmedNickname

        isLoading = true
        errorMessage = nil

        // Step 1 — call Gemini for species-specific thresholds
        phase = .fetchingThresholds
        let thresholds: PlantThresholds
        do {
            thresholds = try await GeminiService.shared.fetchThresholds(
                for: trimmedName
            )
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            phase = .idle
            return
        }

        // Step 2 — persist to SwiftData
        phase = .saving
        let profile = PlantProfile(
            name: trimmedName,
            nickname: displayNickname,
            thresholds: thresholds
        )
        modelContext.insert(profile)

        do {
            try modelContext.save()
        } catch {
            errorMessage =
                "Couldn't save plant profile: \(error.localizedDescription)"
            isLoading = false
            phase = .idle
            return
        }

        // Step 3 — done
        phase = .done
        isLoading = false

        try? await Task.sleep(for: .seconds(0.8))
        dismiss()
    }
}

#Preview {
    PlantSetupView()
        .modelContainer(for: PlantProfile.self, inMemory: true)
}
