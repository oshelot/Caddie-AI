//
//  CourseMapView.swift
//  CaddieAI
//
//  Full-screen map with hole selector overlay and course info.
//

import SwiftUI

struct CourseMapView: View {
    let course: NormalizedCourse
    @Environment(CourseViewModel.self) private var viewModel
    @State private var showingDetail = false
    @State private var showingDebug = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Satellite map with overlays
            MapboxMapRepresentable(
                course: course,
                selectedHole: viewModel.selectedHole,
                onHoleTapped: { hole in
                    viewModel.selectedHole = hole
                }
            )
            .ignoresSafeArea()

            // Bottom overlay
            VStack(spacing: 0) {
                // No holes banner
                if course.holes.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        Text("This course hasn't been fully mapped yet. Satellite view only.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                }

                // Top info bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(course.holes.isEmpty
                             ? "No hole data available"
                             : "\(course.stats.holesDetected) holes detected")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    if !course.holes.isEmpty {
                        ConfidenceBadge(confidence: course.stats.overallConfidence)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

                // Hole selector (only if holes exist)
                if !course.holes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                viewModel.selectedHole = nil
                            } label: {
                                Text("All")
                                    .font(.subheadline)
                                    .fontWeight(viewModel.selectedHole == nil ? .bold : .regular)
                                    .foregroundStyle(viewModel.selectedHole == nil ? .white : .white.opacity(0.6))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        viewModel.selectedHole == nil
                                            ? AnyShapeStyle(.blue)
                                            : AnyShapeStyle(.white.opacity(0.15))
                                    )
                                    .clipShape(Capsule())
                            }

                            ForEach(course.holes.sorted(by: { $0.number < $1.number })) { hole in
                                Button {
                                    viewModel.selectedHole = hole.number
                                } label: {
                                    Text("\(hole.number)")
                                        .font(.subheadline)
                                        .fontWeight(viewModel.selectedHole == hole.number ? .bold : .regular)
                                        .foregroundStyle(viewModel.selectedHole == hole.number ? .white : .white.opacity(0.6))
                                        .frame(minWidth: 32)
                                        .padding(.vertical, 6)
                                        .background(
                                            viewModel.selectedHole == hole.number
                                                ? AnyShapeStyle(.blue)
                                                : AnyShapeStyle(.white.opacity(0.15))
                                        )
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(.ultraThinMaterial)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingDetail = true
                    } label: {
                        Label("Course Details", systemImage: "info.circle")
                    }
                    Button {
                        showingDebug = true
                    } label: {
                        Label("Debug Info", systemImage: "ladybug")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $showingDetail) {
            CourseDetailView(course: course)
        }
        .sheet(isPresented: $showingDebug) {
            CourseDebugView(course: course)
        }
    }
}
