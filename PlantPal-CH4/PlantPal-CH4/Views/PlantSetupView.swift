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
    @State private var showingPhotoPicker = false
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
                        photoSection
                            .confirmationDialog(
                                "Choose Photo",
                                isPresented: $showingPhotoOptions
                            ) {
                                Button("Take Photo") {
                                    showingCamera = true
                                }

                                Button("Choose from Library") {
                                    showingPhotoPicker = true
                                }

                                Button("Cancel", role: .cancel) {}
                            }

                            .confirmationDialog(
                                "Choose Photo",
                                isPresented: $showingPhotoOptions
                            ) {
                                Button("Take Photo") {
                                    showingCamera = true
                                }

                                Button("Choose from Library") {
                                    showingPhotoPicker = true
                                }

                                Button("Cancel", role: .cancel) {}
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
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhoto,
                matching: .images
            )
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView(image: $plantImage)
                    .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    guard
                        let data = try? await newItem.loadTransferable(
                            type: Data.self
                        ),
                        let image = UIImage(data: data)
                    else { return }
                    plantImage = image
                    selectedPhoto = nil
                }
            }
        }
    }

    private var photoSection: some View {
        ZStack {
            if let image = plantImage {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .frame(height: 450)
            } else {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "camera")
                                .font(.largeTitle)
                            Text("Add a photo")
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 450)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture {
            showingPhotoOptions = true
        }
        .overlay(alignment: .bottomTrailing) {
            Button(plantImage == nil ? "Add Photo" : "Retake") {
                showingPhotoOptions = true
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(18)
        }
    }

    private var inputCard: some View {

        VStack(spacing: 0) {

            HStack {
                Text("Nickname")

                Spacer()

                TextField(
                    "My Mochi",
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
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(AppTheme.Colors.lavenderPanel)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 4)
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

        print("Inserting profile...")
        modelContext.insert(profile)

        do {
            print("Saving context...")
            try modelContext.save()
            print("Context saved!")
        } catch {
            print("SAVE FAILED:", error)
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
