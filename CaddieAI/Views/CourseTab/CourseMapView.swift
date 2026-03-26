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
    @Environment(ProfileStore.self) private var profileStore
    @Environment(APIUsageStore.self) private var apiUsageStore
    @State private var showingDetail = false
    @State private var showingDebug = false
    @State private var showingAnalysis = false
    @State private var analysisViewModel = HoleAnalysisViewModel()
    @State private var weather: WeatherData?

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

            // Weather badge (top-left)
            VStack {
                HStack {
                    if let weather {
                        WeatherBadge(weather: weather)
                            .padding(.top, 60)
                            .padding(.leading, 12)
                    }
                    Spacer()
                }
                Spacer()
            }

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
                        if let sel = viewModel.selectedHole,
                           let hole = course.holes.first(where: { $0.number == sel }) {
                            HStack(spacing: 8) {
                                Text("Hole \(hole.number)")
                                    .foregroundStyle(.white.opacity(0.9))
                                if let par = hole.par {
                                    Text("Par \(par)")
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                if let yardages = hole.yardages,
                                   let maxYards = yardages.values.max() {
                                    Text("\(maxYards) yds")
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                if let si = hole.strokeIndex {
                                    Text("SI \(si)")
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            .font(.caption)
                        } else {
                            Text(course.holes.isEmpty
                                 ? "No hole data available"
                                 : "\(course.stats.holesDetected) holes\(course.totalPar.map { " \u{2022} Par \($0)" } ?? "")")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                    if viewModel.selectedHole != nil {
                        Button {
                            if let sel = viewModel.selectedHole,
                               let hole = course.holes.first(where: { $0.number == sel }) {
                                showingAnalysis = true
                                Task {
                                    analysisViewModel.apiUsageStore = apiUsageStore
                                    await analysisViewModel.analyzeHole(
                                        hole,
                                        course: course,
                                        profile: profileStore.profile
                                    )
                                }
                            }
                        } label: {
                            Label("Analyze", systemImage: "wand.and.stars")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.blue)
                                .clipShape(Capsule())
                        }
                    }
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
        .sheet(isPresented: $showingAnalysis) {
            HoleAnalysisSheet(
                viewModel: analysisViewModel,
                course: course,
                profile: profileStore.profile
            )
        }
        .task {
            do {
                weather = try await WeatherService.fetchWeather(
                    latitude: course.centroid.latitude,
                    longitude: course.centroid.longitude
                )
            } catch {
                // Weather is optional — silently fail
            }
        }
    }
}

// MARK: - Hole Analysis Sheet

struct HoleAnalysisSheet: View {
    @Bindable var viewModel: HoleAnalysisViewModel
    let course: NormalizedCourse
    let profile: PlayerProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(TextToSpeechService.self) private var ttsService
    @State private var followUpText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.isAnalyzing && viewModel.analysis == nil {
                        ProgressView("Analyzing hole...")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let analysis = viewModel.analysis {
                        // Header
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hole \(analysis.holeNumber)")
                                .font(.title2.bold())
                            HStack(spacing: 12) {
                                if let par = analysis.par {
                                    Label("Par \(par)", systemImage: "flag.fill")
                                }
                                if let dist = analysis.yardagesByTee?.values.max()
                                    ?? analysis.totalDistanceYards {
                                    Label("\(dist) yds", systemImage: "ruler")
                                }
                                if let dogleg = analysis.dogleg {
                                    Label("Dogleg \(dogleg.direction.displayName)",
                                          systemImage: "arrow.turn.down.\(dogleg.direction.rawValue)")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        Divider()

                        // Quick Facts
                        quickFactsSection(analysis)

                        Divider()

                        // Strategy
                        strategySection(analysis)

                        // Error banner
                        if let error = viewModel.error {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.caption)
                            }
                            .padding(.horizontal)
                        }

                        Divider()

                        // Follow-up
                        followUpSection()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Hole Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        ttsService.stop()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Quick Facts

    @ViewBuilder
    private func quickFactsSection(_ analysis: HoleAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Facts")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 6) {
                // Yardages by tee
                if let yardages = analysis.yardagesByTee, !yardages.isEmpty {
                    let sorted = yardages.sorted { $0.value > $1.value }
                    ForEach(sorted, id: \.key) { tee, yards in
                        factRow(label: tee, value: "\(yards) yds")
                    }
                } else if let dist = analysis.totalDistanceYards {
                    factRow(label: "Distance", value: "~\(dist) yds")
                }

                if let dogleg = analysis.dogleg {
                    factRow(
                        label: "Dogleg",
                        value: "\(dogleg.direction.displayName.capitalized) at \(dogleg.distanceFromTeeYards) yds (\(Int(dogleg.bendAngleDegrees))°)"
                    )
                }

                if let width = analysis.fairwayWidthAtLandingYards {
                    factRow(label: "Fairway width", value: "~\(width) yds at landing zone")
                }

                if let depth = analysis.greenDepthYards,
                   let width = analysis.greenWidthYards {
                    factRow(label: "Green", value: "\(depth) yds deep × \(width) yds wide")
                }

                if !analysis.hazards.isEmpty {
                    ForEach(Array(analysis.hazards.enumerated()), id: \.offset) { _, hazard in
                        factRow(
                            label: hazard.type.displayName,
                            value: hazard.description,
                            icon: hazard.type == .water ? "drop.fill" : "circle.fill",
                            iconColor: hazard.type == .water ? .blue : .orange
                        )
                    }
                }

                if let weather = analysis.weather {
                    factRow(
                        label: "Weather",
                        value: weather.summaryText,
                        icon: "wind",
                        iconColor: .cyan
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    private func factRow(
        label: String,
        value: String,
        icon: String = "circle.fill",
        iconColor: Color = .green
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(iconColor)
                .frame(width: 16)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }
            Spacer()
        }
    }

    // MARK: - Strategy Section

    /// The text to speak — prefers AI advice, falls back to deterministic summary
    private var speakableStrategy: String? {
        guard let analysis = viewModel.analysis else { return nil }
        return analysis.strategicAdvice ?? analysis.deterministicSummary
    }

    @ViewBuilder
    private func strategySection(_ analysis: HoleAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Strategy")
                    .font(.headline)
                if viewModel.isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Spacer()
                if let text = speakableStrategy, !text.isEmpty {
                    Button {
                        if ttsService.isSpeaking {
                            ttsService.stop()
                        } else {
                            ttsService.speak(text)
                        }
                    } label: {
                        Label(
                            ttsService.isSpeaking ? "Stop" : "Listen",
                            systemImage: ttsService.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.circle.fill"
                        )
                        .font(.callout)
                    }
                }
            }
            .padding(.horizontal)

            if let advice = analysis.strategicAdvice {
                Text(advice)
                    .font(.body)
                    .padding(.horizontal)
            } else {
                Text(analysis.deterministicSummary)
                    .font(.body)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Follow-up Section

    @ViewBuilder
    private func followUpSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask a follow-up")
                .font(.headline)
                .padding(.horizontal)

            HStack {
                TextField("e.g. What if it's windy?", text: $followUpText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let question = followUpText
                    followUpText = ""
                    Task {
                        await viewModel.askFollowUp(question, profile: profile)
                    }
                } label: {
                    if viewModel.isAskingFollowUp {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(followUpText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isAskingFollowUp)
            }
            .padding(.horizontal)

            if let response = viewModel.followUpResponse {
                Text(response)
                    .font(.body)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
            }
        }
    }
}

// MARK: - Weather Badge

struct WeatherBadge: View {
    let weather: WeatherData

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: weather.conditionSymbol)
                .font(.caption)
            Text(weather.temperatureDescription)
                .font(.caption.weight(.semibold))
            if weather.windStrength != .none {
                Image(systemName: "wind")
                    .font(.caption2)
                Text("\(Int(weather.windSpeedMph))mph")
                    .font(.caption)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.6))
        .clipShape(Capsule())
    }
}
