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
    @State private var showingRecommendation = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        @Bindable var vm = viewModel

        NavigationStack {
            Form {
                // Voice & Image Input
                Section("Quick Input") {
                    // Voice recording
                    HStack {
                        Button {
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

                        // Photo picker
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

                    // Voice transcription / notes
                    if !speechService.transcribedText.isEmpty || !vm.voiceNotes.isEmpty {
                        TextField("Voice notes", text: $vm.voiceNotes, axis: .vertical)
                            .lineLimit(2...4)
                    }

                    // Image thumbnail
                    if let image = viewModel.selectedImage {
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

                // Distance & Shot Type
                Section("Shot Setup") {
                    HStack {
                        Text("Distance (yards)")
                        Spacer()
                        TextField("150", value: $vm.shotContext.distanceYards, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Picker("Shot Type", selection: $vm.shotContext.shotType) {
                        ForEach(ShotType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                // Conditions
                Section("Conditions") {
                    Picker("Lie", selection: $vm.shotContext.lieType) {
                        ForEach(LieType.allCases) { lie in
                            Text(lie.displayName).tag(lie)
                        }
                    }
                    Picker("Wind", selection: $vm.shotContext.windStrength) {
                        ForEach(WindStrength.allCases) { w in
                            Text(w.displayName).tag(w)
                        }
                    }
                    if vm.shotContext.windStrength != .none {
                        Picker("Wind Direction", selection: $vm.shotContext.windDirection) {
                            ForEach(WindDirection.allCases) { d in
                                Text(d.displayName).tag(d)
                            }
                        }
                    }
                    Picker("Slope / Stance", selection: $vm.shotContext.slope) {
                        ForEach(Slope.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                }

                // Strategy
                Section("Strategy") {
                    Picker("Aggressiveness", selection: $vm.shotContext.aggressiveness) {
                        ForEach(Aggressiveness.allCases) { a in
                            Text(a.displayName).tag(a)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Hazard notes (optional)", text: $vm.shotContext.hazardNotes, axis: .vertical)
                        .lineLimit(2...4)
                }

                // Action
                Section {
                    Button {
                        Task {
                            await viewModel.getAdvice(
                                profile: profileStore.profile,
                                historyStore: historyStore
                            )
                            if viewModel.recommendation != nil {
                                showingRecommendation = true
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(viewModel.isLoading ? "Analyzing..." : "Get Advice")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.shotContext.distanceYards <= 0)
                }
            }
            .navigationTitle("Caddie")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: speechService.transcribedText) { _, newValue in
                if !newValue.isEmpty {
                    viewModel.voiceNotes = newValue
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
            .onAppear {
                speechService.requestAuthorization()
            }
            .sheet(isPresented: $showingRecommendation) {
                if let rec = viewModel.recommendation {
                    RecommendationView(
                        recommendation: rec,
                        analysis: viewModel.deterministicAnalysis,
                        errorMessage: viewModel.errorMessage
                    ) {
                        showingRecommendation = false
                        viewModel.resetForNewShot()
                        selectedPhotoItem = nil
                    }
                }
            }
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
}
