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

// Settings View
struct SettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    let standardISOs: [Double]
    let standardShutterAngles: [Double]
    let roundToIncrement: (Double, [Double]) -> Double

    @Environment(\.dismiss) private var dismiss
    @State private var showDirectoryPicker = false
    @State private var selectedDirectoryURL: URL?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Camera Status Section
                    statusSection
                    
                    // Directory Selection
                    directorySelectionSection

                    // Display Options
                    displaySection

                    // Frame Rate Section
                    frameRateSection

                    // Exposure Controls Section
                    exposureSection

                    // Additional space at bottom
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
    }
    
    private var directorySelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "folder", title: "Capture Directory")
            
            VStack(spacing: 12) {
                HStack {
                    // Use the published property directly
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
                // Frame rate buttons grid
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    ForEach(cameraManager.desiredFramerates, id: \.self) {
                        fps in
                        if cameraManager.availableFramerates.contains(fps) {
                            Button(action: {
                                cameraManager.setFrameRate(fps)
                            }) {
                                Text("\(fps)fps")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(
                                        cameraManager.targetFPS == fps
                                            ? .black : .white
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        cameraManager.targetFPS == fps
                                            ? Color.white
                                            : Color.white.opacity(0.2)
                                    )
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                Color.white.opacity(0.3),
                                                lineWidth: 1)
                                    )
                            }
                        } else {
                            // Show disabled button for unsupported rates
                            Text("\(fps)fps")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            Color.white.opacity(0.1),
                                            lineWidth: 1)
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
            .background(
                .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                icon: "info.circle.fill",
                title: "Camera Status"
            )

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12), count: 2),
                spacing: 12
            ) {
                // Update this card to show frame rate
                statusCard(
                    icon: "gauge.with.dots.needle.67percent",
                    title: "Frame Rate",
                    value: "\(cameraManager.targetFPS) fps"
                )

                statusCard(
                    icon: "checkmark.circle.fill",
                    title: "Status",
                    value: cameraManager.statusText,
                    valueColor: statusColor
                )

                statusCard(
                    icon: "camera.viewfinder",
                    title: "Format",
                    value: cameraManager.pixelFormatName
                )
                statusCard(
                               icon: "clock.fill",
                               title: cameraManager.isCapturing ? "Elapsed" : "Previous",
                               value: formatTimeInterval(
                                   cameraManager.isCapturing
                                       ? cameraManager.elapsedTime
                                       : cameraManager.lastRecordingDuration
                               )
                           )
            }
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                icon: "display",
                title: "Display Options"
            )

            VStack(spacing: 12) {
                toggleOption(
                    icon: "grid",
                    title: "Grid Overlay",
                    subtitle: "Rule of thirds composition guide",
                    isOn: $cameraManager.showGrid
                )

                toggleOption(
                    icon: "chart.bar.fill",
                    title: "Histogram",
                    subtitle: "Real-time exposure analysis",
                    isOn: $cameraManager.showHistogram
                )
            }
        }
    }

    private func toggleOption(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
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

            Toggle("", isOn: isOn)
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

    private var exposureSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                icon: "camera.metering.multispot",
                title: "Exposure Controls"
            )

            VStack(spacing: 20) {
                exposureControl(
                    icon: "camera.aperture",
                    title: "ISO",
                    value: Binding<Double>(
                        get: { Double(cameraManager.iso) },
                        set: { cameraManager.iso = Float($0) }
                    ),
                    range: Double(
                        cameraManager.minISO)...Double(cameraManager.maxISO),
                    increments: standardISOs.filter {
                        $0 >= Double(cameraManager.minISO)
                            && $0 <= Double(cameraManager.maxISO)
                    },
                    displayValue: "\(Int(cameraManager.iso))"
                )

                exposureControl(
                    icon: "timer",
                    title: "Shutter Angle",
                    value: $cameraManager.shutterAngle,
                    range: 1...360,
                    increments: standardShutterAngles,
                    displayValue: "\(Int(cameraManager.shutterAngle))°"
                )
            }
        }
    }

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

    private func statusCard(
        icon: String,
        title: String,
        value: String,
        valueColor: Color = .white
    ) -> some View {
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

    private func exposureControl(
        icon: String,
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        increments: [Double],
        displayValue: String
    ) -> some View {
        let roundedBinding = Binding<Double>(
            get: { value.wrappedValue },
            set: { newValue in
                let rounded = roundToIncrement(newValue, increments)
                value.wrappedValue = rounded
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

            Slider(value: roundedBinding, in: range)
                .tint(.white)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.1), lineWidth: 1)
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
}

// Button Styles
struct ModernButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.smooth(duration: 0.1), value: configuration.isPressed)
    }
}

// Directory Picker
struct DirectoryPicker: UIViewControllerRepresentable {
    @Binding var selectedURL: URL?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
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
