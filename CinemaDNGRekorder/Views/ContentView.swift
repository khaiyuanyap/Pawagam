//
//  ContentView.swift
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

/// Content View
struct ContentView: View {
    // Standard Increments
    let standardISOs: [Double] = [
        25, 50, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800,
        1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000,
        10000, 12800, 16000, 20000, 25600, 32000, 40000, 51200,
    ]

    let standardShutterAngles: [Double] = [
        1, 2, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360,
    ]

    private func roundToIncrement(_ value: Double, increments: [Double])
        -> Double
    {
        guard !increments.isEmpty else { return value }
        let first = increments[0]
        let last = increments[increments.count - 1]

        // Handle values outside the increments range
        if value <= first { return first }
        if value >= last { return last }

        // Binary search for the first element >= value
        var low = 0
        var high = increments.count - 1
        var index = increments.count  // Default if not found (shouldn't happen due to bounds)

        while low <= high {
            let mid = (low + high) / 2
            if increments[mid] < value {
                low = mid + 1
            } else {
                index = mid
                high = mid - 1
            }
        }

        // Compare adjacent candidates for the closest increment
        let candidate1 = increments[index - 1]
        let candidate2 = increments[index]
        let diff1 = value - candidate1
        let diff2 = candidate2 - value

        return diff1 <= diff2 ? candidate1 : candidate2
    }

    @StateObject private var cameraManager = CameraManager()
    @State private var showSettings = false
    @State private var captureButtonScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Glass background
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            // Camera Preview with Grid
            ZStack {
                CameraPreview(
                    session: cameraManager.captureSession,
                    focusAction: cameraManager.setFocusPoint
                )
                .ignoresSafeArea()
                .background(.clear)

                // Grid Overlay
                if cameraManager.showGrid {
                    GridOverlay()
                }
            }

            // Histogram
            if cameraManager.showHistogram {
                VStack {
                    HStack {
                        Spacer()
                        HistogramView(cameraManager: cameraManager)
                            .padding(.top, 60)
                            .padding(.trailing, 20)
                    }
                    Spacer()
                }
            }

            // UI Overlay
            VStack(spacing: 0) {
                // Top Status Bar
                topStatusBar

                Spacer()

                // Bottom Controls
                bottomControls
            }
            
            // Modern Capture Complete Popup
            if cameraManager.showCaptureComplete {
                modernCaptureCompletePopup
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(
                cameraManager: cameraManager,
                standardISOs: standardISOs,
                standardShutterAngles: standardShutterAngles,
                roundToIncrement: roundToIncrement
            )
        }
        .alert("Error", isPresented: $cameraManager.showAlert) {
            Button("OK") { cameraManager.acknowledgeError() }
        } message: {
            Text(cameraManager.alertMessage)
        }
        .onAppear {
            cameraManager.requestPermissions()
            // Lock exposure when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                cameraManager.lockExposure()
            }
        }
    }

    private var modernCaptureCompletePopup: some View {
        ZStack {
            // Darker backdrop blur
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        cameraManager.showCaptureComplete = false
                    }
                }
            
            // Main popup card
            VStack(spacing: 0) {
                // Header section with icon and title
                HStack(spacing: 12) {
                    // Success icon with monochromatic styling
                    ZStack {
                        Circle()
                            .fill(.gray.opacity(0.3))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(cameraManager.showCaptureComplete ? 1.0 : 0.8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: cameraManager.showCaptureComplete)
                    
                    Text("Capture Complete")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Content section
                VStack(spacing: 12) {
                    // Frames count with monochromatic styling
                    HStack(spacing: 10) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        
                        Text("\(cameraManager.captureCount) cDNG frames saved")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                    }
                    
                    // Location info
                    if let directory = cameraManager.captureDirectory?.lastPathComponent {
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            
                            Text(directory)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                    }
                    
                    // Error status
                    HStack(spacing: 10) {
                        Image(systemName: cameraManager.errorCount > 0 ? "exclamationmark.triangle" : "checkmark")
                            .font(.system(size: 16))
                            .foregroundColor(cameraManager.errorCount > 0 ? .primary : .secondary)
                            .frame(width: 16)
                        
                        Text(cameraManager.errorCount > 0 ? "\(cameraManager.errorCount) dropped frames" : "No errors")
                            .font(.subheadline)
                            .foregroundColor(cameraManager.errorCount > 0 ? .primary : .secondary)
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // Action buttons
                HStack(spacing: 16) {
                    // Secondary action button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            cameraManager.showCaptureComplete = false
                        }
                    }) {
                        Text("Done")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Primary action button
                    Button(action: {
                        cameraManager.openFilesApp()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            cameraManager.showCaptureComplete = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 14))
                            Text("View Files")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: 320)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.quaternary, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
            .scaleEffect(cameraManager.showCaptureComplete ? 1.0 : 0.9)
            .opacity(cameraManager.showCaptureComplete ? 1.0 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: cameraManager.showCaptureComplete)
        }
    }

    // Top Status Bar
    private var topStatusBar: some View {
        HStack {
            // Settings Toggle Button
            Button(action: {
                showSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(ModernButtonStyle())

            Spacer()

            // Capture Counter
            captureCounterView
            
            // Dropped Frames Indicator (NEW)
                   if cameraManager.errorCount > 0 {
                       HStack(spacing: 6) {
                           Image(systemName: "exclamationmark.triangle.fill")
                               .font(.system(size: 14, weight: .bold))
                           Text("\(cameraManager.errorCount)")
                               .font(.system(size: 16, weight: .semibold, design: .rounded))
                       }
                       .foregroundStyle(.white)
                       .padding(.horizontal, 12)
                       .padding(.vertical, 8)
                       .background(.red.opacity(0.8), in: Capsule())
                       .overlay(
                           Capsule()
                               .stroke(.white.opacity(0.15), lineWidth: 0.5)
                       )
                       .transition(.scale.combined(with: .opacity))
                   }

            Spacer()
            
           

            // Focus Lock Indicator
            Group {
                if cameraManager.isFocusLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "lock.open")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .transition(.scale.combined(with: .opacity))
            
            
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var captureCounterView: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo.stack")
                .font(.system(size: 14, weight: .medium))
            Text("\(cameraManager.captureCount)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var statusColor: Color {
        switch cameraManager.statusText.lowercased() {
        case let status where status.contains("ready"):
            return .green
        case let status where status.contains("error"):
            return .red
        case let status where status.contains("warning"):
            return .orange
        default:
            return .white
        }
    }

    // Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Recording Status Indicator
            if cameraManager.isCapturing || cameraManager.isFinishing {
                recordingIndicator
                    .transition(
                        .scale.combined(with: .opacity).animation(
                            .smooth(duration: 0.3)))
            }

            // Main Capture Button
            captureButton

            // Status Text
            statusText
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }

    private var recordingIndicator: some View {
        HStack(spacing: 10) {
            // Pulsing indicator
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .scaleEffect(cameraManager.isCapturing ? 1.2 : 0.8)
                .opacity(cameraManager.isCapturing ? 1.0 : 0.6)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: cameraManager.isCapturing
                )

            Text(cameraManager.isFinishing ? "Finalizing..." : "Recording")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.red.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var captureButton: some View {
        Button(action: captureButtonAction) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 2)
                    .frame(width: 80, height: 80)

                // Inner button
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .fill(buttonAccentColor.opacity(0.1))
                            .frame(width: 64, height: 64)
                    )
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                            .frame(width: 64, height: 64)
                    )

                // Icon
                Image(systemName: buttonIcon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(buttonIconColor)
                    .scaleEffect(cameraManager.isCapturing ? 0.9 : 1.0)
                    .animation(
                        .smooth(duration: 0.2), value: cameraManager.isCapturing
                    )
            }
        }
        .scaleEffect(captureButtonScale)
        .disabled(cameraManager.isFinishing)
        .opacity(cameraManager.isFinishing ? 0.6 : 1.0)
        .buttonStyle(CaptureButtonStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: captureButtonScale)
        { _, newValue in
            newValue < 1.0
        }
    }

    private var buttonAccentColor: Color {
        if cameraManager.isFinishing {
            return .gray
        } else if cameraManager.isCapturing {
            return .red
        } else {
            return .white
        }
    }

    private var buttonIconColor: Color {
        if cameraManager.isFinishing {
            return .gray
        } else if cameraManager.isCapturing {
            return .red
        } else {
            return .white
        }
    }

    private var buttonIcon: String {
        if cameraManager.isFinishing {
            return "hourglass"
        } else if cameraManager.isCapturing {
            return "stop.fill"
        } else {
            return "camera.fill"
        }
    }

    private var statusText: some View {
        Text(statusTextValue)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
    }

    private var statusTextValue: String {
        if cameraManager.isFinishing {
            return "Finishing..."
        } else if cameraManager.isCapturing {
            return "Recording..."
        } else {
            return "Tap to Record"
        }
    }

    private func captureButtonAction() {
        if cameraManager.isCapturing {
            cameraManager.stopCapture()
        } else if !cameraManager.isFinishing {
            cameraManager.startCapture()
        }
    }
}

struct CaptureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.smooth(duration: 0.1), value: configuration.isPressed)
    }
}
