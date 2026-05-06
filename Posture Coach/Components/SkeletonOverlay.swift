//
//  SkeletonOverlay.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//

import SwiftUI
import Vision

struct SkeletonOverlay: View {
    let joints: [VNHumanBodyPose3DObservation.JointName: BodyJoint]
    let isBad: Bool

    /// Full 17-joint skeleton — includes spine, centerShoulder, topHead/centerHead, knees, ankles.
    private let connections: [(VNHumanBodyPose3DObservation.JointName, VNHumanBodyPose3DObservation.JointName)] = [
        // Baş
        (.topHead,        .centerHead),
        (.centerHead,     .centerShoulder),
        // Omurga
        (.centerShoulder, .spine),
        (.spine,          .root),
        // Omuzlar
        (.centerShoulder, .leftShoulder),
        (.centerShoulder, .rightShoulder),
        (.leftShoulder,   .rightShoulder),
        // Sol kol
        (.leftShoulder,   .leftElbow),
        (.leftElbow,      .leftWrist),
        // Sağ kol
        (.rightShoulder,  .rightElbow),
        (.rightElbow,     .rightWrist),
        // Kalça
        (.root,           .leftHip),
        (.root,           .rightHip),
        (.leftHip,        .rightHip),
        // Sol bacak
        (.leftHip,        .leftKnee),
        (.leftKnee,       .leftAnkle),
        // Sağ bacak
        (.rightHip,       .rightKnee),
        (.rightKnee,      .rightAnkle),
    ]

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let color: Color = isBad ? .red : .green

                drawReferenceLine(ctx: ctx, size: size, isBad: isBad)

                for (a, b) in connections {
                    guard let j1 = joints[a], let j2 = joints[b] else { continue }
                    var path = Path()
                    path.move(to:    convert(j1.position, size: size))
                    path.addLine(to: convert(j2.position, size: size))
                    ctx.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 2.5)
                }

                for joint in joints.values {
                    let pt   = convert(joint.position, size: size)
                    let rect = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Vertical reference line through centerShoulder — the anatomical midline.
    private func drawReferenceLine(ctx: GraphicsContext, size: CGSize, isBad: Bool) {
        guard let cs = joints[.centerShoulder]?.position else { return }
        let x = convert(cs, size: size).x

        var path = Path()
        path.move(to:    CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))

        let color: Color = isBad ? .red.opacity(0.5) : .white.opacity(0.35)
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
    }

    /// Vision landscape (0,0)=bottom-left of 1280×720 buffer → SwiftUI portrait (0,0)=top-left.
    /// videoOrientation=.landscapeRight: Vision-x maps to screen-y (phone top=high-x=screen top),
    /// Vision-y maps to screen-x (phone left=low-y=screen left).
    private func convert(_ pt: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: pt.y * size.width, y: (1 - pt.x) * size.height)
    }
}
