//
//  PlantSetupView.swift
//  PlantPal-CH4
//
//  Created by Nathan Yong on 30/06/26.
//

import SwiftUI
import SwiftData

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
    @Environment(\.dismiss)      private var dismiss

    @State private var plantName   = ""
    @State private var nickname    = ""
    @State private var isLoading   = false
    @State private var phase       = SetupPhase.idle
    @State private var errorMessage: String?

    enum SetupPhase {
        case idle
        case fetchingThresholds   // calling Gemini
        case saving               // writing to SwiftData
        case done
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Plant species", text: $plantName, prompt: Text("e.g. Monstera deliciosa"))
                    TextField("Nickname (optional)", text: $nickname, prompt: Text("e.g. Living room plant"))
                } header: {
                    Text("Plant details")
                } footer: {
                    Text("Use the scientific or common name. The more specific, the better the care thresholds.")
                }

                if phase != .idle {
                    Section {
                        HStack(spacing: 12) {
                            if isLoading {
                                ProgressView().controlSize(.small)
                            } else if phase == .done {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            Text(phaseLabel)
                                .foregroundStyle(isLoading ? .secondary : .primary)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Add plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isLoading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await setupPlant() }
                    }
                    .disabled(plantName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
        }
    }

    // MARK: — Phase label

    private var phaseLabel: String {
        switch phase {
        case .idle:               return ""
        case .fetchingThresholds: return "Looking up care requirements for \(plantName)…"
        case .saving:             return "Saving plant profile…"
        case .done:               return "Plant added successfully!"
        }
    }

    // MARK: — Setup flow

    private func setupPlant() async {
        let trimmedName     = plantName.trimmingCharacters(in: .whitespaces)
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespaces)
        let displayNickname = trimmedNickname.isEmpty ? trimmedName : trimmedNickname

        isLoading    = true
        errorMessage = nil

        // Step 1 — call Gemini for species-specific thresholds
        phase = .fetchingThresholds
        let thresholds: PlantThresholds
        do {
            thresholds = try await GeminiService.shared.fetchThresholds(for: trimmedName)
        } catch {
            errorMessage = error.localizedDescription
            isLoading    = false
            phase        = .idle
            return
        }

        // Step 2 — persist to SwiftData
        phase = .saving
        let profile = PlantProfile(
            name:       trimmedName,
            nickname:   displayNickname,
            thresholds: thresholds
        )
        modelContext.insert(profile)

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Couldn't save plant profile: \(error.localizedDescription)"
            isLoading    = false
            phase        = .idle
            return
        }

        // Step 3 — done
        phase     = .done
        isLoading = false

        try? await Task.sleep(for: .seconds(0.8))
        dismiss()
    }
}

#Preview {
    PlantSetupView()
        .modelContainer(for: PlantProfile.self, inMemory: true)
}
