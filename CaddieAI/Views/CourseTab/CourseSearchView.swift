//
//  CourseSearchView.swift
//  CaddieAI
//
//  Search form, results list, and saved courses.
//

import SwiftUI
import CoreLocation
import MapKit

struct CourseSearchView: View {
    @Environment(CourseViewModel.self) private var viewModel
    @Environment(CourseCacheService.self) private var cacheService
    @Environment(LocationManager.self) private var locationManager
    @State private var nearbyCourseSuggestion: CourseCacheEntry?
    @State private var showNearbyPrompt = false
    @State private var courseToDelete: CourseCacheEntry?
    @State private var showDeleteConfirmation = false
    @State private var cityCompleter = CityCompleter()

    var body: some View {
        @Bindable var vm = viewModel

        NavigationStack {
            List {
                // MARK: - Search Section
                Section("Search Courses") {
                    TextField("Course name", text: $vm.searchText)
                        .textContentType(.organizationName)
                        .autocorrectionDisabled()

                    TextField("City (optional)", text: $vm.cityText)
                        .textContentType(.addressCity)
                        .onChange(of: viewModel.cityText) { _, newValue in
                            cityCompleter.update(query: newValue)
                        }

                    if !cityCompleter.suggestions.isEmpty && !viewModel.cityText.isEmpty {
                        ForEach(cityCompleter.suggestions, id: \.self) { suggestion in
                            Button {
                                viewModel.cityText = suggestion
                                cityCompleter.clear()
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.circle")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Text(suggestion)
                                        .font(.subheadline)
                                }
                            }
                            .tint(.primary)
                        }
                    }

                    Button {
                        Task { await viewModel.searchCourses() }
                    } label: {
                        HStack {
                            Text("Search")
                            if viewModel.isSearching {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSearching)
                }

                // MARK: - Favorites
                if !cacheService.favoriteCourses.isEmpty {
                    Section("Favorites") {
                        ForEach(cacheService.favoriteCourses) { entry in
                            Button {
                                viewModel.loadCachedCourse(id: entry.id)
                            } label: {
                                HStack {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.caption)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.headline)
                                        if let city = entry.city {
                                            Text([city, entry.state].compactMap { $0 }.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }

                // MARK: - Search Error
                if let error = viewModel.searchError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                // MARK: - Search Results
                if !viewModel.searchResults.isEmpty {
                    Section("Results") {
                        ForEach(viewModel.searchResults) { result in
                            Button {
                                Task { await viewModel.ingestCourse(result) }
                            } label: {
                                CourseSearchRow(result: result)
                            }
                            .tint(.primary)
                        }
                    }
                }

                // MARK: - Saved Courses
                if !viewModel.cachedCourses.isEmpty {
                    Section("Saved Courses") {
                        ForEach(viewModel.cachedCourses) { entry in
                            Button {
                                viewModel.loadCachedCourse(id: entry.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name)
                                        .font(.headline)
                                    if let city = entry.city {
                                        Text([city, entry.state].compactMap { $0 }.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        ConfidenceBadge(confidence: entry.overallConfidence)
                                        Spacer()
                                        Text("Saved \(entry.cachedAt.formatted(.relative(presentation: .named)))")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .tint(.primary)
                            .swipeActions(edge: .leading) {
                                Button {
                                    cacheService.toggleFavorite(id: entry.id)
                                } label: {
                                    Label(
                                        cacheService.isFavorite(id: entry.id) ? "Unfavorite" : "Favorite",
                                        systemImage: cacheService.isFavorite(id: entry.id) ? "star.slash" : "star.fill"
                                    )
                                }
                                .tint(.yellow)
                            }
                        }
                        .onDelete { offsets in
                            let entries = viewModel.cachedCourses
                            if let first = offsets.first {
                                courseToDelete = entries[first]
                                showDeleteConfirmation = true
                            }
                        }
                    }
                }
            }
            .navigationTitle("Courses")
            .navigationDestination(isPresented: Binding(
                get: { viewModel.selectedCourse != nil },
                set: { if !$0 { viewModel.clearSelection() } }
            )) {
                if let course = viewModel.selectedCourse {
                    CourseMapView(course: course)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.isIngesting || viewModel.ingestionError != nil || viewModel.ingestionWarning != nil },
                set: { if !$0 {
                    viewModel.ingestionError = nil
                    viewModel.ingestionWarning = nil
                }}
            )) {
                CourseIngestionView()
                    .environment(viewModel)
                    .interactiveDismissDisabled(viewModel.isIngesting)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.showSubCoursePicker },
                set: { if !$0 { viewModel.showSubCoursePicker = false } }
            )) {
                SubCoursePickerView()
                    .environment(viewModel)
            }
            .task {
                await checkForNearbyCourse()
            }
            .alert(
                "Are you playing here?",
                isPresented: $showNearbyPrompt,
                presenting: nearbyCourseSuggestion
            ) { entry in
                Button("Yes, load it") {
                    viewModel.loadCachedCourse(id: entry.id)
                }
                Button("No", role: .cancel) { }
            } message: { entry in
                let location = [entry.city, entry.state].compactMap { $0 }.joined(separator: ", ")
                Text("It looks like you're at \(entry.name)" + (location.isEmpty ? "." : " in \(location)."))
            }
            .alert(
                "Delete Course?",
                isPresented: $showDeleteConfirmation,
                presenting: courseToDelete
            ) { entry in
                Button("Delete", role: .destructive) {
                    cacheService.invalidate(id: entry.id)
                }
                Button("Keep", role: .cancel) { }
            } message: { entry in
                Text("Course data for \(entry.name) is cached for faster loading. If you plan to play here again, consider keeping it.")
            }
        }
    }

    // MARK: - Proximity Check

    private func checkForNearbyCourse() async {
        guard locationManager.isAuthorized else { return }
        guard viewModel.selectedCourse == nil else { return }

        locationManager.requestCurrentLocation()

        // Wait up to 5 seconds for a location fix
        for _ in 0..<50 {
            if locationManager.currentLocation != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard let coord = locationManager.currentLocation else { return }

        let nearby = cacheService.coursesNear(
            latitude: coord.latitude,
            longitude: coord.longitude
        )

        if let closest = nearby.first {
            nearbyCourseSuggestion = closest
            showNearbyPrompt = true
        }
    }
}

// MARK: - Search Result Row

struct CourseSearchRow: View {
    let result: CourseSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.name)
                    .font(.headline)
                if result.isCached {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            if let city = result.city, let state = result.state {
                Text("\(city), \(state)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let city = result.city {
                Text(city)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if result.source == .appleMapKit {
                Text("Map data may be limited")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Sub-Course Picker

struct SubCoursePickerView: View {
    @Environment(CourseViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This facility has multiple courses. Choose the one you'd like to view.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Available Courses") {
                    ForEach(viewModel.availableSubCourses) { course in
                        Button {
                            viewModel.selectSubCourse(course)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(course.subCourseName ?? course.name)
                                        .font(.headline)
                                    Text("\(course.stats.holesDetected) holes")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                ConfidenceBadge(confidence: course.stats.overallConfidence)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle("Select Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.showSubCoursePicker = false
                        viewModel.availableSubCourses = []
                    }
                }
            }
        }
    }
}

// MARK: - City Autocomplete

@Observable
final class CityCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private(set) var suggestions: [String] = []

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestions = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        suggestions = []
        completer.cancel()
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = Array(
            completer.results
                .map { [$0.title, $0.subtitle].filter { !$0.isEmpty }.joined(separator: ", ") }
                .prefix(4)
        )
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Best-effort; silently ignore
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)
            Text("\(Int(confidence * 100))%")
                .font(.caption2)
                .fontWeight(.medium)
        }
    }

    private var badgeColor: Color {
        if confidence >= 0.80 { return .green }
        if confidence >= 0.55 { return .yellow }
        return .red
    }
}
