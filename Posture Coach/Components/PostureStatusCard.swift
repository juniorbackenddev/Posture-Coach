//
//  PostureStatusCard.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//

import SwiftUI

struct PostureStatusCard: View {
    let analysis: PostureAnalysis?
    let badPercentage: Double

    private var isBad: Bool     { analysis?.isBadPosture == true }
    private var isDetected: Bool { analysis != nil }
    private var errors: [PostureError] { analysis?.errors ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Status row
            HStack(spacing: 10) {
                Image(systemName: isDetected
                      ? (isBad ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                      : "person.slash.fill")
                    .font(.title3)
                    .foregroundStyle(isDetected ? (isBad ? .red : .green) : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isDetected
                         ? (isBad ? (analysis?.primaryError?.rawValue ?? "Kötü duruş") : "İyi duruş")
                         : "Kişi algılanmadı")
                        .font(.subheadline.bold())

                    Text(String(format: "Seans kötü duruş: %.0f%%", badPercentage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Metrics badges
                HStack(spacing: 6) {
                    if let bh = analysis?.bodyHeight {
                        Badge(text: String(format: "%.2fm", bh), color: .blue)
                    }
                    if let dist = analysis?.cameraDistance {
                        Badge(text: String(format: "%.1fm", dist), color: .purple)
                    }
                    if let count = analysis?.personCount, count > 1 {
                        Badge(text: "\(count) kişi", color: .orange)
                    }
                }
            }

            // Low-confidence warning — shown when fewer than ~9/17 joints passed the threshold
            if analysis?.isUnreliable == true {
                Label("Algılama zayıf — tüm vücudun görünür olduğundan emin ol",
                      systemImage: "eye.trianglebadge.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            // All active errors as chips (only when there are multiple)
            if errors.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(errors, id: \.self) { error in
                            Text(error.rawValue)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Badge

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
