//
//  ShotInputView.swift
//  CaddieAI
//

import PhotosUI
import SwiftUI

struct ShotInputView: View {
    @Environment(ShotAdvisorViewModel.self) private var viewModel
    @Environment(ProfileStore.self) private var profileStore
    @Environment(SpeechRecognitionService.self) private var speechService
    @Environment(ShotHistoryStore.self) private var historyStore
    @Environment(TextToSpeechService.self) private var ttsService
    @Environment(CourseViewModel.self) private var courseViewModel
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showingRecommendation = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    private var imageAnalysisEnabled: Bool {
        subscriptionManager.tier == .paid
            && profileStore.profile.betaImageAnalysis
            && PromptService.shared.isFeatureEnabled("imageAnalysis")
    }

    var body: some View {
        @Bindable var vm = viewModel

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Voice & Image Input
                    GroupBox("Quick Input") {
                        VStack(alignment: .leading, spacing: 12) {
                            // Voice recording
                            HStack {
                                Button {
                                    if !speechService.isRecording {
                                        viewModel.voiceStartTime = CFAbsoluteTimeGetCurrent()
                                    }
                                    speechService.toggleRecording()
                                } label: {
                                    Label(
                                        speechService.isRecording ? "Stop" : "Speak",
                                        systemImage: speechService.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                                    )
                                    .foregroundStyle(speechService.isRecording ? .red : .blue)
                                }
                                .buttonStyle(.plain)

                                if speechService.isRecording {
                                    WaveformIndicator()
                                }

                                Spacer()

                                // Photo picker (Pro + Beta opt-in + server flag)
                                if imageAnalysisEnabled {
                                    PhotosPicker(
                                        selection: $selectedPhotoItem,
                                        matching: .images
                                    ) {
                                        if viewModel.selectedImage != nil {
                                            Label("Photo", systemImage: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        } else {
                                            Label("Photo", systemImage: "camera.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Voice transcription / notes
                            if !speechService.transcribedText.isEmpty || !vm.voiceNotes.isEmpty {
                                TextField("Voice notes", text: $vm.voiceNotes, axis: .vertical)
                                    .lineLimit(2...4)
                                    .onChange(of: vm.voiceNotes) { _, new in
                                        var capped = new
                                        InputGuard.enforceLimit(&capped)
                                        if capped != new { vm.voiceNotes = capped }
                                    }
                            }

                            // Image thumbnail (only visible when image analysis is enabled)
                            if imageAnalysisEnabled, let image = viewModel.selectedImage {
                                HStack {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text("Lie photo attached")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Remove") {
                                        viewModel.selectedImage = nil
                                        selectedPhotoItem = nil
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    // Distance & Shot Type
                    GroupBox("Shot Setup") {
                        VStack(spacing: 12) {
                            LabeledContent("Distance (yards)") {
                                TextField("150", value: $vm.shotContext.distanceYards, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                            LabeledContent("Shot Type") {
                                MenuPicker(
                                    selection: $vm.shotContext.shotType,
                                    options: ShotType.allCases,
                                    displayName: \.displayName
                                )
                            }
                        }
                    }

                    // Conditions
                    GroupBox("Conditions") {
                        VStack(spacing: 12) {
                            if vm.shotContext.shotType.showsLiePicker {
                                LabeledContent("Lie") {
                                    FilteredMenuPicker(
                                        selection: $vm.shotContext.lieType,
                                        options: vm.shotContext.shotType.validLies,
                                        displayName: \.displayName
                                    )
                                }
                            }

                            LabeledContent("Wind") {
                                HStack {
                                    MenuPicker(
                                        selection: $vm.shotContext.windStrength,
                                        options: WindStrength.allCases,
                                        displayName: \.displayName
                                    )

                                    if let weather = courseViewModel.currentWeather,
                                       weather.windStrength != .none {
                                        Button {
                                            viewModel.applyWeather(weather)
                                        } label: {
                                            Label("Live", systemImage: "antenna.radiowaves.left.and.right")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                            }

                            if vm.shotContext.windStrength != .none {
                                LabeledContent("Wind Direction") {
                                    MenuPicker(
                                        selection: $vm.shotContext.windDirection,
                                        options: WindDirection.allCases,
                                        displayName: \.displayName
                                    )
                                }
                            }

                            LabeledContent("Slope / Stance") {
                                MenuPicker(
                                    selection: $vm.shotContext.slope,
                                    options: Slope.allCases,
                                    displayName: \.displayName
                                )
                            }
                        }
                    }

                    // Strategy
                    GroupBox("Strategy") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Aggressiveness", selection: $vm.shotContext.aggressiveness) {
                                ForEach(Aggressiveness.allCases) { a in
                                    Text(a.displayName).tag(a)
                                }
                            }
                            .pickerStyle(.segmented)

                            TextField("Hazard notes (optional)", text: $vm.shotContext.hazardNotes, axis: .vertical)
                                .lineLimit(2...4)
                                .onChange(of: vm.shotContext.hazardNotes) { _, new in
                                    var capped = new
                                    InputGuard.enforceLimit(&capped)
                                    if capped != new { vm.shotContext.hazardNotes = capped }
                                }
                        }
                    }

                    // Action
                    Button {
                        Task {
                            await viewModel.getAdvice(
                                profile: profileStore.profile,
                                historyStore: historyStore
                            )
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 8)
                            }
                            Text(viewModel.isLoading ? "Analyzing..." : "Ask Caddie")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.phase == .loading || viewModel.shotContext.distanceYards <= 0)
                }
                .padding()
            }
            .navigationTitle("Caddie")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.shotContext.shotType) { _, newType in
                // Auto-reconcile lie when shot type changes
                let validLies = newType.validLies
                if !validLies.contains(vm.shotContext.lieType) {
                    vm.shotContext.lieType = newType.defaultLie
                }
            }
            .onChange(of: speechService.transcribedText) { _, newValue in
                if !newValue.isEmpty {
                    viewModel.voiceNotes = newValue
                }
            }
            .onChange(of: speechService.isRecording) { _, isRecording in
                // When recording stops, parse the transcription and auto-fill form fields
                if !isRecording && !speechService.transcribedText.isEmpty {
                    let result = VoiceInputParser.parse(speechService.transcribedText)
                    VoiceInputParser.apply(
                        result,
                        to: &viewModel.shotContext,
                        voiceNotes: &viewModel.voiceNotes
                    )
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                if let newItem {
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            viewModel.selectedImage = uiImage
                        }
                    }
                }
            }
            .onChange(of: viewModel.phase) { _, newPhase in
                if newPhase != .idle && !showingRecommendation {
                    showingRecommendation = true
                }
            }
            .onAppear {
                speechService.requestAuthorization()
            }
            .sheet(isPresented: $showingRecommendation) {
                RecommendationView {
                    showingRecommendation = false
                    viewModel.resetForNewShot()
                    selectedPhotoItem = nil
                }
                .environment(viewModel)
                .environment(profileStore)
                .environment(speechService)
                .environment(historyStore)
                .environment(ttsService)
            }
        }
    }
}

// MARK: - Menu Picker

/// A picker rendered as a `Menu` with a custom trailing label so the chevron
/// aligns at a fixed trailing position, matching adjacent `TextField` controls.
private struct MenuPicker<T: Hashable & Identifiable & CaseIterable>: View
where T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    let options: T.AllCases
    let displayName: KeyPath<T, String>

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(options) { option in
                    Text(option[keyPath: displayName]).tag(option)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(selection[keyPath: displayName])
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Filtered Menu Picker

/// A picker rendered as a `Menu` that accepts an explicit array of options
/// instead of requiring CaseIterable. Used when the available options are
/// filtered based on other state (e.g. valid lies for a shot type).
private struct FilteredMenuPicker<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let options: [T]
    let displayName: KeyPath<T, String>

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(options) { option in
                    Text(option[keyPath: displayName]).tag(option)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(selection[keyPath: displayName])
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Waveform Indicator

private struct WaveformIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.red)
                    .frame(width: 3, height: animate ? CGFloat.random(in: 8...20) : 5)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.1),
                        value: animate
                    )
            }
        }
        .frame(height: 20)
        .onAppear { animate = true }
    }
}

#Preview {
    ShotInputView()
        .environment(ShotAdvisorViewModel())
        .environment(ProfileStore())
        .environment(SpeechRecognitionService())
        .environment(ShotHistoryStore())
        .environment(TextToSpeechService())
        .environment(SubscriptionManager())
}
