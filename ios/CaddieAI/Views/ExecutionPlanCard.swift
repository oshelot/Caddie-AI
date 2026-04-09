//
//  ExecutionPlanCard.swift
//  CaddieAI
//

import SwiftUI

// MARK: - Execution Row (shared by both card variants)

struct ExecutionRow: View {
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

// MARK: - Progressive Execution Plan Card

/// Reveals execution plan fields one-by-one with staggered animation,
/// creating a "streaming" feel even though the data arrives all at once.
struct ProgressiveExecutionPlanCard: View {
    let plan: ExecutionPlan

    @State private var visibleFieldCount: Int = 0

    private static let totalFields = 13
    private static let revealInterval: Duration = .milliseconds(120)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            HStack {
                Image(systemName: "figure.golf")
                    .foregroundStyle(.blue)
                Text("How to Hit It")
                    .font(.headline)
                Spacer()
                Text(plan.archetype.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 16) {
                // Setup Summary
                if visibleFieldCount >= 1 {
                    Text(plan.setupSummary)
                        .font(.body)
                        .fontWeight(.medium)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }

                // Setup details
                VStack(alignment: .leading, spacing: 10) {
                    revealableRow(index: 2, icon: "circle.fill", label: "Ball Position", value: plan.ballPosition)
                    revealableRow(index: 3, icon: "scalemass", label: "Weight", value: plan.weightDistribution)
                    revealableRow(index: 4, icon: "arrow.left.and.right", label: "Stance", value: plan.stanceWidth)
                    revealableRow(index: 5, icon: "arrow.up.forward", label: "Alignment", value: plan.alignment)
                    revealableRow(index: 6, icon: "rectangle.portrait.rotate", label: "Clubface", value: plan.clubface)
                    revealableRow(index: 7, icon: "arrow.up.to.line", label: "Shaft Lean", value: plan.shaftLean)
                }

                if visibleFieldCount >= 8 {
                    Divider()
                        .transition(.opacity)
                }

                // Swing details
                VStack(alignment: .leading, spacing: 10) {
                    revealableRow(index: 8, icon: "arrow.turn.up.left", label: "Backswing", value: plan.backswingLength)
                    revealableRow(index: 9, icon: "arrow.turn.up.right", label: "Finish", value: plan.followThrough)
                    revealableRow(index: 10, icon: "metronome", label: "Tempo", value: plan.tempo)
                    revealableRow(index: 11, icon: "target", label: "Strike", value: plan.strikeIntention)
                }

                // Mistake to avoid
                if visibleFieldCount >= 12 {
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
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }

                // Swing thought (final element, highlighted)
                if visibleFieldCount >= 13 {
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text(plan.swingThought)
                            .font(.title3)
                            .italic()
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding()
            .animation(.easeOut(duration: 0.25), value: visibleFieldCount)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await revealFields()
        }
    }

    @ViewBuilder
    private func revealableRow(index: Int, icon: String, label: String, value: String) -> some View {
        if visibleFieldCount >= index {
            ExecutionRow(icon: icon, label: label, value: value)
                .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }

    private func revealFields() async {
        for i in 1...Self.totalFields {
            try? await Task.sleep(for: Self.revealInterval)
            withAnimation {
                visibleFieldCount = i
            }
        }
    }
}

// MARK: - Original Execution Plan Card (kept for non-animated use)

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

// MARK: - Previews

#Preview("Progressive") {
    ScrollView {
        ProgressiveExecutionPlanCard(plan: .mock)
            .padding()
    }
}

#Preview("Static") {
    ScrollView {
        ExecutionPlanCard(plan: .mock)
            .padding()
    }
}
