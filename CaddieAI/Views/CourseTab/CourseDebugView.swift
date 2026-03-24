//
//  CourseDebugView.swift
//  CaddieAI
//
//  Developer debug view showing raw OSM counts, confidence breakdowns, and IDs.
//

import SwiftUI

struct CourseDebugView: View {
    let course: NormalizedCourse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Course Identity") {
                    LabeledContent("ID", value: course.id)
                    LabeledContent("Schema", value: course.schemaVersion)
                    if let osmId = course.source.osmCourseId {
                        LabeledContent("OSM Course ID", value: osmId)
                    }
                }

                Section("Centroid") {
                    LabeledContent("Latitude", value: String(format: "%.6f", course.centroid.latitude))
                    LabeledContent("Longitude", value: String(format: "%.6f", course.centroid.longitude))
                }

                Section("Bounding Box") {
                    LabeledContent("South", value: String(format: "%.6f", course.boundingBox.south))
                    LabeledContent("West", value: String(format: "%.6f", course.boundingBox.west))
                    LabeledContent("North", value: String(format: "%.6f", course.boundingBox.north))
                    LabeledContent("East", value: String(format: "%.6f", course.boundingBox.east))
                }

                Section("Confidence Breakdown per Hole") {
                    ForEach(course.holes.sorted(by: { $0.number < $1.number })) { hole in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hole \(hole.number)")
                                .font(.headline)

                            if let bd = hole.confidenceBreakdown {
                                ConfidenceRow(label: "Hole path", value: bd.holePath, weight: 0.35)
                                ConfidenceRow(label: "Green", value: bd.green, weight: 0.30)
                                ConfidenceRow(label: "Tee", value: bd.tee, weight: 0.15)
                                ConfidenceRow(label: "Hole number", value: bd.holeNumber, weight: 0.10)
                                ConfidenceRow(label: "Hazards", value: bd.hazards, weight: 0.05)
                                ConfidenceRow(label: "Geometry", value: bd.geometryConsistency, weight: 0.05)
                                HStack {
                                    Text("Weighted total")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(String(format: "%.2f", bd.weighted))
                                        .fontWeight(.semibold)
                                }
                            }

                            if let refs = hole.rawRefs {
                                Group {
                                    if let wayId = refs.holeWayId {
                                        Text("Way: \(wayId)").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    if let greenId = refs.greenWayId {
                                        Text("Green: \(greenId)").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Confidence Row

private struct ConfidenceRow: View {
    let label: String
    let value: Double
    let weight: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.0f%%", value * 100))
                .font(.caption)
                .monospacedDigit()
            Text(String(format: "(×%.2f)", weight))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
