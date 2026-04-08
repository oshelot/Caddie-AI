//
//  CourseMapView.swift
//  CaddieAI
//
//  Full-screen map with hole selector overlay and course info.
//

import CoreLocation
import SwiftUI

/// Info displayed when the user taps a point on the course map.
struct TapDistanceInfo {
    let tapPoint: CLLocationCoordinate2D
    let greenCenter: CLLocationCoordinate2D
    let distanceYards: Int
    let recommendedClub: String?
}

struct CourseMapView: View {
    let course: NormalizedCourse
    @Environment(CourseViewModel.self) private var viewModel
    @Environment(ProfileStore.self) private var profileStore
    @Environment(APIUsageStore.self) private var apiUsageStore
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(CourseCacheService.self) private var cacheService
    @Environment(ShotAdvisorViewModel.self) private var shotAdvisor
    @Environment(TabRouter.self) private var tabRouter
    @State private var isDetecting = false
    @State private var showingDetail = false
    @State private var showingDebug = false
    @State private var showingAnalysis = false
    @State private var analysisViewModel = HoleAnalysisViewModel()
    @State private var weather: WeatherData?
    @State private var locationManager = LocationManager()
    @State private var showUserLocation = false
    @State private var showTeeReminder = false
    @State private var tapDistanceInfo: TapDistanceInfo?

    /// Pre-sorted holes to avoid re-sorting on every render.
    private var sortedHoles: [NormalizedHole] {
        course.holes.sorted { $0.number < $1.number }
    }

    /// The currently selected hole model, pre-computed to avoid repeated O(n) lookups.
    private var selectedHoleModel: NormalizedHole? {
        guard let sel = viewModel.selectedHole else { return nil }
        return course.holes.first { $0.number == sel }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Satellite map with overlays
            MapboxMapRepresentable(
                course: course,
                selectedHole: viewModel.selectedHole,
                showUserLocation: showUserLocation,
                onHoleTapped: { hole in
                    viewModel.selectedHole = hole
                },
                onMapTapped: { coordinate in
                    handleMapTap(coordinate)
                },
                tapLine: tapDistanceInfo.map {
                    TapLineData(from: $0.tapPoint, to: $0.greenCenter)
                }
            )
            .ignoresSafeArea()

            // Weather badge (top-left) and location button (top-right)
            VStack {
                HStack {
                    if let weather {
                        WeatherBadge(weather: weather)
                            .padding(.top, 60)
                            .padding(.leading, 12)
                    }
                    Spacer()
                    Button {
                        if locationManager.isAuthorized {
                            showUserLocation.toggle()
                        } else {
                            locationManager.requestPermission()
                            showUserLocation = true
                        }
                    } label: {
                        Image(systemName: showUserLocation ? "location.fill" : "location")
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 12)
                }

                // Tee box reminder callout
                if showTeeReminder, CourseViewModel.deduplicatedTees(for: course).count > 1 {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.yellow)
                        Text("Tap the tee button above to choose your tee box")
                            .font(.subheadline)
                        Spacer()
                        Button {
                            withAnimation { showTeeReminder = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }

            // Bottom overlay
            VStack(spacing: 0) {
                // Tap-to-distance label
                if let info = tapDistanceInfo {
                    HStack(spacing: 8) {
                        Image(systemName: "ruler")
                            .font(.caption)
                        Text("\(info.distanceYards) yds")
                            .font(.subheadline.weight(.bold))
                        if let club = info.recommendedClub {
                            Text("•")
                                .foregroundStyle(.white.opacity(0.5))
                            Text(club)
                                .font(.subheadline)
                        }
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                tapDistanceInfo = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.75))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

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
                        if let hole = selectedHoleModel {
                            HStack(spacing: 8) {
                                Text("Hole \(hole.number)")
                                    .foregroundStyle(.white.opacity(0.9))
                                if let par = hole.par {
                                    Text("Par \(par)")
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                if let yardages = hole.yardages,
                                   let yards = viewModel.selectedTee.flatMap({ yardages[$0] })
                                        ?? yardages.values.max() {
                                    Text("\(yards) yds")
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                if let si = hole.strokeIndex {
                                    Text("SI \(si)")
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            .font(.caption)
                        } else {
                            let teeYards: String = {
                                guard let tee = viewModel.selectedTee,
                                      let yards = course.teeYardageTotals?[tee] else { return "" }
                                return " \u{2022} \(yards) yds"
                            }()
                            Text(course.holes.isEmpty
                                 ? "No hole data available"
                                 : "\(course.stats.holesDetected) holes\(course.totalPar.map { " \u{2022} Par \($0)" } ?? "")\(teeYards)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                    if !course.holes.isEmpty {
                        ConfidenceBadge(confidence: course.stats.overallConfidence)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

                // Action buttons (separate row so they don't compete for space)
                if viewModel.selectedHole != nil {
                    HStack(spacing: 12) {
                        Button {
                            autoDetectAndAskCaddie()
                        } label: {
                            Label("Ask Caddie", systemImage: "figure.golf")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.green)
                                .clipShape(Capsule())
                        }
                        .disabled(isDetecting)

                        Button {
                            if let hole = selectedHoleModel {
                                showingAnalysis = true
                                Task {
                                    analysisViewModel.apiUsageStore = apiUsageStore
                                    analysisViewModel.subscriptionManager = subscriptionManager
                                    await analysisViewModel.analyzeHole(
                                        hole,
                                        course: course,
                                        profile: profileStore.profile,
                                        selectedTee: viewModel.selectedTee
                                    )
                                }
                            }
                        } label: {
                            Label("Analyze", systemImage: "wand.and.stars")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                }

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

                            ForEach(sortedHoles) { hole in
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
        .navigationTitle("Course Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    let dedupedTees = CourseViewModel.deduplicatedTees(for: course)
                    if dedupedTees.count > 1 {
                        Menu {
                            ForEach(dedupedTees, id: \.canonicalTee) { entry in
                                Button {
                                    viewModel.selectedTee = entry.canonicalTee
                                    cacheService.saveSelectedTee(entry.canonicalTee, forCourse: course.id)
                                    showTeeReminder = false
                                } label: {
                                    HStack {
                                        Text(entry.displayName)
                                        if let yards = course.teeYardageTotals?[entry.canonicalTee] {
                                            Text("(\(yards) yds)")
                                        }
                                        if viewModel.selectedTee == entry.canonicalTee {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "flag.fill")
                                Text(teePickerLabel(dedupedTees: dedupedTees))
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.8))
                            .clipShape(Capsule())
                        }
                    } else if let selected = viewModel.selectedTee {
                        // Single tee — show label without a menu
                        HStack(spacing: 4) {
                            Image(systemName: "flag.fill")
                            Text(dedupedTees.first?.displayName ?? selected)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.8))
                        .clipShape(Capsule())
                    }

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
            // Restore saved tee, match profile preference, or auto-select first
            if viewModel.selectedTee == nil {
                let dedupedTees = CourseViewModel.deduplicatedTees(for: course)
                if !dedupedTees.isEmpty {
                    let hasSavedTee = cacheService.selectedTee(forCourse: course.id) != nil
                    if let saved = cacheService.selectedTee(forCourse: course.id),
                       dedupedTees.contains(where: { $0.canonicalTee == saved }) {
                        viewModel.selectedTee = saved
                    } else if let match = CourseViewModel.bestTeeForPreference(
                        profileStore.profile.preferredTeeBox,
                        from: dedupedTees
                    ) {
                        viewModel.selectedTee = match
                        cacheService.saveSelectedTee(match, forCourse: course.id)
                        // Show reminder so user knows which tee was auto-selected
                        if !hasSavedTee && dedupedTees.count > 1 {
                            showTeeReminder = true
                        }
                    } else {
                        viewModel.selectedTee = dedupedTees.first?.canonicalTee
                        if dedupedTees.count > 1 {
                            showTeeReminder = true
                        }
                    }
                }
            }

            do {
                weather = try await WeatherService.fetchWeather(
                    latitude: course.centroid.latitude,
                    longitude: course.centroid.longitude
                )
            } catch {
                // Weather is optional — silently fail
            }
        }
        .onChange(of: viewModel.selectedHole) {
            tapDistanceInfo = nil
        }
    }

    // MARK: - Auto Detect

    private func autoDetectAndAskCaddie() {
        guard let hole = selectedHoleModel else { return }

        if !locationManager.isAuthorized {
            locationManager.requestPermission()
            return
        }

        isDetecting = true
        locationManager.requestCurrentLocation()

        Task {
            // Brief wait for location callback
            try? await Task.sleep(for: .seconds(0.8))

            guard let userCoord = locationManager.currentLocation else {
                isDetecting = false
                return
            }

            let userPoint = GeoJSONPoint(
                latitude: userCoord.latitude,
                longitude: userCoord.longitude
            )

            // 1. Distance to green (yards)
            let greenTarget = hole.green?.centroid ?? hole.lineOfPlay?.endPoint
            let distYards: Int
            if let target = greenTarget {
                distYards = Int(userPoint.distance(to: target) / 0.9144)
            } else {
                distYards = 150
            }

            // 2. Hole bearing (tee-to-green line)
            let holeBearing = hole.lineOfPlay?.bearingAtDistance(0)

            // 3. Shot type from distance vs player's bag
            let shotType = inferShotType(
                distanceYards: distYards,
                clubDistances: profileStore.profile.clubDistances
            )

            // 4. Build shot context
            shotAdvisor.resetForNewShot()
            shotAdvisor.shotContext.distanceYards = distYards
            shotAdvisor.shotContext.shotType = shotType
            shotAdvisor.shotContext.lieType = .fairway
            shotAdvisor.shotContext.aggressiveness = profileStore.profile.defaultAggressiveness
            shotAdvisor.shotContext.slope = .level

            // 5. Apply weather (wind strength + relative direction)
            if let weather {
                shotAdvisor.applyWeather(weather, holeBearingDegrees: holeBearing)
            }

            // 6. Auto-populate hazard notes from hole data
            var hazards: [String] = []
            if !hole.water.isEmpty { hazards.append("Water in play") }
            if !hole.bunkers.isEmpty { hazards.append("\(hole.bunkers.count) bunker(s)") }
            shotAdvisor.shotContext.hazardNotes = hazards.joined(separator: ". ")

            // 7. Navigate to Caddie tab
            isDetecting = false
            tabRouter.selectedTab = "caddie"
        }
    }

    /// Returns the display name for the currently selected tee from the deduped list, or "Tees" as fallback.
    private func teePickerLabel(dedupedTees: [(displayName: String, canonicalTee: String)]) -> String {
        guard let selected = viewModel.selectedTee else { return "Tees" }
        return dedupedTees.first(where: { $0.canonicalTee == selected })?.displayName ?? selected
    }

    // bestTeeForPreference lives on CourseViewModel for testability

    private func inferShotType(distanceYards: Int, clubDistances: [ClubDistance]) -> ShotType {
        let sorted = clubDistances.sorted { $0.carryYards > $1.carryYards }
        let longestCarry = sorted.first?.carryYards ?? 250
        let shortestWedge = sorted.last?.carryYards ?? 60

        if distanceYards > longestCarry {
            return .tee
        } else if distanceYards <= 40 {
            return .chip
        } else if distanceYards <= shortestWedge {
            return .pitch
        } else {
            return .approach
        }
    }

    // MARK: - Tap to Distance

    private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        // Require a selected hole so we know which green to measure to
        guard let hole = selectedHoleModel else { return }

        let greenTarget: GeoJSONPoint? = hole.green?.centroid ?? hole.lineOfPlay?.endPoint
        guard let target = greenTarget else { return }

        let tapPoint = GeoJSONPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let distMeters = tapPoint.distance(to: target)
        let distYards = Int(distMeters / 0.9144)

        let club = recommendClub(
            distanceYards: distYards,
            clubDistances: profileStore.profile.clubDistances
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            tapDistanceInfo = TapDistanceInfo(
                tapPoint: coordinate,
                greenCenter: CLLocationCoordinate2D(
                    latitude: target.latitude,
                    longitude: target.longitude
                ),
                distanceYards: distYards,
                recommendedClub: club
            )
        }
    }

    private func recommendClub(distanceYards: Int, clubDistances: [ClubDistance]) -> String? {
        guard !clubDistances.isEmpty else { return nil }
        let sorted = clubDistances.sorted { $0.carryYards > $1.carryYards }
        guard let best = sorted.min(by: {
            abs($0.carryYards - distanceYards) < abs($1.carryYards - distanceYards)
        }) else { return nil }
        return best.club.displayName
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
    @State private var showOffTopicAlert = false

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

                            #if DEBUG
                            if viewModel.engineLatencyMs != nil || viewModel.llmLatencyMs != nil {
                                let parts = [
                                    viewModel.engineLatencyMs.map { "Engine: \($0)ms" },
                                    viewModel.llmLatencyMs.map { ms in
                                        ms >= 1000
                                            ? "LLM: \(String(format: "%.1f", Double(ms) / 1000.0))s"
                                            : "LLM: \(ms)ms"
                                    }
                                ].compactMap { $0 }
                                Text(parts.joined(separator: " | "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            #endif
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
                    .onChange(of: followUpText) { _, new in
                        var capped = new
                        InputGuard.enforceLimit(&capped)
                        if capped != new { followUpText = capped }
                    }

                Button {
                    if InputGuard.isGolfRelated(followUpText) {
                        let question = followUpText
                        followUpText = ""
                        Task {
                            await viewModel.askFollowUp(question, profile: profile)
                        }
                    } else {
                        showOffTopicAlert = true
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
            .alert("Off Topic", isPresented: $showOffTopicAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(PromptService.shared.offTopicResponse)
            }

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
