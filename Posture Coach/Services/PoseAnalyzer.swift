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
    case facingSideways   = "Kameraya dön"
}

struct PostureAnalysis {
    let joints: [VNHumanBodyPose3DObservation.JointName: BodyJoint]
    let errors: [PostureError]
    let bodyHeight: Float
    let cameraDistance: Float
    let personCount: Int
    /// Fraction of 17 joints successfully detected (0–1).
    /// Below ~0.55 means fewer than ~9 joints were found — skeleton display is noisy.
    let detectionQuality: Float

    var isBadPosture: Bool { !errors.isEmpty }
    var primaryError: PostureError? { errors.first }
    var isUnreliable: Bool { detectionQuality < 0.55 }
}

// MARK: - Analyser

private typealias Joints3D = [VNHumanBodyPose3DObservation.JointName: VNHumanBodyRecognizedPoint3D]

final class PoseAnalyzer {
    private let sequenceHandler = VNSequenceRequestHandler()
    // VNDetectHumanBodyPose3DRequest is a VNStatefulRequest subclass — its temporal
    // context lives inside the request object. Creating a new instance each frame
    // resets that context, degrading 3D accuracy. Reuse the same instance across frames;
    // recreate only when starting a new session (flushEMAHistory).
    private var poseRequest = VNDetectHumanBodyPose3DRequest()

    // MARK: - Smoothing

    /// EMA alpha: 0.55 → 45% old value retained each frame. Higher = more responsive.
    private let smoothAlpha: CGFloat = 0.55
    /// Per-joint exponential moving average of the projected 2D screen position.
    private var smoothed2D: [VNHumanBodyPose3DObservation.JointName: CGPoint] = [:]

    func flushEMAHistory() {
        smoothed2D.removeAll()
        poseRequest = VNDetectHumanBodyPose3DRequest()
    }

    // MARK: - Analysis entry point

    func analyze(sampleBuffer: CMSampleBuffer) -> PostureAnalysis? {
        do {
            // Pass the sample buffer directly so Vision uses the native landscape orientation
            // metadata set by videoOrientation = .landscapeRight on the capture connection.
            try sequenceHandler.perform([poseRequest], on: sampleBuffer)
        } catch {
            return nil
        }

        guard let results = poseRequest.results, !results.isEmpty else { return nil }
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

    // MARK: - Joint extraction

    private func extractJoints(
        from obs: VNHumanBodyPose3DObservation
    ) -> [VNHumanBodyPose3DObservation.JointName: BodyJoint] {
        let all: Joints3D = (try? obs.recognizedPoints(.all)) ?? [:]
        var result: [VNHumanBodyPose3DObservation.JointName: BodyJoint] = [:]

        for (name, pt) in all {
            guard let vnPt = try? obs.pointInImage(name) else { continue }

            var raw = CGPoint(x: vnPt.x, y: vnPt.y)

            // Outlier rejection: if joint jumps > 25% of frame in one frame, freeze it.
            if let prev = smoothed2D[name] {
                let dist = hypot(raw.x - prev.x, raw.y - prev.y)
                if dist > 0.35 { raw = prev }
            }

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

    // MARK: - 3D posture evaluation (all distances bodyHeight-adaptive)

    private func evaluatePosture(from obs: VNHumanBodyPose3DObservation) -> [PostureError] {
        let bh = obs.bodyHeight
        var errors: [PostureError] = []

        let torso = (try? obs.recognizedPoints(.torso))    ?? [:]
        let headG = (try? obs.recognizedPoints(.head))     ?? [:]
        let lArm  = (try? obs.recognizedPoints(.leftArm))  ?? [:]
        let rArm  = (try? obs.recognizedPoints(.rightArm)) ?? [:]

        // 1. Spine tilt (any direction) — angle of root→centerShoulder from vertical Y.
        // 1b. Dedicated forward Z-lean — +Z points toward the camera in Vision space;
        //     a positive ratio means the shoulders are closer to the camera than the hips.
        if let r = torso[.root], let cs = torso[.centerShoulder] {
            let vec = worldPos(cs) - worldPos(r)
            let len = simd_length(vec)
            if len > 0.1 {
                let tilt = acos(min(abs(vec.y) / len, 1.0)) * (180 / Float.pi)
                if tilt > 20 { errors.appendIfAbsent(.hunched) }
                if vec.z / len > 0.20 { errors.appendIfAbsent(.hunched) }
            }
        }

        // 1c. Head–shoulder–root angle: the angle at centerShoulder in the
        //     head→shoulder←root triangle. Upright ≈ 170–180°; hunching narrows it.
        //     Root is the origin in root-relative space so worldPos(r) ≈ (0,0,0).
        if let hd = headG[.centerHead],
           let cs = torso[.centerShoulder],
           let r  = torso[.root] {
            let toHead = worldPos(hd) - worldPos(cs)
            let toRoot = worldPos(r)  - worldPos(cs)
            let lh = simd_length(toHead), lr = simd_length(toRoot)
            if lh > 0.05 && lr > 0.05 {
                let dot   = simd_dot(toHead / lh, toRoot / lr)
                let angle = acos(min(max(dot, -1), 1)) * (180 / Float.pi)
                if angle < 155 { errors.appendIfAbsent(.hunched) }
            }
        }

        // 2. Lateral lean — shoulder centre X offset from hip centre > 6% of bodyHeight.
        if let r = torso[.root], let cs = torso[.centerShoulder] {
            if abs(worldPos(cs).x - worldPos(r).x) > bh * 0.06 {
                errors.appendIfAbsent(.lateralLean)
            }
        }

        // 3. Sideways to camera — left/right shoulder X-span collapses when person shows
        //    a profile view. Normal frontal width ≈ 25–35% of bodyHeight; < 12% = side-on.
        if let ls = lArm[.leftShoulder], let rs = rArm[.rightShoulder] {
            if abs(worldPos(ls).x - worldPos(rs).x) < bh * 0.12 {
                errors.appendIfAbsent(.facingSideways)
            }
        }

        // 4. Shoulder protraction — both shoulders sit in front of the spine joint in Z.
        //    Using the spine (mid-back) as reference avoids the false-negative that occurs
        //    when centerShoulder itself moves forward during hunching and erases the offset.
        if let sp = torso[.spine],
           let ls = lArm[.leftShoulder],
           let rs = rArm[.rightShoulder] {
            let spZ = worldPos(sp).z
            if worldPos(ls).z - spZ > bh * 0.08 &&
               worldPos(rs).z - spZ > bh * 0.08 {
                errors.appendIfAbsent(.roundedShoulders)
            }
        }

        // 5. Sagittal spine angle (kyphosis) — project the lower-spine vector
        //    (root→spine) and upper-spine vector (spine→centerShoulder) onto the Y-Z
        //    (sagittal) plane and measure the bend angle between them. Upright posture
        //    keeps both segments nearly parallel (angle ≈ 0°); a rounded upper back
        //    tilts the upper segment forward (+Z), opening the angle.
        if let r  = torso[.root],
           let sp = torso[.spine],
           let cs = torso[.centerShoulder] {
            let lower = worldPos(sp) - worldPos(r)
            let upper = worldPos(cs) - worldPos(sp)
            let lYZ = SIMD2<Float>(lower.y, lower.z)
            let uYZ = SIMD2<Float>(upper.y, upper.z)
            let ll = simd_length(lYZ), lu = simd_length(uYZ)
            if ll > 0.05 && lu > 0.05 {
                let dot   = simd_dot(lYZ / ll, uYZ / lu)
                let angle = acos(min(max(dot, -1), 1)) * (180 / Float.pi)
                if angle > 15 { errors.appendIfAbsent(.hunched) }
            }
        }

        // 5b. Spine-bow Z fallback — catches seated slouch where the sagittal angle
        //     is too shallow to cross the geometric threshold: centerShoulder rolling
        //     forward while the spine joint stays back creates a direct Z gap.
        if let sp = torso[.spine], let cs = torso[.centerShoulder] {
            if worldPos(cs).z - worldPos(sp).z > bh * 0.06 {
                errors.appendIfAbsent(.hunched)
            }
        }

        // 6. Forward head — head Z leads the mean of both shoulder joints in Z.
        //    Using the shoulder mean (rather than centerShoulder) is more stable and
        //    directly captures the depth gap between the face and the shoulder plane.
        if let hd = headG[.centerHead],
           let ls = lArm[.leftShoulder],
           let rs = rArm[.rightShoulder] {
            let shoulderZ = (worldPos(ls).z + worldPos(rs).z) * 0.5
            if worldPos(hd).z - shoulderZ > bh * 0.08 {
                errors.appendIfAbsent(.forwardHead)
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
