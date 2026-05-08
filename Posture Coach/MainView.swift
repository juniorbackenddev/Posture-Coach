//
//  MainView.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//
import SwiftUI
import SwiftData
import AVFoundation

struct MainView: View {
    @State private var vm = PostureViewModel()
    @Environment(\.modelContext) private var context
    @State private var showHistory      = false
    @State private var completedSession: PostureSession? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                if vm.isSessionActive || vm.countdownRemaining > 0 {
                    CameraPreview(session: vm.camera.session)
                        .ignoresSafeArea()
                } else {
                    Color(.systemBackground).ignoresSafeArea()
                }

                if vm.isSessionActive, let analysis = vm.currentAnalysis {
                    SkeletonOverlay(joints: analysis.joints, isBad: analysis.isBadPosture)
                        // The preview layer mirrors the front camera (selfie view), but the
                        // pixel buffer passed to Vision is unmirrored. Flip the overlay to match.
                        .scaleEffect(x: vm.camera.position == .front ? -1 : 1, y: 1)
                        .ignoresSafeArea()
                }

                // Countdown overlay
                if vm.countdownRemaining > 0 {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        Text("\(vm.countdownRemaining)")
                            .font(.system(size: 120, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: vm.countdownRemaining)
                    }
                    .ignoresSafeArea()
                }

                VStack {
                    if vm.isSessionActive {
                        PostureStatusCard(analysis: vm.currentAnalysis,
                                          badPercentage: vm.badPosturePercentage)
                            .padding(.horizontal)
                            .padding(.top, 60)
                    }

                    Spacer()

                    if vm.isSessionActive {
                        ActiveSessionPanel(vm: vm, onStop: saveAndStop)
                            .padding()
                    } else if vm.countdownRemaining == 0 {
                        StartPanel(
                            onStart:        { vm.beginWithCountdown() },
                            onHistory:      { showHistory = true },
                            onToggleCamera: { vm.toggleCamera() }
                        )
                        .padding()
                    }
                }
            }
            .sheet(item: $completedSession) { session in
                SessionSummaryView(session: session)
            }
            .navigationDestination(isPresented: $showHistory) {
                HistoryView()
            }
        }
    }

    private func saveAndStop() {
        let session = vm.stopSession()
        context.insert(session)
        try? context.save()
        completedSession = session
    }
}

// MARK: - Alt bileşenler

private struct ActiveSessionPanel: View {
    var vm: PostureViewModel
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(formatted(vm.sessionElapsed), systemImage: "timer")
                Spacer()
                Label(String(format: "%.0f%% kötü", vm.badPosturePercentage),
                      systemImage: "figure.stand")
                    .foregroundStyle(vm.badPosturePercentage > 30 ? .red : .primary)
            }
            .font(.subheadline.monospacedDigit())

            Button(action: onStop) {
                Label("Seansı Bitir", systemImage: "stop.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func formatted(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

private struct StartPanel: View {
    let onStart:        () -> Void
    let onHistory:      () -> Void
    let onToggleCamera: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onStart) {
                Label("Seans Başlat", systemImage: "play.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Button(action: onHistory) {
                    Label("Geçmiş Seanslar", systemImage: "chart.bar.fill")
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button(action: onToggleCamera) {
                    Label("Kamera Değiştir", systemImage: "camera.rotate")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Seans Özeti

struct SessionSummaryView: View {
    let session: PostureSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Text("Seans Tamamlandı")
                .font(.title2.bold())

            HStack(spacing: 40) {
                StatItem(value: formatDuration(session.duration),
                         label: "Süre",
                         icon: "timer")
                StatItem(value: String(format: "%.0f%%", session.badPosturePercentage),
                         label: "Kötü Duruş",
                         icon: "figure.stand",
                         valueColor: session.badPosturePercentage > 40 ? .red : .green)
            }

            if session.dominantErrorType != "Yok" {
                Label("En sık: \(session.dominantErrorType)", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Tamam") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(36)
        .presentationDetents([.medium])
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        String(format: "%dm %02ds", Int(t) / 60, Int(t) % 60)
    }
}

private struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(valueColor)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
