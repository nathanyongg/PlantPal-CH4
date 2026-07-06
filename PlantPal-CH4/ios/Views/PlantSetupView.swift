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

    /// When set, the view edits this existing profile instead of
    /// creating a new one — prefilled from its current values.
    var editingProfile: PlantProfile? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var plantName: String
    @State private var nickname: String
    @State private var isLoading = false
    @State private var phase = SetupPhase.idle
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var plantImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPhotoOptions = false
    @State private var showingPhotoPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    init(editingProfile: PlantProfile? = nil) {
        self.editingProfile = editingProfile
        _plantName = State(initialValue: editingProfile?.name ?? "")
        _nickname = State(initialValue: editingProfile?.nickname ?? "")
        if let data = editingProfile?.imageData, let image = UIImage(data: data) {
            _plantImage = State(initialValue: image)
        }
    }

    enum SetupPhase {
        case idle
        case fetchingThresholds  // calling Gemini
        case saving  // writing to SwiftData
        case done
    }

    var body: some View {
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
        .background(AppBackground { Color.clear })
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
        .confirmationDialog(
            "Delete Plant?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deletePlant()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(editingProfile?.nickname ?? "this plant") and its check-in history. This can't be undone.")
        }
    }

    /// `leafGreen`'s dark variant is nearly the same shade as the form
    /// card's own background, so the labels disappear in dark mode —
    /// swap to a brighter green there. Light mode is untouched.
    private var formLabelColor: Color {
        colorScheme == .dark ? AppTheme.Colors.success : AppTheme.Colors.leafGreen
    }

    // MARK: — Delete

    private func deletePlant() {
        guard let editingProfile else { return }
        modelContext.delete(editingProfile)
        try? modelContext.save()
        dismiss()
    }

    // MARK: — Top bar

    private var topBar: some View {
        ZStack {
            Text(editingProfile == nil ? "Add Plant" : "Edit Plant")
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
                        .background(AppTheme.Colors.surface, in: Circle())
                        .overlay {
                            Circle().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                if editingProfile != nil {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.critical)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.Colors.surface, in: Circle())
                            .overlay {
                                Circle().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete Plant")
                    .accessibilityHint("Removes this plant and its check-in history")
                }
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
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
        }
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
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(AppTheme.Colors.surface, in: Capsule())
            .overlay {
                Capsule().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
            }
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
                .fill(AppTheme.Colors.leafGreen)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 4)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
        }
    }

    private var inputCard: some View {

        VStack(spacing: 0) {

            HStack {
                Text("Nickname")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(formLabelColor)

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
                    .foregroundStyle(formLabelColor)

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
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
        }
    }

    private var isSaveDisabled: Bool {
        plantName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
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

                Text(isLoading ? "Saving…" : (editingProfile == nil ? "Save" : "Save Changes"))
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
        .background(AppTheme.Colors.secondaryAccent, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.Colors.outline(for: colorScheme), lineWidth: 1.5)
        }
        .opacity(isSaveDisabled ? 0.5 : 1)
        .disabled(isSaveDisabled)
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
        case .done: return editingProfile == nil ? "Plant added successfully!" : "Changes saved!"
        }
    }

    // MARK: — Setup flow

    private func setupPlant() async {
        if let editingProfile {
            await saveEdits(to: editingProfile)
        } else {
            await createPlant()
        }
    }

    private func createPlant() async {
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

    // Editing only renames/re-photographs by default — thresholds stay
    // put unless the species text actually changed, so this never
    // re-hits Gemini for a plant that's already set up correctly.
    private func saveEdits(to profile: PlantProfile) async {
        let trimmedName = plantName.trimmingCharacters(in: .whitespaces)
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespaces)
        let displayNickname =
            trimmedNickname.isEmpty ? trimmedName : trimmedNickname

        isLoading = true
        errorMessage = nil

        if trimmedName != profile.name {
            phase = .fetchingThresholds
            do {
                let thresholds = try await GeminiService.shared.fetchThresholds(for: trimmedName)
                profile.minTemperatureC = thresholds.minTemperatureC
                profile.maxTemperatureC = thresholds.maxTemperatureC
                profile.minHumidityPercent = thresholds.minHumidityPercent
                profile.maxHumidityPercent = thresholds.maxHumidityPercent
                profile.minSoilMoisturePercent = thresholds.minSoilMoisturePercent
                profile.maxSoilMoisturePercent = thresholds.maxSoilMoisturePercent
                profile.minLightLux = thresholds.minLightLux
                profile.maxLightLux = thresholds.maxLightLux
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                phase = .idle
                SpeechManager.shared.speak(
                    "Could not update plant. \(error.localizedDescription)"
                )
                return
            }
        }

        phase = .saving
        profile.name = trimmedName
        profile.nickname = displayNickname
        if let plantImage {
            profile.imageData = plantImage.jpegData(compressionQuality: 0.85)
        }

        try? modelContext.save()

        phase = .done
        isLoading = false
        SpeechManager.shared.speak("\(displayNickname) updated")

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
