//
//  CameraPreview.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//
                      
#if canImport(UIKit)
import UIKit
import AVFoundation
import SwiftUI
                                                                                                                    
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
                                                                                                                      
    func makeUIView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
                                                                                                                      
    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }                         
                                                                                                                      
        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            previewLayer.session     = session
            previewLayer.videoGravity = .resizeAspectFill
        }
        required init?(coder: NSCoder) { fatalError() }
    }
}
#else
import AppKit
import AVFoundation
import SwiftUI
                                                                                                                      
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
                                                                                                                      
    class PreviewView: NSView {
        private let previewLayer = AVCaptureVideoPreviewLayer()
                                                                                                                      
        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            wantsLayer              = true
            layer                  = previewLayer
            previewLayer.session    = session
            previewLayer.videoGravity = .resizeAspectFill
        }
        required init?(coder: NSCoder) { fatalError() }
    }
}
#endif
       
