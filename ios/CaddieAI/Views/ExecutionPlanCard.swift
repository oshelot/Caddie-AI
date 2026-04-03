//
//  ExecutionPlanCard.swift
//  CaddieAI
//

import SwiftUI

struct ExecutionPlanCard: View {
    let plan: ExecutionPlan
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "figure.golf")
                        .foregroundStyle(.blue)
                    Text("How to Hit It")
                        .font(.headline)
                    Spacer()
                    Text(plan.archetype.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    // Setup Summary
                    Text(plan.setupSummary)
                        .font(.body)
                        .fontWeight(.medium)

                    // Setup details grid
                    VStack(alignment: .leading, spacing: 10) {
                        ExecutionRow(icon: "circle.fill", label: "Ball Position", value: plan.ballPosition)
                        ExecutionRow(icon: "scalemass", label: "Weight", value: plan.weightDistribution)
                        ExecutionRow(icon: "arrow.left.and.right", label: "Stance", value: plan.stanceWidth)
                        ExecutionRow(icon: "arrow.up.forward", label: "Alignment", value: plan.alignment)
                        ExecutionRow(icon: "rectangle.portrait.rotate", label: "Clubface", value: plan.clubface)
                        ExecutionRow(icon: "arrow.up.to.line", label: "Shaft Lean", value: plan.shaftLean)
                    }

                    Divider()

                    // Swing details
                    VStack(alignment: .leading, spacing: 10) {
                        ExecutionRow(icon: "arrow.turn.up.left", label: "Backswing", value: plan.backswingLength)
                        ExecutionRow(icon: "arrow.turn.up.right", label: "Finish", value: plan.followThrough)
                        ExecutionRow(icon: "metronome", label: "Tempo", value: plan.tempo)
                        ExecutionRow(icon: "target", label: "Strike", value: plan.strikeIntention)
                    }

                    // Mistake to avoid
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red.opacity(0.8))
                            .font(.callout)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avoid")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(plan.mistakeToAvoid)
                                .font(.callout)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Execution Row

private struct ExecutionRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue.opacity(0.7))
                .font(.caption)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
            }
        }
    }
}

// MARK: - Previews

#Preview {
    ScrollView {
        ExecutionPlanCard(plan: .mock)
            .padding()
    }
}
