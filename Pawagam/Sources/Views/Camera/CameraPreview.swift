//
//  CameraPreview.swift
//  Pawagam
//
//  Created by Khai Yuan Yap on 19/06/2025.
//

import AVFoundation
import Accelerate
import Combine
import Photos
import SwiftUI
import UniformTypeIdentifiers
import MobileCoreServices
import Metal
import MetalKit
import MetalPerformanceShaders

// Camera Preview UIViewRepresentable
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
        var focusAction: ((CGPoint) -> Void)?
        var screenPointAction: ((CGPoint) -> Void)?
        
        func makeUIView(context: Context) -> UIView {
            let view = UIView(frame: UIScreen.main.bounds)
            view.backgroundColor = .clear
            
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.frame = view.frame
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            
            // Add tap gesture for focus
            let tapGesture = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleTap(_:)))
            view.addGestureRecognizer(tapGesture)
            
            return view
        }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first
            as? AVCaptureVideoPreviewLayer
        {
            layer.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: CameraPreview

        init(_ parent: CameraPreview) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard
                let previewLayer = gesture.view?.layer.sublayers?.first
                    as? AVCaptureVideoPreviewLayer
            else { return }
            let tapPoint = gesture.location(in: gesture.view)
            let devicePoint = previewLayer.captureDevicePointConverted(
                fromLayerPoint: tapPoint)
            parent.focusAction?(devicePoint)
            parent.screenPointAction?(tapPoint)
        }
    }
}
