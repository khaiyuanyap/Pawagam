//
//  HistogramView.swift
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

struct HistogramView: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var histogramData: [CGFloat] = Array(
        repeating: 0.1, count: 64)

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Histogram Chart
            ZStack {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<histogramData.count, id: \.self) { index in
                        let normalizedHeight = histogramData[index]
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: gradientColors(for: index),
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
                
                // Mode indicator
                VStack {
                    HStack {
                        Spacer()
                        Text(cameraManager.histogramMode.rawValue.prefix(3).uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(modeIndicatorColor())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer()
                }
                .frame(width: 120, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .onTapGesture {
            cycleHistogramMode()
        }
        .onReceive(cameraManager.histogramPublisher) { newData in
            withAnimation(.easeInOut(duration: 0.15)) {
                histogramData = newData
            }
        }
    }
    
    private func gradientColors(for index: Int) -> [Color] {
        switch cameraManager.histogramMode {
        case .luminance:
            return [
                .white.opacity(0.9),
                .white.opacity(0.6)
            ]
        case .red:
            return [
                .red.opacity(0.9),
                .red.opacity(0.6)
            ]
        case .green:
            return [
                .green.opacity(0.9),
                .green.opacity(0.6)
            ]
        case .blue:
            return [
                .blue.opacity(0.9),
                .blue.opacity(0.6)
            ]
        case .rgb:
            // For RGB mode, cycle through R, G, B colors
            let colorIndex = index % 3
            switch colorIndex {
            case 0:
                return [.red.opacity(0.9), .red.opacity(0.6)]
            case 1:
                return [.green.opacity(0.9), .green.opacity(0.6)]
            default:
                return [.blue.opacity(0.9), .blue.opacity(0.6)]
            }
        }
    }
    
    private func cycleHistogramMode() {
        let allModes = CameraManager.HistogramMode.allCases
        guard let currentIndex = allModes.firstIndex(of: cameraManager.histogramMode) else { return }
        
        let nextIndex = (currentIndex + 1) % allModes.count
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            cameraManager.histogramMode = allModes[nextIndex]
        }
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func modeIndicatorColor() -> Color {
        switch cameraManager.histogramMode {
        case .luminance:
            return .white
        case .red:
            return .red
        case .green:
            return .green
        case .blue:
            return .blue
        case .rgb:
            return .white
        }
    }
}
