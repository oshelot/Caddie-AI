//
//  ShotHistoryView.swift
//  CaddieAI
//

import SwiftUI

struct ShotHistoryView: View {
    @Environment(ShotHistoryStore.self) private var historyStore

    var body: some View {
        NavigationStack {
            Group {
                if historyStore.records.isEmpty {
                    ContentUnavailableView(
                        "No Shot History",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text("Your shots will appear here after you get advice from the caddie.")
                    )
                } else {
                    List {
                        ForEach(historyStore.records) { record in
                            NavigationLink {
                                ShotDetailView(record: record)
                            } label: {
                                ShotHistoryRow(record: record)
                            }
                        }
                        .onDelete { offsets in
                            historyStore.deleteRecord(at: offsets)
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

// MARK: - Shot History Row

private struct ShotHistoryRow: View {
    let record: ShotRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.recommendedClub)
                        .font(.headline)
                    Text("• \(record.effectiveDistance) yds")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(record.context.shotType.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: .capsule)
                    Text(record.context.lieType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(record.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let outcome = record.outcome {
                Text(outcome.emoji)
                    .font(.title2)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shot Detail View

struct ShotDetailView: View {
    @Environment(ShotHistoryStore.self) private var historyStore
    let record: ShotRecord

    @State private var selectedOutcome: ShotOutcome?
    @State private var actualClub: String
    @State private var notes: String

    init(record: ShotRecord) {
        self.record = record
        _selectedOutcome = State(initialValue: record.outcome)
        _actualClub = State(initialValue: record.actualClubUsed ?? record.recommendedClub)
        _notes = State(initialValue: record.notes)
    }

    var body: some View {
        Form {
            Section("Shot Info") {
                LabeledContent("Date", value: record.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Shot Type", value: record.context.shotType.displayName)
                LabeledContent("Distance", value: "\(record.context.distanceYards) yds")
                LabeledContent("Effective Distance", value: "\(record.effectiveDistance) yds")
                LabeledContent("Lie", value: record.context.lieType.displayName)
                LabeledContent("Recommended Club", value: record.recommendedClub)
                LabeledContent("Target", value: record.target)
            }

            Section("Conditions") {
                if record.context.windStrength != .none {
                    LabeledContent("Wind", value: "\(record.context.windStrength.displayName) \(record.context.windDirection.displayName)")
                }
                if record.context.slope != .level {
                    LabeledContent("Slope", value: record.context.slope.displayName)
                }
                if !record.context.hazardNotes.isEmpty {
                    LabeledContent("Hazards", value: record.context.hazardNotes)
                }
            }

            Section("Your Result") {
                Picker("Actual Club Used", selection: $actualClub) {
                    ForEach(Club.shotClubs) { club in
                        Text(club.displayName).tag(club.displayName)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Outcome")
                        .font(.subheadline)
                    HStack(spacing: 12) {
                        ForEach(ShotOutcome.allCases) { outcome in
                            Button {
                                selectedOutcome = outcome
                            } label: {
                                VStack(spacing: 2) {
                                    Text(outcome.emoji)
                                        .font(.title2)
                                    Text(outcome.displayName)
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    selectedOutcome == outcome ? Color.accentColor.opacity(0.2) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedOutcome == outcome ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Button("Save Result") {
                    saveResult()
                }
                .disabled(selectedOutcome == nil)
            }
        }
        .navigationTitle("Shot Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveResult() {
        var updated = record
        updated.outcome = selectedOutcome
        updated.actualClubUsed = actualClub
        updated.notes = notes
        historyStore.updateRecord(updated)
    }
}

#Preview {
    ShotHistoryView()
        .environment(ShotHistoryStore())
}
