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

struct PlantSetupView3: View {

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
        ZStack {
            AppBackground {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        Button {
                            showingPhotoOptions = true
                        } label: {
                            photoSection
                        }
                        .confirmationDialog(
                            "Choose Photo",
                            isPresented: $showingPhotoOptions,
                            titleVisibility: .hidden
                        ) {
                            Button("Take Photo") {
                                showingCamera = true
                            }

                            PhotosPicker(
                                selection: $selectedPhoto,
                                matching: .images
                            ) {
                                Text("Choose from Library")
                            }

                            Button("Cancel", role: .cancel) { }
                        }

                        inputCard
                        
                        saveButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 104)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Plant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var photoSection: some View {
        ZStack(alignment: .bottomTrailing) {

            Group {
                if let image = plantImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 25)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            VStack(spacing: 12){
                                Image(systemName: "camera")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Add a photo")
                            }
                        }
                }
            }
            .frame(height: 420)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 28))

            Button("Retake") {
                showingPhotoOptions = true
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(18)
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView(image: $plantImage)
            }
        }
    }

    private var inputCard: some View {

        VStack(spacing: 0) {

            HStack {
                Text("Nickname")

                Spacer()

                TextField(
                    "My Little Bolu Ketan",
                    text: $nickname
                )
                .multilineTextAlignment(.trailing)
            }

            Divider()
                .padding(.vertical, 14)

            HStack {

                Text("Species")

                Spacer()

                TextField(
                    "Monstera deliciosa",
                    text: $plantName
                )
                .multilineTextAlignment(.trailing)
            }

        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 36)
                .fill(AppTheme.Colors.lavenderPanel)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
        )
    }

    private var saveButton: some View {

        Button {
            Task {
                await setupPlant()
            }
        } label: {

            Text("Save")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.83, green: 0.65, blue: 0.92),
                            Color(red: 0.76, green: 0.60, blue: 0.88),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
        }
        .padding(.horizontal, 55)
        .disabled(
            plantName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
        )
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
        profile.imageData = plantImage?.jpegData(compressionQuality: 0.85)

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
