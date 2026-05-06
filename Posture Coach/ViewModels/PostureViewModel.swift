//
//  PostureViewModel.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//

import SwiftUI
import Vision
import simd

@Observable
@MainActor
final class PostureViewModel {
    var currentAnalysis: PostureAnalysis?
    var isSessionActive = false
    var sessionElapsed: TimeInterval = 0

    private(set) var badFrameCount = 0
    private(set) var totalFrameCount = 0

    var badPosturePercentage: Double {
        guard totalFrameCount > 0 else { return 0 }
        return Double(badFrameCount) / Double(totalFrameCount) * 100
    }

    let camera = CameraManager()
    let analyzer = PoseAnalyzer()

    private var sessionStart: Date?
    private var lastWarningDate: Date?
    private var elapsedTask: Task<Void, Never>?
    private var consecutiveBadFrames = 0

    private let badFrameThreshold = 4
    private let warningCooldown: TimeInterval = 8

    init() {
        camera.onFrame = { [weak self] buffer in
            guard let self else { return }
            guard let analysis = self.analyzer.analyze(sampleBuffer: buffer) else { return }
            Task { @MainActor in self.handleAnalysis(analysis) }
        }
    }

    // MARK: - Session

    func startSession() {
        isSessionActive     = true
        sessionStart        = .now
        sessionElapsed      = 0
        badFrameCount       = 0
        totalFrameCount     = 0
        lastWarningDate     = nil
        currentAnalysis     = nil
        consecutiveBadFrames = 0
        HapticManager.shared.sessionTap()

        elapsedTask = Task { @MainActor in
            while isSessionActive {
                try? await Task.sleep(for: .seconds(1))
                guard isSessionActive else { break }
                sessionElapsed = Date.now.timeIntervalSince(sessionStart ?? .now)
            }
        }
        camera.requestPermissionAndStart()
    }

    func stopSession() -> PostureSession {
        isSessionActive = false
        elapsedTask?.cancel()
        elapsedTask = nil
        camera.stop()

        let duration = Date.now.timeIntervalSince(sessionStart ?? .now)
        return PostureSession(
            duration: duration,
            badPosturePercentage: badPosturePercentage,
            dominantErrorType: currentAnalysis?.primaryError?.rawValue ?? "Yok"
        )
    }

    func toggleCamera() {
            camera.switchCamera()
            analyzer.flushEMAHistory() 
        }

    // MARK: - Private

    private func handleAnalysis(_ analysis: PostureAnalysis) {
        guard isSessionActive else { return }

        currentAnalysis  = analysis
        totalFrameCount += 1

        if analysis.isBadPosture {
            consecutiveBadFrames += 1
            if consecutiveBadFrames >= badFrameThreshold {
                badFrameCount += 1
                triggerWarningIfNeeded()
            }
        } else {
            consecutiveBadFrames = 0
        }
    }

    private func triggerWarningIfNeeded() {
        let now = Date.now
        if let last = lastWarningDate, now.timeIntervalSince(last) < warningCooldown { return }
        lastWarningDate = now
        HapticManager.shared.postureWarning()
    }
}
