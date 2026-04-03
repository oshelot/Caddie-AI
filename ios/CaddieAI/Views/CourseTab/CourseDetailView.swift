//
//  CourseDetailView.swift
//  CaddieAI
//
//  Course stats, hole list, and confidence details.
//

import SwiftUI

struct CourseDetailView: View {
    let course: NormalizedCourse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Overview
                Section("Overview") {
                    LabeledContent("Name", value: course.name)
                    if let city = course.city, let state = course.state {
                        LabeledContent("Location", value: "\(city), \(state)")
                    }
                    LabeledContent("Source", value: course.source.provider.uppercased())
                    LabeledContent("Fetched", value: course.source.fetchedAt.formatted(.dateTime.month().day().year()))
                }

                // MARK: - Scorecard
                if course.totalPar != nil || course.slopeRating != nil {
                    Section("Scorecard") {
                        if let par = course.totalPar {
                            LabeledContent("Total Par", value: "\(par)")
                        }
                        if let slope = course.slopeRating {
                            LabeledContent("Slope Rating", value: String(format: "%.0f", slope))
                        }
                        if let rating = course.courseRating {
                            LabeledContent("Course Rating", value: String(format: "%.1f", rating))
                        }
                        let dedupedTees = CourseViewModel.deduplicatedTees(for: course)
                        if !dedupedTees.isEmpty {
                            LabeledContent("Tees", value: dedupedTees.map(\.displayName).joined(separator: ", "))
                        }
                    }
                }

                // MARK: - Detection Stats
                Section("Detection Stats") {
                    StatRow(label: "Holes", count: course.stats.holesDetected, icon: "flag")
                    StatRow(label: "Greens", count: course.stats.greensDetected, icon: "circle.fill")
                    StatRow(label: "Tees", count: course.stats.teesDetected, icon: "rectangle.fill")
                    StatRow(label: "Bunkers", count: course.stats.bunkersDetected, icon: "triangle.fill")
                    StatRow(label: "Water", count: course.stats.waterFeaturesDetected, icon: "drop.fill")

                    HStack {
                        Text("Overall Confidence")
                            .fontWeight(.medium)
                        Spacer()
                        ConfidenceBadge(confidence: course.stats.overallConfidence)
                    }
                }

                // MARK: - Holes
                Section("Holes") {
                    ForEach(course.holes.sorted(by: { $0.number < $1.number })) { hole in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Hole \(hole.number)")
                                    .fontWeight(.medium)
                                if let par = hole.par {
                                    Text("Par \(par)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                if let si = hole.strokeIndex {
                                    Text("SI \(si)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                Spacer()
                                ConfidenceBadge(confidence: hole.confidence)
                            }
                            if let yardages = hole.yardages, !yardages.isEmpty {
                                HStack(spacing: 12) {
                                    ForEach(yardages.sorted(by: { $0.value > $1.value }), id: \.key) { tee, yards in
                                        Text("\(tee): \(yards)y")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Course Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Stat Row

private struct StatRow: View {
    let label: String
    let count: Int
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
    }
}
