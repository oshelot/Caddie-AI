//
//  ClubDistanceEditor.swift
//  CaddieAI
//

import SwiftUI

struct ClubDistanceEditor: View {
    @Binding var clubDistances: [ClubDistance]

    var body: some View {
        ForEach($clubDistances) { $clubDistance in
            HStack {
                Text(clubDistance.club.displayName)
                    .frame(width: 130, alignment: .leading)
                Spacer()
                TextField("yards", value: $clubDistance.carryYards, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("yds")
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            }
        }
    }
}

#Preview {
    @Previewable @State var distances = Club.shotClubs.map {
        ClubDistance(club: $0, carryYards: $0.defaultCarryYards)
    }
    List {
        ClubDistanceEditor(clubDistances: $distances)
    }
}
