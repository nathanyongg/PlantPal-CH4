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

    /// The device chosen in ConnectDeviceView before this screen ever
    /// appears — new plants always arrive with one already selected.
    var preselectedDeviceID: String? = nil
    var preselectedDeviceName: String? = nil
    var preselectedSensorBaseURL: String? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query private var allProfiles: [PlantProfile]

    @StateObject private var ble = ESP32BLEManager.shared

    @State private var plantName: String
    @State private var nickname: String
    @State private var linkedDeviceID: String?
    @State private var linkedDeviceName: String?
    @State private var sensorBaseURL: String?
    @State private var showingDevicePicker = false
    @State private var isLoading = false
    @State private var phase = SetupPhase.idle
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var plantImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPhotoOptions = false
    @State private var showingPhotoPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    init(
        editingProfile: PlantProfile? = nil,
        preselectedDeviceID: String? = nil,
        preselectedDeviceName: String? = nil,
        preselectedSensorBaseURL: String? = nil
    ) {
        self.editingProfile = editingProfile
        self.preselectedDeviceID = preselectedDeviceID
        self.preselectedDeviceName = preselectedDeviceName
        self.preselectedSensorBaseURL = preselectedSensorBaseURL
        _plantName = State(initialValue: editingProfile?.name ?? "")
        _nickname = State(initialValue: editingProfile?.nickname ?? "")
        _linkedDeviceID = State(
            initialValue: editingProfile?.linkedDeviceID ?? preselectedDeviceID
        )
        _linkedDeviceName = State(
            initialValue: editingProfile?.linkedDeviceName
                ?? preselectedDeviceName
        )
        _sensorBaseURL = State(
            initialValue: editingProfile?.sensorBaseURL
                ?? preselectedSensorBaseURL
        )
        if let data = editingProfile?.imageData, let image = UIImage(data: data)
        {
            _plantImage = State(initialValue: image)
        }
    }

    /// Devices already dedicated to a different plant — offering them
    /// here would let two plants fight over one sensor.
    private var deviceClaimedByAnotherPlant: Bool {
        guard let linkedDeviceID else { return false }
        return allProfiles.contains {
            $0.linkedDeviceID == linkedDeviceID
                && $0.persistentModelID != editingProfile?.persistentModelID
        }
    }

    private var availableDevices: [ESP32BLEManager.DiscoveredDevice] {
        let claimedElsewhere = Set(
            allProfiles
                .filter {
                    $0.persistentModelID != editingProfile?.persistentModelID
                }
                .compactMap(\.linkedDeviceID)
        )
        return ble.discoveredDevices.filter {
            !claimedElsewhere.contains($0.id.uuidString)
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

                deviceSection

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
            Text(
                "This removes \(editingProfile?.nickname ?? "this plant") and its check-in history. This can't be undone."
            )
        }
    }

    /// `leafGreen`'s dark variant is nearly the same shade as the form
    /// card's own background, so the labels disappear in dark mode —
    /// swap to a brighter green there. Light mode is untouched.
    private var formLabelColor: Color {
        colorScheme == .dark
            ? AppTheme.Colors.success : AppTheme.Colors.leafGreen
    }

    // MARK: — Delete

    private func deletePlant() {
        guard let editingProfile else { return }
        Task {
            try? await FirestoreService.shared.deletePlant(editingProfile)
        }
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
                IconCircleButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Back"
                ) {
                    dismiss()
                }

                Spacer()

                if editingProfile != nil {
                    IconCircleButton(
                        systemImage: "trash",
                        tint: AppTheme.Colors.critical,
                        accessibilityLabel: "Delete Plant",
                        accessibilityHint:
                            "Removes this plant and its check-in history"
                    ) {
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: — Device (each plant needs its own paired sensor)

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device")
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(formLabelColor)

            Button {
                showingDevicePicker.toggle()
                if showingDevicePicker {
                    ble.startScanning()
                } else {
                    ble.stopScanning()
                }
            } label: {
                HStack {
                    Image(systemName: "wifi")
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(linkedDeviceName ?? "No device selected")
                            .font(AppTheme.Typography.cardTitle)
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        if linkedDeviceID == nil {
                            Text("Tap to connect a sensor")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        } else if sensorBaseURL == nil {
                            Text("Finish Wi-Fi setup first")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.warning)
                        } else if deviceClaimedByAnotherPlant {
                            Text("Already linked to another plant")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.critical)
                        } else {
                            Text("Wi-Fi ready")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    Image(
                        systemName: showingDevicePicker
                            ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    AppTheme.Colors.surface,
                    in: RoundedRectangle(
                        cornerRadius: AppTheme.Radius.medium,
                        style: .continuous
                    )
                )
                .appOutline(
                    RoundedRectangle(
                        cornerRadius: AppTheme.Radius.medium,
                        style: .continuous
                    ),
                    colorScheme: colorScheme
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: AppTheme.Radius.medium,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Device")
            .accessibilityValue(linkedDeviceName ?? "No device selected")
            .accessibilityHint("Shows nearby devices to pair with this plant")

            if showingDevicePicker {
                devicePickerList
            }
        }
        .onDisappear { ble.stopScanning() }
    }

    private var devicePickerList: some View {
        VStack(spacing: 8) {
            if availableDevices.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking for nearby devices…")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.vertical, 10)
            } else {
                ForEach(availableDevices) { device in
                    Button {
                        linkedDeviceID = device.id.uuidString
                        linkedDeviceName = device.name
                        sensorBaseURL = nil
                        showingDevicePicker = false
                        ble.stopScanning()
                    } label: {
                        HStack {
                            Text(device.name)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Spacer()
                            if linkedDeviceID == device.id.uuidString {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.Colors.success)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            AppTheme.Colors.surface,
                            in: RoundedRectangle(
                                cornerRadius: AppTheme.Radius.small,
                                style: .continuous
                            )
                        )
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: AppTheme.Radius.small,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                RoundedRectangle(cornerRadius: AppTheme.Radius.large)
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
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .appOutline(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large),
            colorScheme: colorScheme
        )
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
            .appOutline(Capsule(), colorScheme: colorScheme)
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
            RoundedRectangle(
                cornerRadius: AppTheme.Radius.xlarge,
                style: .continuous
            )
            .fill(AppTheme.Colors.leafGreen)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 4)
        )
        .appOutline(
            RoundedRectangle(
                cornerRadius: AppTheme.Radius.xlarge,
                style: .continuous
            ),
            colorScheme: colorScheme
        )
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
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
        .appOutline(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card),
            colorScheme: colorScheme
        )
    }

    private var isSaveDisabled: Bool {
        plantName.trimmingCharacters(in: .whitespaces).isEmpty
            || isLoading
            || linkedDeviceID == nil
            || sensorBaseURL == nil
            || deviceClaimedByAnotherPlant
    }

    private var saveButton: some View {

        Button {
            Task {
                await setupPlant()
            }
        } label: {
            if isLoading {
                ProgressView()
                    .tint(.white)
            }

            Text(
                isLoading
                    ? "Saving…"
                    : (editingProfile == nil ? "Save" : "Save Changes")
            )
            .font(.headline)
            .foregroundStyle(AppTheme.Colors.secondaryAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
        .background(Color.white, in: Capsule())
        .appOutline(Capsule(), colorScheme: colorScheme)
        .contentShape(Capsule())
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
        case .done:
            return editingProfile == nil
                ? "Plant added successfully!" : "Changes saved!"
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
            thresholds: thresholds,
            linkedDeviceID: linkedDeviceID,
            linkedDeviceName: linkedDeviceName,
            sensorBaseURL: sensorBaseURL
        )
        profile.imageData = plantImage?.jpegData(compressionQuality: 0.85)

        print("Inserting profile...")
        modelContext.insert(profile)

        do {
            print("Saving context...")
            try await FirestoreService.shared.uploadPlant(profile)
            try modelContext.save()
            print("Context saved!")
        } catch {
            print("SAVE FAILED:", error)
            errorMessage = error.localizedDescription
            isLoading = false
            phase = .idle
            return
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
                let thresholds = try await GeminiService.shared.fetchThresholds(
                    for: trimmedName
                )
                profile.minTemperatureC = thresholds.minTemperatureC
                profile.maxTemperatureC = thresholds.maxTemperatureC
                profile.minHumidityPercent = thresholds.minHumidityPercent
                profile.maxHumidityPercent = thresholds.maxHumidityPercent
                profile.minSoilMoisturePercent =
                    thresholds.minSoilMoisturePercent
                profile.maxSoilMoisturePercent =
                    thresholds.maxSoilMoisturePercent
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
        profile.linkedDeviceID = linkedDeviceID
        profile.linkedDeviceName = linkedDeviceName
        profile.sensorBaseURL = sensorBaseURL
        if let plantImage {
            profile.imageData = plantImage.jpegData(compressionQuality: 0.85)
        }

        do {
            try await FirestoreService.shared.uploadPlant(profile)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            phase = .idle
            SpeechManager.shared.speak(
                "Could not update plant. \(error.localizedDescription)"
            )
            return
        }

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
