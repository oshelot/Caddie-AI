//
//  YourBagView.swift
//  CaddieAI
//
//  Club distances editor with add, remove, and sort functionality.
//

import SwiftUI

struct YourBagView: View {
    @Environment(ProfileStore.self) private var profileStore
    @State private var showingAddClub = false
    @State private var showingIronTypePicker = false

    private static let maxClubs = 13

    private var bagIsFull: Bool {
        profileStore.profile.clubDistances.count >= Self.maxClubs
    }

    /// Clubs not yet in the player's bag (excludes putter)
    private var availableClubs: [Club] {
        let currentClubs = Set(profileStore.profile.clubDistances.map(\.club))
        return Club.shotClubs.filter { !currentClubs.contains($0) }
    }

    var body: some View {
        @Bindable var store = profileStore

        Form {
            Section {
                ForEach($store.profile.clubDistances) { $clubDistance in
                    HStack {
                        Text(clubDistance.club.displayName)
                            .frame(width: 150, alignment: .leading)
                        Spacer()
                        TextField("yards", value: $clubDistance.carryYards, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("yds")
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                    }
                }
                .onDelete(perform: deleteClubs)
            } header: {
                HStack {
                    Text("Clubs (\(profileStore.profile.clubDistances.count)/\(Self.maxClubs))")
                    Spacer()
                    Text("Sorted by distance")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Swipe left on a club to remove it from your bag.")
            }

            if !bagIsFull && !availableClubs.isEmpty {
                Section {
                    Button {
                        showingAddClub = true
                    } label: {
                        Label("Add Club", systemImage: "plus.circle")
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { profileStore.profile.ironType != nil },
                    set: { isOn in
                        if isOn {
                            showingIronTypePicker = true
                        } else {
                            profileStore.profile.ironType = nil
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Game Improvement Irons")
                        if let ironType = profileStore.profile.ironType {
                            Text(ironType.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("GI/SGI irons have wider soles and higher offset. The caddie will account for reduced versatility from bunkers, tight lies, and rough.")
            }
        }
        .navigationTitle("Your Bag")
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showingAddClub) {
            AddClubSheet(availableClubs: availableClubs) { club, yards in
                addClub(club, carryYards: yards)
            }
        }
        .confirmationDialog(
            "What type of game improvement irons?",
            isPresented: $showingIronTypePicker,
            titleVisibility: .visible
        ) {
            Button("Game Improvement") {
                profileStore.profile.ironType = .gameImprovement
            }
            Button("Super Game Improvement") {
                profileStore.profile.ironType = .superGameImprovement
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: profileStore.profile.clubDistances.map(\.carryYards)) {
            sortBag()
        }
    }

    private func deleteClubs(at offsets: IndexSet) {
        profileStore.profile.clubDistances.remove(atOffsets: offsets)
    }

    private func addClub(_ club: Club, carryYards: Int) {
        profileStore.profile.clubDistances.append(
            ClubDistance(club: club, carryYards: carryYards)
        )
        sortBag()
    }

    private func sortBag() {
        profileStore.profile.clubDistances.sort { $0.carryYards > $1.carryYards }
    }
}

// MARK: - Add Club Sheet

struct AddClubSheet: View {
    let availableClubs: [Club]
    let onAdd: (Club, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedClub: Club?
    @State private var carryYards: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                clubSelectionSection
                distanceSection
            }
            .navigationTitle("Add Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let club = selectedClub {
                            onAdd(club, carryYards)
                            dismiss()
                        }
                    }
                    .disabled(selectedClub == nil || carryYards <= 0)
                }
            }
        }
    }

    private var clubSelectionSection: some View {
        Section("Select a Club") {
            ForEach(availableClubs) { club in
                clubRow(club)
            }
        }
    }

    private func clubRow(_ club: Club) -> some View {
        Button {
            selectedClub = club
            carryYards = club.defaultCarryYards
        } label: {
            HStack {
                Text(club.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(club.defaultCarryYards) yds avg")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                if selectedClub == club {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    @ViewBuilder
    private var distanceSection: some View {
        if let club = selectedClub {
            Section("Set Your Distance") {
                HStack {
                    Text(club.shortName)
                        .fontWeight(.medium)
                    Spacer()
                    TextField("yards", value: $carryYards, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("yds")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        YourBagView()
            .environment(ProfileStore())
    }
}
