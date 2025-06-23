//
//  SettingsView.swift
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

// MARK: - Camera Grid Components
struct CameraGridButton: View {
    let camera: CameraManager.CameraInfo
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(camera.type)
                    .font(.system(size: 12, weight: .medium))
                
                Text(camera.position == .back ? "Back" : "Front")
                    .font(.system(size: 10))
                    .opacity(0.7)
            }
            .foregroundColor(isSelected ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? Color.white
                    : Color.white.opacity(0.2)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
}

struct CameraGrid: View {
    @ObservedObject var cameraManager: CameraManager
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(cameraManager.availableCameras) { camera in
                CameraGridButton(
                    camera: camera,
                    isSelected: cameraManager.selectedCameraID == camera.id,
                    action: {
                        cameraManager.selectedCameraID = camera.id
                        cameraManager.reconfigureCamera()
                    }
                )
            }
        }
    }
}

// MARK: - Status Card Component
struct StatusCard: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = .white
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Toggle Option Component
struct ToggleOption: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .tint(.blue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Main Settings View
struct SettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    let standardISOs: [Double]
    let standardShutterAngles: [Double]
    let roundToIncrement: (Double, [Double]) -> Double

    @Environment(\.dismiss) private var dismiss
    @State private var showDirectoryPicker = false
    @State private var selectedDirectoryURL: URL?
    @State private var showAbout = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    statusSection
                    cameraSelectionSection
                    frameRateSection
                    directorySelectionSection
                    displaySection
                    aboutSection
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(.thinMaterial, ignoresSafeAreaEdges: .all)
            .navigationTitle("Camera Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showDirectoryPicker) {
            DirectoryPicker(selectedURL: $selectedDirectoryURL)
                .onDisappear {
                    if let url = selectedDirectoryURL {
                        cameraManager.setCaptureDirectory(url)
                    }
                }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }
    
    // **MARK: - Section Views**
    private var cameraSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "camera.rotate", title: "Camera Selection")
            
            VStack(spacing: 5) {
                
                // Back cameras grid
                if cameraManager.availableCameras.isEmpty {
                    ProgressView("Discovering cameras...")
                                    .padding()
                } else {
                    if !backCameras.isEmpty {
                        Text("BACK CAMERA")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 10)
                        
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                            spacing: 10
                        ) {
                            ForEach(backCameras, id: \.id) { camera in
                                cameraButton(for: camera)
                            }
                        }
                    }
                    
                    // Front cameras grid
                    if !frontCameras.isEmpty {
                        Text("FRONT CAMERA")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)
                            .padding(.bottom, 10)
                        
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                            spacing: 10
                        ) {
                            ForEach(frontCameras, id: \.id) { camera in
                                cameraButton(for: camera)
                            }
                        }
                    }
                }
                
                Text("Current: \(cameraManager.currentCameraType)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private var backCameras: [CameraManager.CameraInfo] {
        cameraManager.availableCameras.filter { $0.position == .back }
    }

    private var frontCameras: [CameraManager.CameraInfo] {
        cameraManager.availableCameras.filter { $0.position == .front }
    }

    private func cameraButton(for camera: CameraManager.CameraInfo) -> some View {
        Button(action: {
            cameraManager.selectedCameraID = camera.id
            cameraManager.reconfigureCamera()
        }) {
            VStack(spacing: 8) {
                Text(camera.type)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(cameraManager.selectedCameraID == camera.id ? .black : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                cameraManager.selectedCameraID == camera.id
                    ? Color.white
                    : Color.white.opacity(0.2)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "info.circle", title: "Information")
            
            Button(action: { showAbout = true }) {
                HStack(spacing: 16) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("About & Help")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        Text("Learn about features, settings, and tips")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(ModernButtonStyle())
        }
    }
    
    private var directorySelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "folder", title: "Capture Directory")
            
            VStack(spacing: 12) {
                HStack {
                    Text(cameraManager.captureDirectoryURL?.lastPathComponent ?? "Default")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button("Change") {
                        showDirectoryPicker = true
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
                
                Text("Current: \(cameraManager.captureDirectoryURL?.path ?? "")")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var frameRateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "film", title: "Frame Rate")

            VStack(spacing: 16) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    ForEach(cameraManager.desiredFramerates, id: \.self) { fps in
                        if cameraManager.availableFramerates.contains(fps) {
                            Button(action: { cameraManager.setFrameRate(fps) }) {
                                Text("\(fps)fps")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(
                                        cameraManager.targetFPS == fps ? .black : .white
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        cameraManager.targetFPS == fps ? Color.white : Color.white.opacity(0.2)
                                    )
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        } else {
                            Text("\(fps)fps")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                }

                Text("Current: \(cameraManager.targetFPS) fps")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "info.circle.fill", title: "Camera Status")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                spacing: 12
            ) {
                StatusCard(
                    icon: "gauge.with.dots.needle.67percent",
                    title: "Frame Rate",
                    value: "\(cameraManager.targetFPS) fps"
                )

                StatusCard(
                    icon: "checkmark.circle.fill",
                    title: "Status",
                    value: cameraManager.statusText,
                    valueColor: statusColor
                )

                StatusCard(
                    icon: "camera.viewfinder",
                    title: "Format",
                    value: cameraManager.pixelFormatName
                )
                
                StatusCard(
                    icon: "clock.fill",
                    title: cameraManager.isCapturing ? "Elapsed" : "Previous",
                    value: formatTimeInterval(
                        cameraManager.isCapturing ? cameraManager.elapsedTime : cameraManager.lastRecordingDuration
                    )
                )
            }
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "display", title: "Display Options")

            VStack(spacing: 12) {
                ToggleOption(
                    icon: "grid",
                    title: "Grid Overlay",
                    subtitle: "Rule of thirds composition guide",
                    isOn: $cameraManager.showGrid
                )

                ToggleOption(
                    icon: "chart.bar.fill",
                    title: "Histogram",
                    subtitle: "Real-time exposure analysis",
                    isOn: $cameraManager.showHistogram
                )
            }
        }
    }

    // MARK: - Helper Methods
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var statusColor: Color {
        switch cameraManager.statusText.lowercased() {
        case let status where status.contains("ready"): return .green
        case let status where status.contains("error"): return .red
        case let status where status.contains("warning"): return .orange
        default: return .white
        }
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: interval) ?? "0:00"
    }
}

// MARK: - Button Styles
struct ModernButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.smooth(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Directory Picker
struct DirectoryPicker: UIViewControllerRepresentable {
    @Binding var selectedURL: URL?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DirectoryPicker
        
        init(_ parent: DirectoryPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.selectedURL = url
            parent.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}
