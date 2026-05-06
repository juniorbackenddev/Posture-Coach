//
//  PoseAnalyzer.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//

import Vision
import CoreImage
import CoreGraphics
import simd

// MARK: - Domain types

struct BodyJoint: Identifiable {
    let id = UUID()
    let name: VNHumanBodyPose3DObservation.JointName
    /// Projected 2D position in Vision normalised coordinates (origin bottom-left, 0–1).
    let position: CGPoint
    /// World-space position in metres, root-relative (hip centre = origin).
    let position3D: SIMD3<Float>
}

enum PostureError: String, CaseIterable, Codable {
    case hunched          = "Kambur oturuş"
    case forwardHead      = "Baş öne eğilmiş"
    case roundedShoulders = "Yuvarlak omuzlar"
    case lateralLean      = "Yana eğilme"
}

struct PostureAnalysis {
    let joints: [VNHumanBodyPose3DObservation.JointName: BodyJoint]
    let errors: [PostureError]
    let bodyHeight: Float
    let cameraDistance: Float
    let personCount: Int
    /// Ratio of joints that passed the confidence threshold (0–1). Below ~0.55 means
    /// fewer than ~9 of 17 joints were reliably detected — skeleton display is noisy.
    let detectionQuality: Float

    var isBadPosture: Bool { !errors.isEmpty }
    var primaryError: PostureError? { errors.first }
    var isUnreliable: Bool { detectionQuality < 0.55 }
}

// MARK: - Analyser

private typealias Joints3D = [VNHumanBodyPose3DObservation.JointName: VNHumanBodyRecognizedPoint3D]

final class PoseAnalyzer {
    /// Persistent across frames — VNDetectHumanBodyPose3DRequest requires temporal context.
    private let sequenceHandler = VNSequenceRequestHandler()

    // MARK: - Smoothing
    /// EMA alpha: fraction of the new raw value blended each frame.
    /// 0.35 → 65% old, 35% new — moderate lag-free smoothing.
    private let smoothAlpha: CGFloat = 0.35
    /// Per-joint exponential moving average of the projected 2D position.
    private var smoothed2D: [VNHumanBodyPose3DObservation.JointName: CGPoint] = [:]

    func analyze(sampleBuffer: CMSampleBuffer) -> PostureAnalysis? {
        let req = VNDetectHumanBodyPose3DRequest()
        do {
            // Pass the sample buffer directly so Vision uses the native landscape orientation
            // metadata. ABPKPersonIDTracker requires landscape pixel buffers — do NOT pass
            // an orientation that would cause Vision to rotate to portrait before inference.
            try sequenceHandler.perform([req], on: sampleBuffer)
        } catch {
            return nil
        }

        guard let results = req.results, !results.isEmpty else { return nil }

        // Primary person = closest to camera (largest bodyHeight).
        let obs = results.max(by: { $0.bodyHeight < $1.bodyHeight })!

        let joints = extractJoints(from: obs)
        guard joints.count >= 2 else { return nil }

        let camCol = obs.cameraOriginMatrix.columns.3
        let cameraDistance = simd_length(SIMD3<Float>(camCol.x, camCol.y, camCol.z))
        let quality = Float(joints.count) / 17.0

        return PostureAnalysis(
            joints: joints,
            errors: evaluatePosture(from: obs),
            bodyHeight: obs.bodyHeight,
            cameraDistance: cameraDistance,
            personCount: results.count,
            detectionQuality: quality
        )
    }
    
    func flushEMAHistory() {
            smoothed2D.removeAll()
        }

    // MARK: - Joint extraction

    /// Fetches all 17 joints, filters by confidence, then applies per-joint EMA smoothing
    /// to the projected 2D position so the skeleton doesn't jump on noisy frames.
    // MARK: - Joint extraction
        private func extractJoints(
            from obs: VNHumanBodyPose3DObservation
        ) -> [VNHumanBodyPose3DObservation.JointName: BodyJoint] {
            let all: Joints3D = (try? obs.recognizedPoints(.all)) ?? [:]
            var result: [VNHumanBodyPose3DObservation.JointName: BodyJoint] = [:]

            for (name, pt) in all {
                // Hatalı confidence satırını sildik! 3D modelde confidence per-joint verilmiyor.
                
                guard let vnPt = try? obs.pointInImage(name) else { continue }
                var raw = CGPoint(x: vnPt.x, y: vnPt.y)
                
                // 1. Outlier Rejection (Clamp): Nokta bir karede çok fazla uçtu mu?
                if let prev = smoothed2D[name] {
                                let dx = raw.x - prev.x
                                let dy = raw.y - prev.y
                                let distance = sqrt(dx*dx + dy*dy)
                                
                                let maxJump: CGFloat = 0.15 // %15'lik sınır
                                
                                if distance > maxJump {
                                    // İŞTE DÜZELTME BURASI:
                                    // Yönelim vermek yerine, saçmalayan veriyi tamamen reddet.
                                    // Noktayı son bilinen güvenli yerinde (prev) bırak!
                                    raw = prev
                                }
                            }
                // 2. EMA Filtresi
                let prev = smoothed2D[name] ?? raw
                let s = CGPoint(
                    x: smoothAlpha * raw.x + (1 - smoothAlpha) * prev.x,
                    y: smoothAlpha * raw.y + (1 - smoothAlpha) * prev.y
                )
                smoothed2D[name] = s

                result[name] = BodyJoint(name: name, position: s, position3D: worldPos(pt))
            }
            return result
        }

    // MARK: - 3D posture analysis (metres, bodyHeight-adaptive)

    private func evaluatePosture(from obs: VNHumanBodyPose3DObservation) -> [PostureError] {
        let bh = obs.bodyHeight
        var errors: [PostureError] = []

        // Batch-fetch by body region using JointsGroupName.
        let torso = (try? obs.recognizedPoints(.torso))    ?? [:]
        let lArm  = (try? obs.recognizedPoints(.leftArm))  ?? [:]
        let rArm  = (try? obs.recognizedPoints(.rightArm)) ?? [:]

        // 1. Spine lean — angle of root→centerShoulder from vertical Y axis.
        if let r = torso[.root], let cs = torso[.centerShoulder] {
            let vec = worldPos(cs) - worldPos(r)
            let len = simd_length(vec)
            if len > 0.1 {
                let tilt = acos(min(abs(vec.y) / len, 1.0)) * (180 / Float.pi)
                if tilt > 20 { errors.appendIfAbsent(.hunched) }
            }
        }

        // 2. Lateral lean — X offset between root and centerShoulder, bh-scaled.
        if let r = torso[.root], let cs = torso[.centerShoulder] {
            if abs(worldPos(cs).x - worldPos(r).x) > bh * 0.06 {
                errors.appendIfAbsent(.lateralLean)
            }
        }

        // 3. Rounded shoulders — both shoulders displaced forward (+Z) vs centerShoulder.
        if let cs = torso[.centerShoulder],
           let ls = lArm[.leftShoulder],
           let rs = rArm[.rightShoulder] {
            let csZ = worldPos(cs).z
            if worldPos(ls).z - csZ > bh * 0.04 &&
               worldPos(rs).z - csZ > bh * 0.04 {
                errors.appendIfAbsent(.roundedShoulders)
            }
        }

        return errors
    }

    // MARK: - Helpers

    private func worldPos(_ p: VNHumanBodyRecognizedPoint3D) -> SIMD3<Float> {
        let c = p.position.columns.3
        return SIMD3<Float>(c.x, c.y, c.z)
    }
}

private extension Array where Element == PostureError {
    mutating func appendIfAbsent(_ error: PostureError) {
        if !contains(error) { append(error) }
    }
}
