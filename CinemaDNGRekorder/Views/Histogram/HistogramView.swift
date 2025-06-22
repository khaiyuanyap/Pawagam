//
//  HistogramView.swift
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

struct HistogramView: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var histogramData: [CGFloat] = Array(
        repeating: 0.1, count: 64)

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Histogram Chart
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    )

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<histogramData.count, id: \.self) { index in
                        let normalizedHeight = histogramData[index]
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.9),
                                        .white.opacity(0.6),
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(
                                width: 120 / CGFloat(histogramData.count),
                                height: max(1, normalizedHeight * 50)
                            )
                            .animation(
                                .easeInOut(duration: 0.15),
                                value: normalizedHeight)
                    }
                }
                .frame(width: 120, height: 60, alignment: .bottom)
                .clipped()
            }

            // Exposure info
            VStack(alignment: .trailing, spacing: 2) {
                Text("ISO \(Int(cameraManager.iso))")
                    .font(
                        .system(size: 10, weight: .medium, design: .monospaced)
                    )
                    .foregroundStyle(.white.opacity(0.8))

                Text("\(Int(cameraManager.shutterAngle))°")
                    .font(
                        .system(size: 10, weight: .medium, design: .monospaced)
                    )
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            )
        }
        .onReceive(cameraManager.histogramPublisher) { newData in
            withAnimation(.easeInOut(duration: 0.15)) {
                histogramData = newData
            }
        }
    }
}
