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
        AppBackground {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    topBar

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

                    formPanel

                    statusSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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

    // MARK: — Top bar

    private var topBar: some View {
        ZStack {
            Text("Add Plant")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Back")

                Spacer()
            }
        }
        .padding(.top, 8)
    }

    // MARK: — Photo section

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
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 450)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture {
            showingPhotoOptions = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            plantImage == nil ? "Add a photo" : "Plant photo"
        )
        .accessibilityHint("Opens the camera or photo library")
        .accessibilityAddTraits(.isButton)
        .overlay(alignment: .bottomTrailing) {
            Button(plantImage == nil ? "Add Photo" : "Retake") {
                showingPhotoOptions = true
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .padding(18)
        }
    }

    // MARK: — Form panel (nickname + species + save)

    private var formPanel: some View {
        VStack(spacing: 20) {
            inputCard
            saveButton
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(AppTheme.Colors.lavenderPanel)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 4)
        )
    }

    private var inputCard: some View {

        VStack(spacing: 0) {

            HStack {
                Text("Nickname")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.leafGreen)

                Spacer()

                HStack(spacing: 4) {
                    TextField(
                        "My Mochi",
                        text: $nickname
                    )
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .accessibilityLabel("Nickname")

                    Image(systemName: "leaf.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.success)
                        .accessibilityHidden(true)
                }
            }

            Divider()
                .padding(.vertical, 14)

            HStack {

                Text("Species")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.leafGreen)

                Spacer()

                TextField(
                    "Monstera deliciosa",
                    text: $plantName
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .accessibilityLabel("Species")
            }

        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var saveButton: some View {

        Button {
            Task {
                await setupPlant()
            }
        } label: {

            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }

                Text(isLoading ? "Saving…" : "Save")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(AppTheme.Colors.secondaryAccent)
        .disabled(
            plantName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
        )
        .accessibilityLabel(isLoading ? "Saving plant" : "Save plant")
        .accessibilityHint("Looks up care requirements and adds the plant")
    }

    private var statusSection: some View {

        Group {
            if let errorMessage {
                Text(errorMessage)
                    .font(AppTheme.Typography.subtitle)
                    .foregroundStyle(AppTheme.Colors.critical)
                    .multilineTextAlignment(.center)
            } else if isLoading || phase == .done {
                Text(phaseLabel)
                    .font(AppTheme.Typography.subtitle)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
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
            SpeechManager.shared.speak(
                "Could not add plant. \(error.localizedDescription)"
            )
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
        SpeechManager.shared.speak("\(displayNickname) added successfully")

        try? await Task.sleep(for: .seconds(0.8))
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PlantSetupView()
    }
    .modelContainer(for: PlantProfile.self, inMemory: true)
}
