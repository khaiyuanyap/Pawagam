//
//  CinemaDNGRekorderApp.swift
//  CinemaDNGRekorder
//
//  Created by Khai Yuan Yap on 12/06/2025.
//

import AVFoundation
import Combine
import Photos
import SwiftUI

func print(items: Any..., separator: String = " ", terminator: String = "\n") {

    #if DEBUG

    var idx = items.startIndex
    let endIdx = items.endIndex

    repeat {
        Swift.print(items[idx], separator: separator, terminator: idx == (endIdx - 1) ? terminator : separator)
        idx += 1
    }
    while idx < endIdx

    #endif
}

// MARK: - App Delegate for Orientation Lock
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

// MARK: - Main App
@main
struct DNGCameraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    // MARK: - Standard Increments
    let standardISOs: [Double] = [
        25, 50, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800,
        1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000,
        10000, 12800, 16000, 20000, 25600, 32000, 40000, 51200,
    ]

    let standardShutterAngles: [Double] = [
        1, 2, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360,
    ]

    // MARK: - Helper Functions
    private func roundToIncrement(_ value: Double, increments: [Double])
        -> Double
    {
        guard !increments.isEmpty else { return value }
        let first = increments[0]
        let last = increments[increments.count - 1]
        if value <= first { return first }
        if value >= last { return last }

        // Find the closest increment
        var closest = increments[0]
        var minDiff = abs(value - closest)
        for increment in increments {
            let diff = abs(value - increment)
            if diff < minDiff {
                minDiff = diff
                closest = increment
            }
        }
        return closest
    }

    @StateObject private var cameraManager = CameraManager()
    @State private var showStats = false
    @State private var captureButtonScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreview(
                session: cameraManager.captureSession,
                focusAction: cameraManager.setFocusPoint
            )
            .ignoresSafeArea()

            // UI Overlay
            VStack(spacing: 0) {
                // Top Status Bar
                topStatusBar

                Spacer()

                // Bottom Controls
                bottomControls
            }
        }
        .alert("Error", isPresented: $cameraManager.showAlert) {
            Button("OK") { cameraManager.acknowledgeError() }
        } message: {
            Text(cameraManager.alertMessage)
        }
        .alert(
            "Capture Complete", isPresented: $cameraManager.showCaptureComplete
        ) {
            Button("View Files") {
                cameraManager.openFilesApp()
            }
            Button("OK") {}
        } message: {
            Text(captureCompleteMessage)
        }
        .onAppear {
            cameraManager.requestPermissions()
        }
    }

    // MARK: - Top Status Bar
    private var topStatusBar: some View {
        VStack(spacing: 0) {
            HStack {
                // Stats Toggle Button
                Button(action: {
                    withAnimation(.smooth(duration: 0.35)) {
                        showStats.toggle()
                    }
                }) {
                    Image(systemName: "slider.horizontal.3")
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

                Spacer()

                // Focus Lock Indicator (UPDATED)
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

            // Expandable Stats Panel
            if showStats {
                statsPanel
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.95, anchor: .top)
                                .combined(with: .opacity)
                                .combined(with: .move(edge: .top))
                                .animation(
                                    .smooth(duration: 0.4, extraBounce: 0.1)),
                            removal: .scale(scale: 0.98, anchor: .top)
                                .combined(with: .opacity)
                                .combined(with: .move(edge: .top))
                                .animation(.smooth(duration: 0.25))
                        )
                    )
            }
        }
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

    private var statsPanel: some View {
        VStack(spacing: 20) {
            // Status Grid
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12), count: 2),
                spacing: 12
            ) {
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
                    icon: "gearshape.2.fill",
                    title: "Pipeline",
                    value: cameraManager.pipelineStatus
                )

                statusCard(
                    icon: "camera.viewfinder",
                    title: "Format",
                    value: cameraManager.pixelFormatName
                )
            }

            // Divider
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 0.5)

            // Exposure Controls Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "camera.metering.multispot")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Exposure Controls")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 16) {
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

                    // Shutter Angle Control with standard increments
                    exposureControl(
                        icon: "timer",
                        title: "Shutter",
                        value: $cameraManager.shutterAngle,
                        range: 1...360,
                        increments: standardShutterAngles,
                        displayValue: "\(Int(cameraManager.shutterAngle))°"
                    )
                }
            }
        }
        .padding(24)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)
    }

    private func statusCard(
        icon: String, title: String, value: String, valueColor: Color = .white
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Updated Exposure Control
    private func exposureControl(
        icon: String,
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        increments: [Double],
        displayValue: String
    ) -> some View {
        // Create custom rounded binding
        let roundedBinding = Binding<Double>(
            get: { value.wrappedValue },
            set: { newValue in
                let rounded = roundToIncrement(newValue, increments: increments)
                value.wrappedValue = rounded
            }
        )

        return VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 16)

                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(0.3)
                }

                Spacer()

                Text(displayValue)
                    .font(
                        .system(size: 15, weight: .semibold, design: .rounded)
                    )
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            }

            // Use the rounded binding for the slider
            Slider(value: roundedBinding, in: range)
                .tint(.white)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.05), lineWidth: 1)
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

    // MARK: - Bottom Controls
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

    private var captureCompleteMessage: String {
        """
        Successfully saved \(cameraManager.captureCount) files!

        📁 Location: Files > On My iPhone > DNG Camera > DNG_Captures > \(cameraManager.captureDirectory?.lastPathComponent ?? "")

        \(cameraManager.errorCount > 0 ? "⚠️ \(cameraManager.errorCount) errors occurred" : "✅ No errors")
        """
    }

    private func captureButtonAction() {
        if cameraManager.isCapturing {
            cameraManager.stopCapture()
        } else if !cameraManager.isFinishing {
            cameraManager.startCapture()
        }
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

struct CaptureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.smooth(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Camera Preview UIViewRepresentable
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var focusAction: ((CGPoint) -> Void)?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black

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
        }
    }
}

// MARK: - Camera Manager
class CameraManager: NSObject, ObservableObject {
    @Published var isFocusLocked = false

    // MARK: - Focus Lock
    private func lockFocus() {
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()

            // Lock focus at current setting
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
                DispatchQueue.main.async {
                    self.isFocusLocked = true
                }
                print("Focus locked")
            } else {
                print("Locked focus mode not supported")
            }

            device.unlockForConfiguration()
        } catch {
            print("Error locking focus: \(error.localizedDescription)")
        }
    }

    private func unlockFocus() {
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                DispatchQueue.main.async {
                    self.isFocusLocked = false
                }
                print("Focus unlocked")
            }

            device.unlockForConfiguration()
        } catch {
            print("Error unlocking focus: \(error.localizedDescription)")
        }
    }

    private func resetFocus() {
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                DispatchQueue.main.async {
                    self.isFocusLocked = false
                }
                print("Focus reset to continuous")
            }

            device.unlockForConfiguration()
        } catch {
            print("Error resetting focus: \(error.localizedDescription)")
        }
    }

    // Exposure properties
    @Published var iso: Float = 100.0
    @Published var shutterAngle: Double = 180.0
    @Published var minISO: Float = 0.0
    @Published var maxISO: Float = 0.0
    private var cancellables = Set<AnyCancellable>()

    // Add focus point visualization
    @Published var focusPoint: CGPoint? = nil
    private var focusPointTimer: Timer?

    // File management
    func openFilesApp() {
        guard let captureDir = captureDirectory else {
            showError("No capture directory found")
            return
        }

        // Create a URL that points to the parent directory
        let parentDir = captureDir.deletingLastPathComponent()

        DispatchQueue.main.async {
            // Open the Files app at our directory
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: parentDir.path) {
                let controller = UIDocumentPickerViewController(
                    forOpeningContentTypes: [.folder])
                controller.directoryURL = parentDir
                UIApplication.shared.windows.first?.rootViewController?.present(
                    controller, animated: true)
            } else {
                self.showError("Directory not found")
            }
        }
    }

    @Published var elapsedTime: TimeInterval = 0

    private var metricsTimer: Timer?
    private var captureStartTime: Date?
    // Increased buffer size
    private let maxBufferSize = 50000  // Up from 100
    private let maxMemoryFrames = 10000  // Keep only recent frames in memory

    // New buffer management properties
    private var frameDataCache = [Int: Data]()
    private var diskCacheURL: URL?
    private var isLowMemory = false

    // Enhanced threading system
    private let rawProcessingQueue = DispatchQueue(
        label: "com.cinemadngrekorder.rawprocessing",
        qos: .userInitiated,
        attributes: .concurrent)

    private let jpegProcessingQueue = DispatchQueue(
        label: "com.cinemadngrekorder.jpegprocessing",
        qos: .userInitiated,
        attributes: .concurrent)

    private let fileSavingQueue = DispatchQueue(
        label: "com.cinemadngrekorder.filesaving",
        qos: .utility,
        attributes: .concurrent)  // Changed to concurrent

    // Prioritization
    private var processingPriority = [Int: Bool]()
    private let priorityQueue = DispatchQueue(
        label: "com.cinemadngrekorder.priority",
        qos: .userInteractive)

    private var pendingFrames = Set<Int>()  // Track all frames that need processing
    private let finishQueue = DispatchQueue(
        label: "com.cinemadngrekorder.finish")
    private let maxWaitTime: TimeInterval = 10.0

    // MARK: - Published Properties
    @Published var isCapturing = false
    @Published var isFinishing = false
    @Published var captureCount = 0
    @Published var statusText = "Ready"
    @Published var showAlert = false
    @Published var showCaptureComplete = false
    @Published var alertMessage = ""
    @Published var pipelineStatus = "0/0/0"  // Capture/Process/Save
    @Published var errorCount = 0
    @Published var pixelFormatName = "Unknown"

    // MARK: - Camera Properties
    let captureSession = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput!
    private var captureDevice: AVCaptureDevice!

    // MARK: - Focus Properties
    private var focusTimer: Timer?
    private let focusDuration: TimeInterval = 2.0

    // MARK: - Capture Properties
    let targetFPS = 24
    private var captureTimer: DispatchSourceTimer?
    private let captureInterval: TimeInterval

    // MARK: - Pipeline System
    private let pipelineQueue = DispatchQueue(
        label: "com.cinemadngrekorder.pipeline", qos: .userInitiated)
    private let dngProcessingQueue = DispatchQueue(
        label: "com.cinemadngrekorder.dngprocessing", qos: .userInitiated,
        attributes: .concurrent)

    private var frameBuffer = [Int: (photo: AVCapturePhoto, timestamp: Date)]()
    private var nextFrameID = 1
    private var lastSavedFrameID = 0
    private let bufferLock = NSLock()
    private let pipelineSemaphore: DispatchSemaphore
    private var captureGroup: DispatchGroup?

    // MARK: - Capture Readiness
    private let captureSerialQueue = DispatchQueue(
        label: "com.cinemadngrekorder.captureserial")

    // MARK: - File Management
    private var documentsPath: URL {
        return FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
    }
    var captureDirectory: URL?

    // MARK: - Raw Format Support
    private var supportedRawPixelFormats: [OSType] = []
    private var selectedRawPixelFormat: OSType = 0

    // MARK: - Initialization
    override init() {
        self.captureInterval = 1.0 / Double(targetFPS)
        self.pipelineSemaphore = DispatchSemaphore(
            value: ProcessInfo.processInfo.processorCount)
        super.init()
        setupCamera()

        // Setup disk cache
        setupDiskCache()

        // Memory warning observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Setup exposure observers
        setupExposureObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        focusPointTimer?.invalidate()
    }

    private func setupExposureObservers() {
        $iso
            .dropFirst()
            .sink { [weak self] newISO in
                self?.setExposure(iso: newISO)
            }
            .store(in: &cancellables)

        $shutterAngle
            .dropFirst()
            .sink { [weak self] newAngle in
                self?.setShutterAngle(newAngle)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - White Balance Lock
    private func lockWhiteBalance() {
        guard let device = captureDevice else { return }
        
        do {
            try device.lockForConfiguration()
            // Lock white balance at current setting
            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
                print("White balance locked")
            } else {
                print("Locked white balance mode not supported")
            }
            device.unlockForConfiguration()
        } catch {
            print("Error locking white balance: \(error.localizedDescription)")
        }
    }

    private func unlockWhiteBalance() {
        guard let device = captureDevice else { return }
        
        do {
            try device.lockForConfiguration()
            // Revert to continuous auto white balance
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                print("White balance unlocked")
            }
            device.unlockForConfiguration()
        } catch {
            print("Error unlocking white balance: \(error.localizedDescription)")
        }
    }

    @objc private func handleMemoryWarning() {
        bufferLock.lock()
        isLowMemory = true

        // Free memory immediately
        let framesToKeep = min(frameBuffer.count, maxMemoryFrames)
        let framesToRemove = Array(
            frameBuffer.keys.sorted().dropFirst(framesToKeep))

        for frameID in framesToRemove {
            frameBuffer.removeValue(forKey: frameID)
            frameDataCache.removeValue(forKey: frameID)
        }

        bufferLock.unlock()
        print("⚠️ Memory warning - reduced buffer to \(framesToKeep) frames")
    }

    private func setupDiskCache() {
        let tempDir = FileManager.default.temporaryDirectory
        diskCacheURL = tempDir.appendingPathComponent("CinemaDNG_Cache")

        do {
            try FileManager.default.createDirectory(
                at: diskCacheURL!,
                withIntermediateDirectories: true
            )
            print("Disk cache initialized at: \(diskCacheURL!.path)")
        } catch {
            print("Failed to create disk cache: \(error)")
        }
    }

    // MARK: - Camera Setup
    private func setupCamera() {
        captureSession.sessionPreset = .photo

        // Setup camera input
        guard
            let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back)
        else {
            showError("Unable to access camera")
            return
        }

        captureDevice = camera

        do {
            // Get ISO range
            try captureDevice.lockForConfiguration()
            minISO = captureDevice.activeFormat.minISO
            maxISO = captureDevice.activeFormat.maxISO
            iso = captureDevice.iso
            captureDevice.unlockForConfiguration()
        } catch {
            print("Error getting ISO range: \(error)")
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            showError(
                "Unable to create camera input: \(error.localizedDescription)")
            return
        }

        // Setup photo output
        photoOutput = AVCapturePhotoOutput()
        photoOutput.maxPhotoQualityPrioritization = .speed

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        // Get supported raw formats
        supportedRawPixelFormats = photoOutput.availableRawPhotoPixelFormatTypes
        print("Available raw formats: \(supportedRawPixelFormats)")

        // Prefer 14-bit Bayer if available, otherwise use any available format
        if supportedRawPixelFormats.contains(kCVPixelFormatType_14Bayer_RGGB) {
            selectedRawPixelFormat = kCVPixelFormatType_14Bayer_RGGB
            pixelFormatName = "14b RGGB"
        } else if supportedRawPixelFormats.contains(
            kCVPixelFormatType_14Bayer_GRBG)
        {
            selectedRawPixelFormat = kCVPixelFormatType_14Bayer_GRBG
            pixelFormatName = "14b GRBG"
        } else if supportedRawPixelFormats.contains(
            kCVPixelFormatType_14Bayer_BGGR)
        {
            selectedRawPixelFormat = kCVPixelFormatType_14Bayer_BGGR
            pixelFormatName = "14b BGGR"
        } else if supportedRawPixelFormats.contains(
            kCVPixelFormatType_14Bayer_GBRG)
        {
            selectedRawPixelFormat = kCVPixelFormatType_14Bayer_GBRG
            pixelFormatName = "14b GBRG"
        } else if let firstFormat = supportedRawPixelFormats.first {
            selectedRawPixelFormat = firstFormat
            pixelFormatName = "Raw \(firstFormat)"
        } else {
            pixelFormatName = "JPEG"
            print("Device doesn't support raw photo capture")
        }

        print("Selected format: \(pixelFormatName)")

        // Configure camera for high-speed capture and autofocus
        configureCamera()

        // Start session
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    private func configureCamera() {
        do {
            try captureDevice.lockForConfiguration()

            // Configure autofocus
            if captureDevice.isFocusModeSupported(.continuousAutoFocus) {
                captureDevice.focusMode = .continuousAutoFocus
            }

            // Configure auto exposure
            if captureDevice.isExposureModeSupported(.continuousAutoExposure) {
                captureDevice.exposureMode = .continuousAutoExposure
            }

            // Configure auto white balance
            if captureDevice.isWhiteBalanceModeSupported(
                .continuousAutoWhiteBalance)
            {
                captureDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            // Set frame rate for high-speed capture
            if captureDevice.activeFormat.videoSupportedFrameRateRanges
                .contains(where: { $0.maxFrameRate >= Double(targetFPS) })
            {
                let timeValue = CMTimeValue(1)
                let timeScale = CMTimeScale(targetFPS)
                captureDevice.activeVideoMinFrameDuration = CMTime(
                    value: timeValue, timescale: timeScale)
                captureDevice.activeVideoMaxFrameDuration = CMTime(
                    value: timeValue, timescale: timeScale)
            }

            captureDevice.unlockForConfiguration()
        } catch {
            print("Error configuring camera: \(error)")
            showError(
                "Camera configuration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Exposure Control
    private func setExposure(iso: Float) {
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()

            // Set ISO
            device.setExposureModeCustom(
                duration: device.exposureDuration, iso: iso)

            device.unlockForConfiguration()
        } catch {
            print("Error setting ISO: \(error.localizedDescription)")
        }
    }

    private func setShutterAngle(_ angle: Double) {
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()

            // Calculate exposure duration from shutter angle
            let frameDuration = CMTime(
                value: 1, timescale: CMTimeScale(targetFPS))
            let exposureDurationSeconds =
                (angle / 360.0) * Double(frameDuration.seconds)
            let exposureDuration = CMTime(
                seconds: exposureDurationSeconds, preferredTimescale: 1_000_000)

            // Set exposure duration
            device.setExposureModeCustom(
                duration: exposureDuration, iso: device.iso)

            device.unlockForConfiguration()
        } catch {
            print("Error setting shutter angle: \(error.localizedDescription)")
        }
    }

    // MARK: - Focus Control (enhanced)
    func setFocusPoint(_ point: CGPoint) {
        // Add this guard condition to ignore focus changes during capture
        guard !isCapturing else { return }
        
        guard let device = captureDevice else { return }

        // Visualize focus point
        focusPoint = point
        focusPointTimer?.invalidate()
        focusPointTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0, repeats: false
        ) { [weak self] _ in
            self?.focusPoint = nil
        }

        do {
            try device.lockForConfiguration()

            // Check if point of interest is supported
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point

                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }

            // Set exposure point if supported
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point

                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                } else if device.isExposureModeSupported(
                    .continuousAutoExposure)
                {
                    device.exposureMode = .continuousAutoExposure
                }
            }

            device.unlockForConfiguration()

            // Reset focus to continuous after delay
            resetFocusAfterDelay()
        } catch {
            print("Error setting focus point: \(error.localizedDescription)")
        }
    }

    private func resetFocusAfterDelay() {
        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(
            withTimeInterval: focusDuration, repeats: false
        ) { [weak self] _ in
            self?.resetToContinuousFocus()
        }
    }

    private func resetToContinuousFocus() {
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            device.unlockForConfiguration()
        } catch {
            print("Error resetting focus: \(error.localizedDescription)")
        }
    }

    // MARK: - Permissions
    func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    // Reset focus when permissions are granted
                    self?.resetFocus()
                } else {
                    self?.showError("Camera access is required for this app")
                }
            }
        }

        PHPhotoLibrary.requestAuthorization { status in
            // Handle photo library permission if needed
        }
    }

    // MARK: - Capture Control
    func startCapture() {
        // Reset metrics
        elapsedTime = 0

        // Start metrics timer
        captureStartTime = Date()
        metricsTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0, repeats: true
        ) { [weak self] _ in
            guard let self = self else { return }

            // Update elapsed time
            if let startTime = self.captureStartTime {
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }

        pendingFrames.removeAll()

        // Create capture directory in Documents (visible in "On My iPhone")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        // Create a folder specifically for DNG captures
        let dngCapturesFolder = documentsPath.appendingPathComponent(
            "DNG_Captures")
        captureDirectory = dngCapturesFolder.appendingPathComponent(
            "Capture_\(timestamp)")

        guard var captureDir = captureDirectory else { return }

        do {
            // Create the main DNG_Captures folder if it doesn't exist
            try FileManager.default.createDirectory(
                at: dngCapturesFolder, withIntermediateDirectories: true)
            // Create the specific capture session folder
            try FileManager.default.createDirectory(
                at: captureDir, withIntermediateDirectories: true)

            // Make sure the files are visible in Files app
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            try captureDir.setResourceValues(resourceValues)

            print("Created capture directory: \(captureDir.path)")

        } catch {
            showError(
                "Failed to create capture directory: \(error.localizedDescription)"
            )
            return
        }

        // Reset pipeline state
        isCapturing = true
        isFinishing = false
        captureCount = 0
        errorCount = 0
        nextFrameID = 1
        lastSavedFrameID = 0
        frameBuffer.removeAll()
        captureGroup = DispatchGroup()
        updateStatusText("Capturing...")
        updatePipelineStatus()

        // Start high-speed capture timer
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.cinemadngrekorder.capturetimer"))
        timer.schedule(
            deadline: .now(), repeating: captureInterval,
            leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.capturePhoto()
        }
        timer.resume()
        captureTimer = timer

        lockFocus()
          lockWhiteBalance() // ADD THIS LINE
    }

    // MARK: - Stop Capture Logic
    func stopCapture() {
        guard isCapturing else { return }

        isCapturing = false
        isFinishing = true
        captureTimer?.cancel()
        captureTimer = nil
        updateStatusText("Finishing...")

        // Use a dedicated queue for finishing to prevent deadlocks
        finishQueue.async { [weak self] in
            guard let self = self else { return }

            // Wait for pending frames with timeout
            let result = self.captureGroup?.wait(
                timeout: .now() + self.maxWaitTime)

            // Check if we timed out
            if result == .timedOut {
                print("Timeout waiting for frames to finish")

                // Force complete any remaining frames
                self.bufferLock.lock()
                let remainingFrames = self.pendingFrames
                self.bufferLock.unlock()

                for frameID in remainingFrames {
                    print("Force completing frame \(frameID)")
                    self.captureGroup?.leave()
                }
            }

            // Final cleanup
            self.bufferLock.lock()
            self.pendingFrames.removeAll()
            self.frameBuffer.removeAll()
            self.bufferLock.unlock()

            // Final UI updates
            DispatchQueue.main.async {
                self.isFinishing = false
                self.updateStatusText("Ready")
                self.showCaptureComplete = true
            }

            unlockFocus()
             unlockWhiteBalance() // ADD THIS LINE

        }
    }

    private func capturePhoto() {
        // Skip if buffer full
        bufferLock.lock()
        let currentBufferSize = frameBuffer.count
        bufferLock.unlock()

        if currentBufferSize >= maxBufferSize {
            print(
                "Skipping capture: buffer full (\(currentBufferSize)/\(maxBufferSize))"
            )
            return
        }

        captureSerialQueue.async {
            // Check buffer size
            self.bufferLock.lock()
            let currentBufferSize = self.frameBuffer.count
            self.bufferLock.unlock()

            // Skip if buffer full or system busy
            if currentBufferSize >= self.maxBufferSize {
                print(
                    "Skipping capture: buffer full (\(currentBufferSize)/\(self.maxBufferSize))"
                )
                return
            }

            // Create photo settings with the supported raw pixel format
            let photoSettings: AVCapturePhotoSettings

            if self.supportedRawPixelFormats.isEmpty {
                // Fallback to JPEG if no raw formats available
                photoSettings = AVCapturePhotoSettings()
                print("Falling back to JPEG capture")
            } else {
                // Use supported raw format
                photoSettings = AVCapturePhotoSettings(
                    rawPixelFormatType: self.selectedRawPixelFormat
                )
            }

            // Configure settings for speed
            photoSettings.isHighResolutionPhotoEnabled = false
            photoSettings.flashMode = .off

            // Capture photo
            DispatchQueue.main.async {
                self.photoOutput.capturePhoto(
                    with: photoSettings, delegate: self)
            }
        }
    }

    // MARK: - Pipeline Processing
    private func processFrame(_ photo: AVCapturePhoto, frameID: Int) {
        pipelineQueue.async {
            // Track frame in buffer
            self.bufferLock.lock()
            self.pendingFrames.insert(frameID)
            self.frameBuffer[frameID] = (photo, Date())
            self.bufferLock.unlock()

            self.updatePipelineStatus()

            // Process based on format
            if self.supportedRawPixelFormats.contains(where: {
                $0 == self.selectedRawPixelFormat
            }) {
                self.processRawFrame(photo, frameID: frameID)
            } else {
                self.processJPEGFrame(photo, frameID: frameID)
            }
        }
    }

    private func processRawFrame(_ photo: AVCapturePhoto, frameID: Int) {
        pipelineSemaphore.wait()
        rawProcessingQueue.async {
            defer { self.pipelineSemaphore.signal() }

            guard let dngData = photo.fileDataRepresentation() else {
                self.handleFrameCompletion(frameID: frameID, success: false)
                return
            }

            // Cache in memory or disk based on available memory
            self.bufferLock.lock()

            if self.frameDataCache.count < self.maxMemoryFrames
                && !self.isLowMemory
            {
                // Keep in memory
                self.frameDataCache[frameID] = dngData
                self.bufferLock.unlock()
                print("📦 Cached RAW frame \(frameID) in memory")
            } else {
                // Write to disk cache
                self.bufferLock.unlock()
                let cacheFile = self.diskCacheURL!.appendingPathComponent(
                    "frame_\(frameID).dng")

                do {
                    try dngData.write(to: cacheFile)
                    print("💾 Cached RAW frame \(frameID) to disk")
                } catch {
                    print("Disk cache write failed: \(error)")
                    self.handleFrameCompletion(frameID: frameID, success: false)
                    return
                }
            }

            // Save to final destination
            self.fileSavingQueue.async {
                self.saveDNGData(dngData, frameID: frameID)
            }
        }
    }

    private func processJPEGFrame(_ photo: AVCapturePhoto, frameID: Int) {
        pipelineSemaphore.wait()
        jpegProcessingQueue.async {
            defer { self.pipelineSemaphore.signal() }

            guard let cgImage = photo.previewCGImageRepresentation() else {
                self.handleFrameCompletion(frameID: frameID, success: false)
                return
            }

            let uiImage = UIImage(cgImage: cgImage)
            guard let jpegData = uiImage.jpegData(compressionQuality: 0.9)
            else {
                self.handleFrameCompletion(frameID: frameID, success: false)
                return
            }

        }
    }

    private func processImageData(_ photo: AVCapturePhoto, frameID: Int) {
        // Try to get raw DNG data first
        if let dngData = photo.fileDataRepresentation() {
            self.saveDNGData(dngData, frameID: frameID)
        }
        // If raw not available, try to get processed data
        else if let cgImage = photo.previewCGImageRepresentation() {
            self.saveProcessedData(cgImage, frameID: frameID)
        }
        // If both fail, report error
        else {
            print("Failed to get any image data for frame \(frameID)")
            self.handleFrameCompletion(frameID: frameID, success: false)
        }
    }

    // MARK: - Buffer Enhancements
    private func saveDNGData(_ dngData: Data, frameID: Int) {
        guard let captureDir = captureDirectory else {
            self.handleFrameCompletion(frameID: frameID, success: false)
            return
        }

        let filename = String(format: "IMG_%04d.dng", frameID)
        let fileURL = captureDir.appendingPathComponent(filename)

        do {
            // Check if we have a cached disk version
            let cacheFile = diskCacheURL!.appendingPathComponent(
                "frame_\(frameID).dng")
            if FileManager.default.fileExists(atPath: cacheFile.path) {
                // Move from cache instead of re-writing
                try FileManager.default.moveItem(at: cacheFile, to: fileURL)
                print("Moved DNG from cache: \(filename)")
            } else {
                // Write directly from memory
                try dngData.write(to: fileURL)
                print("Saved DNG from memory: \(filename)")
            }

            self.handleFrameCompletion(frameID: frameID, success: true)
        } catch {
            print("Error saving DNG file: \(error.localizedDescription)")
            self.handleFrameCompletion(frameID: frameID, success: false)
        }
    }

    private func saveProcessedData(_ cgImage: CGImage, frameID: Int) {
        guard let captureDir = captureDirectory else {
            self.handleFrameCompletion(frameID: frameID, success: false)
            return
        }

        let filename = String(format: "IMG_%04d.jpg", frameID)
        let fileURL = captureDir.appendingPathComponent(filename)

        do {
            let uiImage = UIImage(cgImage: cgImage)
            if let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
                try jpegData.write(to: fileURL)
                print("Saved JPEG: \(filename)")
                self.handleFrameCompletion(frameID: frameID, success: true)
            } else {
                throw NSError(
                    domain: "ImageProcessing", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Failed to create JPEG data"
                    ])
            }
        } catch {
            print("Error saving JPEG file: \(error.localizedDescription)")
            self.handleFrameCompletion(frameID: frameID, success: false)
        }
    }

    private func handleFrameCompletion(frameID: Int, success: Bool) {
        pipelineQueue.async {
            // Cleanup cache
            self.bufferLock.lock()
            self.pendingFrames.remove(frameID)
            self.frameBuffer.removeValue(forKey: frameID)
            self.frameDataCache.removeValue(forKey: frameID)

            // Remove disk cache if exists
            let cacheFile = self.diskCacheURL!.appendingPathComponent(
                "frame_\(frameID).dng")
            if FileManager.default.fileExists(atPath: cacheFile.path) {
                try? FileManager.default.removeItem(at: cacheFile)
            }

            self.lastSavedFrameID = max(self.lastSavedFrameID, frameID)
            self.bufferLock.unlock()

            self.updatePipelineStatus()
            self.captureGroup?.leave()

            if !success {
                DispatchQueue.main.async {
                    self.errorCount += 1
                }
            }
        }
    }

    // MARK: - Thread-Safe UI Updates
    private func updateStatusText(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }

    private func updateCaptureCount(_ count: Int) {
        DispatchQueue.main.async {
            self.captureCount = count
        }
    }

    private func updatePipelineStatus() {
        bufferLock.lock()
        let captureCount = frameBuffer.count
        let oldestTimestamp = frameBuffer.values.map { $0.timestamp }.min()
        let age = oldestTimestamp.map { -$0.timeIntervalSinceNow } ?? 0
        bufferLock.unlock()

        let status =
            "C:\(captureCount) P:\(ProcessInfo.processInfo.processorCount) A:\(String(format: "%.2f", age))s"

        DispatchQueue.main.async {
            self.pipelineStatus = status
        }
    }

    // MARK: - Error Handling
    func acknowledgeError() {
        showAlert = false
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.alertMessage = message
            self.showAlert = true
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        pipelineQueue.async {
            let currentFrameID = self.nextFrameID
            self.nextFrameID += 1

            // Enter group for this frame BEFORE processing
            self.captureGroup?.enter()

            // Update capture count
            DispatchQueue.main.async {
                self.captureCount = currentFrameID
            }

            if let error = error {
                print("Error processing photo: \(error.localizedDescription)")
                // Handle error immediately
                self.handleFrameCompletion(
                    frameID: currentFrameID, success: false)
                return
            }

            // Process frame
            self.processFrame(photo, frameID: currentFrameID)
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
