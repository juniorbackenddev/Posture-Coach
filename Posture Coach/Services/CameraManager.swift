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
    var onFrame: ((CMSampleBuffer) -> Void)?
    private(set) var position: AVCaptureDevice.Position = .front

    private let queue = DispatchQueue(label: "posture.camera", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()

    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted  { self?.setupAndStart()}
            }
        default:
            break
        }
    }
    
    func stop() {
        session.stopRunning()
    }
    func switchCamera() {
            position = (position == .front) ? .back : .front

            queue.async {
                // 1. Race condition'ı önlemek için sistemi durdur
                self.session.stopRunning()
                self.session.beginConfiguration()

                // Swap the video input
                for input in self.session.inputs where (input as? AVCaptureDeviceInput) != nil {
                    self.session.removeInput(input)
                }
                guard
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.position),
                    let input  = try? AVCaptureDeviceInput(device: device),
                    self.session.canAddInput(input)
                else {
                    self.session.commitConfiguration()
                    self.session.startRunning() // Hata olsa bile geri başlat
                    return
                }
                self.session.addInput(input)

                #if os(iOS)
                if let conn = self.videoOutput.connection(with: .video) {
                    
                    // İŞTE DÜZELTİLEN KISIM BURASI (iOS 17 kontrolü)
                    if #available(iOS 17.0, *) {
                        if conn.isVideoRotationAngleSupported(0.0) {
                            conn.videoRotationAngle = 0.0
                        }
                    } else {
                        if conn.isVideoOrientationSupported {
                            conn.videoOrientation = .landscapeRight
                        }
                    }
                    
                    // 2. Ön kamera için ayna efektini aç (sağ/sol karışmaması için)
                    if self.position == .front && conn.isVideoMirroringSupported {
                        conn.isVideoMirrored = true
                    }
                    
                    if conn.isCameraIntrinsicMatrixDeliverySupported {
                        conn.isCameraIntrinsicMatrixDeliveryEnabled = true
                    }
                }
                #endif

                self.session.commitConfiguration()
                // 3. Güvenli bir şekilde yeniden başlat
                self.session.startRunning()
            }
        }
    
    
    private func setupAndStart() {
        // İlk çağrıda konfigüre et, sonrasında sadece başlat
        if session.inputs.isEmpty {
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            videoOutput.setSampleBufferDelegate(self, queue: queue)

            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

#if os(iOS)
            if let conn = self.videoOutput.connection(with: .video) {
                
                // 1. Yönlendirme (iOS 17+ ve Eski Sürümler İçin)
                if #available(iOS 17.0, *) {
                    // DÜZELTME BURADA: contains yerine isVideoRotationAngleSupported fonksiyonunu kullanıyoruz
                    if conn.isVideoRotationAngleSupported(0.0) {
                        conn.videoRotationAngle = 0.0
                    }
                } else {
                    // iOS 16 ve öncesi: Eski yöntem
                    if conn.isVideoOrientationSupported {
                        conn.videoOrientation = .landscapeRight
                    }
                }
                
                // 2. Ön kamera için ayna efektini aç (Sadece ön kameradaysa)
                if self.position == .front && conn.isVideoMirroringSupported {
                    conn.isVideoMirrored = true
                }
                
                // 3. 3D Pose için derinlik matrisi
                if conn.isCameraIntrinsicMatrixDeliverySupported {
                    conn.isCameraIntrinsicMatrixDeliveryEnabled = true
                }
            }
            #endif

            session.commitConfiguration()
        }

        guard !session.isRunning else { return }
        queue.async { self.session.startRunning() }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }
}
