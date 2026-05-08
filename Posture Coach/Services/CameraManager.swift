//
//  CameraManager.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//

import Foundation
import AVFoundation

final class CameraManager: NSObject {
    let session = AVCaptureSession()
    nonisolated(unsafe) var onFrame: ((CMSampleBuffer) -> Void)?
    private(set) var position: AVCaptureDevice.Position = .front

    private let queue = DispatchQueue(label: "posture.camera", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()

    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.setupAndStart() }
            }
        default:
            break
        }
    }

    func stop() {
        // Dispatch on the same queue as setupAndStart so stop always runs after any
        // pending start, eliminating the race where the session restarts after stop.
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func switchCamera() {
        position = (position == .front) ? .back : .front
        // Session not running → position is stored; next setupAndStart() picks it up.
        guard session.isRunning else { return }
        queue.async { self.reconfigureInput() }
    }

    // MARK: - Private

    private func setupAndStart() {
        queue.async {
            // Add the output exactly once.
            if !self.session.outputs.contains(where: { $0 === self.videoOutput }) {
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1280x720
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }
                self.session.commitConfiguration()
            }

            // Always reconfigure the input so a pre-session camera toggle takes effect.
            self.reconfigureInput()

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    /// Swaps the active video input to match self.position.
    /// Called on self.queue. Safe on both running and stopped sessions.
    private func reconfigureInput() {
        session.beginConfiguration()
        session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.forEach { session.removeInput($0) }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        // Commit BEFORE querying the connection — AVFoundation only creates the
        // input→output connection object after commitConfiguration(), so querying
        // videoOutput.connection(with:) inside an open beginConfiguration() block
        // always returns nil and the orientation / intrinsics are never applied.
        session.commitConfiguration()

        // Lock to 30 fps — Vision's 3D pose model can exceed 33 ms/frame on slower
        // devices, so without this the session drops to irregular rates. Both min and
        // max are set so the device doesn't boost above 30 either.
        try? device.lockForConfiguration()
        let fps30 = CMTime(value: 1, timescale: 30)
        device.activeVideoMinFrameDuration = fps30
        device.activeVideoMaxFrameDuration = fps30
        device.unlockForConfiguration()

        #if os(iOS)
        if let conn = videoOutput.connection(with: .video) {
            // VNDetectHumanBodyPose3DRequest requires landscape pixel buffers.
            // videoRotationAngle=0 (iOS 17+) or videoOrientation=.landscapeRight keeps
            // the native sensor landscape orientation without rotating to portrait.
            // Do NOT set isVideoMirrored on the data output — that swaps left/right
            // joints in the pixel buffer and confuses the 3D pose model.
            if #available(iOS 17.0, *) {
                conn.videoRotationAngle = 0
            } else {
                if conn.isVideoOrientationSupported { conn.videoOrientation = .landscapeRight }
            }
            if conn.isCameraIntrinsicMatrixDeliverySupported {
                conn.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }
        #endif
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }
}
