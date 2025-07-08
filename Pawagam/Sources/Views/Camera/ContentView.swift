//
//  ContentView.swift
//  Pawagam
//
//  Khai Yuan Yap
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
    @StateObject private var viewModel = ContentViewModel()
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
                    session: viewModel.cameraManager.captureSession,
                    focusAction: viewModel.cameraManager.setFocusPoint
                )
                .ignoresSafeArea()
                .background(.clear)

                // Grid Overlay
                if viewModel.cameraManager.showGrid {
                    GridOverlay()
                }
                
            }

            // Histogram (right side)
            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 12) {
                        // Histogram
                        if viewModel.cameraManager.showHistogram {
                            HistogramView(cameraManager: viewModel.cameraManager)
                        }
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
            

            // UI Overlay
            VStack(spacing: 0) {
                // Top Status Bar
                topStatusBar

                Spacer()

                // Bottom Controls
                bottomControls
            }
            
            // Exposure Control Popups
            exposurePopups
            
            // Modern Capture Complete Popup
            if viewModel.cameraManager.showCaptureComplete {
                modernCaptureCompletePopup
            }
        }
        .fullScreenCover(isPresented: $viewModel.showSettings) {
            SettingsView(
                cameraManager: viewModel.cameraManager,
                standardISOs: viewModel.standardISOs,
                standardShutterAngles: viewModel.standardShutterAngles,
                roundToIncrement: viewModel.roundToIncrement
            )
        }
        .alert("Error", isPresented: $viewModel.cameraManager.showAlert) {
            Button("OK") { viewModel.cameraManager.acknowledgeError() }
        } message: {
            Text(viewModel.cameraManager.alertMessage)
        }
        .onAppear {
            viewModel.cameraManager.requestPermissions()
            // Lock exposure when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                viewModel.cameraManager.lockExposure()
            }
            // Prevent screen dimming
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            // Re-enable screen dimming when app goes away
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    // MARK: - Exposure Control Popups
    private var exposurePopups: some View {
        ZStack(alignment: .bottom) {
            // Dismissal background
            if viewModel.showISOPopup || viewModel.showShutterPopup {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring()) {
                            viewModel.showISOPopup = false
                            viewModel.showShutterPopup = false
                        }
                    }
            }
            
            VStack(spacing: 0) {
                Spacer()
                
                // ISO Popup
                if viewModel.showISOPopup {
                    ExposureControl(
                        icon: "circle.bottomrighthalf.pattern.checkered",
                        title: "ISO",
                        value: Binding<Double>(
                            get: { Double(viewModel.cameraManager.iso) },
                            set: {
                                let clampedValue = min(max($0, Double(viewModel.cameraManager.minISO)), Double(viewModel.cameraManager.maxISO))
                                viewModel.cameraManager.iso = Float(clampedValue)
                            }
                        ),
                        range: Double(viewModel.cameraManager.minISO)...Double(viewModel.cameraManager.maxISO),
                        increments: viewModel.standardISOs.filter {
                            $0 >= Double(viewModel.cameraManager.minISO) && $0 <= Double(viewModel.cameraManager.maxISO)
                        },
                        displayValue: "\(Int(viewModel.cameraManager.iso))",
                        roundToIncrement: viewModel.roundToIncrement
                    )
                    .padding()
                    .padding(.horizontal)
                    .padding(.bottom, 55)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Shutter Popup
                if viewModel.showShutterPopup {
                    ExposureControl(
                        icon: "righttriangle",
                        title: "Shutter Angle",
                        value: $viewModel.cameraManager.shutterAngle,
                        range: 1...360,
                        increments: viewModel.standardShutterAngles,
                        displayValue: "\(Int(viewModel.cameraManager.shutterAngle))°",
                        roundToIncrement: viewModel.roundToIncrement
                    )
                    .padding()
                    .padding(.horizontal)
                    .padding(.bottom, 55)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .zIndex(1) // Ensure popups appear above other content
    }

    private var modernCaptureCompletePopup: some View {
        ZStack {
            // Darker backdrop blur
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.cameraManager.showCaptureComplete = false
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
                    .scaleEffect(viewModel.cameraManager.showCaptureComplete ? 1.0 : 0.8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: viewModel.cameraManager.showCaptureComplete)
                    
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
                        
                        Text("\(viewModel.cameraManager.captureCount) cDNG frames saved")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                    }
                    
                    // Location info
                    if let directory = viewModel.cameraManager.captureDirectory?.lastPathComponent {
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
                        Image(systemName: viewModel.cameraManager.errorCount > 0 ? "exclamationmark.triangle" : "checkmark")
                            .font(.system(size: 16))
                            .foregroundColor(viewModel.cameraManager.errorCount > 0 ? .primary : .secondary)
                            .frame(width: 16)
                        
                        Text(viewModel.cameraManager.errorCount > 0 ? "\(viewModel.cameraManager.errorCount) dropped frames" : "No errors")
                            .font(.subheadline)
                            .foregroundColor(viewModel.cameraManager.errorCount > 0 ? .primary : .secondary)
                        
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
                            viewModel.cameraManager.showCaptureComplete = false
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
                        viewModel.cameraManager.openFilesApp()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.cameraManager.showCaptureComplete = false
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
            .scaleEffect(viewModel.cameraManager.showCaptureComplete ? 1.0 : 0.9)
            .opacity(viewModel.cameraManager.showCaptureComplete ? 1.0 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: viewModel.cameraManager.showCaptureComplete)
        }
    }

    // Top Status Bar
    private var topStatusBar: some View {
        HStack {
            // Settings Toggle Button
            Button(action: {
                viewModel.showSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
            }
            .buttonStyle(ModernButtonStyle())

            Spacer()

            // Capture Counter
            captureCounterView
            
            // Dropped Frames Indicator
            if viewModel.cameraManager.errorCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("\(viewModel.cameraManager.errorCount)")
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
                if viewModel.cameraManager.isFocusLocked {
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
            Text("\(viewModel.cameraManager.captureCount)")
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
        switch viewModel.cameraManager.statusText.lowercased() {
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
            if viewModel.cameraManager.isCapturing || viewModel.cameraManager.isFinishing {
                recordingIndicator
                    .transition(
                        .scale.combined(with: .opacity).animation(
                            .smooth(duration: 0.3)))
            }

            // Main Capture Button with exposure controls
            HStack(spacing: 15) { // Reduced spacing between buttons
                // ISO Button
                exposureControlButton(
                    icon: "circle.bottomrighthalf.pattern.checkered",
                    isActive: viewModel.showISOPopup,
                    action: {
                        withAnimation(.spring()) {
                            viewModel.showShutterPopup = false
                            viewModel.showISOPopup.toggle()
                        }
                    }
                )
                
                // Main Capture Button
                captureButton
                
                // Shutter Button
                exposureControlButton(
                    icon: "righttriangle",
                    isActive: viewModel.showShutterPopup,
                    action: {
                        withAnimation(.spring()) {
                            viewModel.showISOPopup = false
                            viewModel.showShutterPopup.toggle()
                        }
                    }
                )
            }
            .padding(.horizontal, 24) // Reduced side padding

            // Status Text
            statusText
        }
        .padding(.horizontal, 16) // Reduced outer padding
        .padding(.bottom)
    }
    
    private func exposureControlButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.yellow : Color.white.opacity(0.15), lineWidth: 0.5)
                )
        }
    }

    private var recordingIndicator: some View {
        HStack(spacing: 10) {
            // Pulsing indicator
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .scaleEffect(viewModel.cameraManager.isCapturing ? 1.2 : 0.8)
                .opacity(viewModel.cameraManager.isCapturing ? 1.0 : 0.6)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: viewModel.cameraManager.isCapturing
                )

            Text(viewModel.cameraManager.isFinishing ? "Finalizing..." : "Recording")
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
                    .scaleEffect(viewModel.cameraManager.isCapturing ? 0.9 : 1.0)
                    .animation(
                        .smooth(duration: 0.2), value: viewModel.cameraManager.isCapturing
                    )
            }
        }
        .scaleEffect(captureButtonScale)
        .disabled(viewModel.cameraManager.isFinishing)
        .opacity(viewModel.cameraManager.isFinishing ? 0.6 : 1.0)
        .buttonStyle(CaptureButtonStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: captureButtonScale)
        { _, newValue in
            newValue < 1.0
        }
    }

    private var buttonAccentColor: Color {
        if viewModel.cameraManager.isFinishing {
            return .gray
        } else if viewModel.cameraManager.isCapturing {
            return .red
        } else {
            return .white
        }
    }

    private var buttonIconColor: Color {
        if viewModel.cameraManager.isFinishing {
            return .gray
        } else if viewModel.cameraManager.isCapturing {
            return .red
        } else {
            return .white
        }
    }

    private var buttonIcon: String {
        if viewModel.cameraManager.isFinishing {
            return "hourglass"
        } else if viewModel.cameraManager.isCapturing {
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
        if viewModel.cameraManager.isFinishing {
            return "Finishing..."
        } else if viewModel.cameraManager.isCapturing {
            return "Recording..."
        } else {
            return "Tap to Record"
        }
    }

    private func captureButtonAction() {
        if viewModel.cameraManager.isCapturing {
            viewModel.cameraManager.stopCapture()
        } else if !viewModel.cameraManager.isFinishing {
            viewModel.cameraManager.startCapture()
        }
    }
    
    // MARK: - Exposure Control Component
    struct ExposureControl: View {
        let icon: String
        let title: String
        @Binding var value: Double
        let range: ClosedRange<Double>
        let increments: [Double]
        let displayValue: String
        let roundToIncrement: (Double, [Double]) -> Double
        
        // Your custom presets
        let isoPresets = [100.0, 200.0, 800.0, 3200.0]
        let shutterPresets = [45.0, 90.0, 180.0, 360.0]
        
        var presets: [Double] {
            if title == "ISO" {
                return isoPresets
            } else {
                return shutterPresets
            }
        }
        
        var body: some View {
            // Calculate actual slider range based on increments
            let sliderRange = increments.min()!...increments.max()!
            let minValue = increments.min()!
            let maxValue = increments.max()!
            
            let roundedBinding = Binding<Double>(
                get: { value },
                set: { newValue in
                    let rounded = roundToIncrement(newValue, increments)
                    value = rounded
                }
            )
            
            return VStack(spacing: 16) {
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 20, height: 20)
                        
                        Text(title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                    
                    Spacer()
                    
                    Text(displayValue)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                }
                
                Slider(value: roundedBinding, in: sliderRange)
                    .tint(.white)
                
                // ISO range indicators
                HStack {
                    Text("Min: \(Int(minValue))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Text("Max: \(Int(maxValue))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(presets, id: \.self) { preset in
                            Button(action: {
                                withAnimation(.spring()) {
                                    value = preset
                                }
                            }) {
                                Text("\(Int(preset))")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(
                                        value == preset ? .black : .white
                                    )
                                    .frame(minWidth: 44)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(
                                        value == preset ? Color.white : Color.clear
                                    )
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                value == preset ? Color.white : Color.white.opacity(0.3),
                                                lineWidth: value == preset ? 0 : 1
                                            )
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
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

