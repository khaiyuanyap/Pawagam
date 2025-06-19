//
//  GridOverlay.swift
//  CinemaDNGRekorder
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

// Grid Overlay
struct GridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height

                // Vertical lines (rule of thirds)
                let verticalSpacing = width / 3
                for i in 1..<3 {
                    let x = verticalSpacing * CGFloat(i)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }

                // Horizontal lines (rule of thirds)
                let horizontalSpacing = height / 3
                for i in 1..<3 {
                    let y = horizontalSpacing * CGFloat(i)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(.white.opacity(0.3), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}
