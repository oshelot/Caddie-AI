//
//  CourseIngestionView.swift
//  CaddieAI
//
//  Loading progress sheet displayed during course ingestion.
//

import SwiftUI

struct CourseIngestionView: View {
    @Environment(CourseViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 24) {
            if let error = viewModel.ingestionError {
                // Error state
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                Text("Ingestion Failed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Dismiss") {
                    viewModel.ingestionError = nil
                }
                .buttonStyle(.borderedProminent)

            } else if let warning = viewModel.ingestionWarning {
                // Completed with warning (sparse data)
                Image(systemName: "map.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Limited Course Data")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(warning)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("View Satellite Map") {
                    viewModel.ingestionWarning = nil
                }
                .buttonStyle(.borderedProminent)

            } else {
                // Loading state
                ProgressView()
                    .controlSize(.large)

                Text(viewModel.ingestionStep)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Fetching course data from OpenStreetMap")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button("Cancel", role: .cancel) {
                    viewModel.cancelIngestion()
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
        }
        .padding(40)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
