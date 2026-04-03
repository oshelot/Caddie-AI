//
//  SwingInfoView.swift
//  CaddieAI
//
//  Profile detail page for editing per-category stock shapes and tendencies.
//

import SwiftUI

struct SwingInfoView: View {
    @Environment(ProfileStore.self) private var profileStore

    var body: some View {
        @Bindable var store = profileStore

        Form {
            Section("Shot Shape") {
                Picker("Woods", selection: $store.profile.woodsStockShape) {
                    ForEach(StockShape.allCases) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
                Picker("Irons", selection: $store.profile.ironsStockShape) {
                    ForEach(StockShape.allCases) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
                Picker("Hybrids", selection: $store.profile.hybridsStockShape) {
                    ForEach(StockShape.allCases) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
            }

            Section("Tendencies") {
                Picker("Miss Tendency", selection: $store.profile.missTendency) {
                    ForEach(MissTendency.allCases) { miss in
                        Text(miss.displayName).tag(miss)
                    }
                }
                Picker("Bunker Confidence", selection: $store.profile.bunkerConfidence) {
                    ForEach(SelfConfidence.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                Picker("Wedge Confidence", selection: $store.profile.wedgeConfidence) {
                    ForEach(SelfConfidence.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                Picker("Preferred Chip Style", selection: $store.profile.preferredChipStyle) {
                    ForEach(ChipStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Picker("Swing Tendency", selection: $store.profile.swingTendency) {
                    ForEach(SwingTendency.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
            }
        }
        .navigationTitle("Swing Info")
    }
}

#Preview {
    NavigationStack {
        SwingInfoView()
            .environment(ProfileStore())
    }
}
