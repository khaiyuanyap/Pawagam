//
//  CinemaDNGRekorderApp.swift
//  CinemaDNGRekorder
//
//  Created by Khai Yuan Yap on 12/06/2025.
//

import AVFoundation
import Photos
import SwiftUI

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
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreview(
                session: cameraManager.captureSession,
                focusAction: cameraManager.setFocusPoint
            )
            .ignoresSafeArea()

            // UI Overlay
            VStack {
                // Top Status Bar
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target: \(cameraManager.targetFPS) FPS")
                            .font(.caption)
                            .foregroundColor(.white)
                        Text("Status: \(cameraManager.statusText)")
                            .font(.caption)
                            .foregroundColor(.white)
                        Text("Pipeline: \(cameraManager.pipelineStatus)")
                            .font(.caption)
                            .foregroundColor(.white)
                        Text("Format: \(cameraManager.pixelFormatName)")
                            .font(.caption)
                            .foregroundColor(.white)
                        Text("Crop: \(cameraManager.cropFactorText)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Text("Captured: \(cameraManager.captureCount)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.4), .clear], startPoint: .top,
                        endPoint: .bottom))

                Spacer()

                // Bottom Controls
                VStack(spacing: 16) {
                    // Capture Button
                    Button(action: {
                        if cameraManager.isCapturing {
                            cameraManager.stopCapture()
                        } else if !cameraManager.isFinishing {
                            cameraManager.startCapture()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(
                                    cameraManager.isFinishing
                                        ? Color.gray
                                        : (cameraManager.isCapturing
                                            ? Color.green : Color.red)
                                )
                                .frame(width: 80, height: 80)

                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 80, height: 80)

                            Image(
                                systemName:
                                    cameraManager.isFinishing
                                    ? "hourglass"
                                    : (cameraManager.isCapturing
                                        ? "stop.fill" : "camera.fill")
                            )
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        }
                    }
                    .scaleEffect(cameraManager.isCapturing ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.1),
                        value: cameraManager.isCapturing
                    )
                    .disabled(cameraManager.isFinishing)

                    // Status Text
                    Text(
                        cameraManager.isFinishing
                            ? "Finishing..."
                            : (cameraManager.isCapturing
                                ? "Recording..." : "Tap to Start")
                    )
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                }
                .padding(.bottom, 40)
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
            Button("OK") {}
        } message: {
            Text(
                "Saved \(cameraManager.captureCount) files to 'On My iPhone' in Files app.\n\nPath: DNG Camera > DNG_Captures > \(cameraManager.captureDirectory?.lastPathComponent ?? "")\n\nErrors: \(cameraManager.errorCount)"
            )
        }
        .onAppear {
            cameraManager.requestPermissions()
        }
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
    // Add crop factor property
    @Published var cropFactorText = "1.0x"
    private var currentCropFactor: Double = 1.0

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

    @Published var isWarmingUp = false  // NEW: Track warm-up state
    private var warmUpTimer: Timer?  // NEW: Timer for warm-up period

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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    // MARK: - Focus Control
    func setFocusPoint(_ point: CGPoint) {
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()

            // Check if point of interest is supported
            if device.isFocusPointOfInterestSupported
                && device.isFocusModeSupported(.autoFocus)
            {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }

            // Set exposure point if supported
            if device.isExposurePointOfInterestSupported
                && device.isExposureModeSupported(.autoExpose)
            {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
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
                if !granted {
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
        isWarmingUp = true  // NEW: Start in warm-up mode
        isCapturing = false
        isFinishing = false
        captureCount = 0
        errorCount = 0
        nextFrameID = 1
        lastSavedFrameID = 0
        frameBuffer.removeAll()
        captureGroup = DispatchGroup()
        updateStatusText("Warming Up...")  // NEW: Update status
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

        // NEW: Set warm-up timer to transition after 5 seconds
        DispatchQueue.main.async {
            self.warmUpTimer = Timer.scheduledTimer(
                withTimeInterval: 10.0,
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                self.isWarmingUp = false
                self.isCapturing = true
                self.updateStatusText("Capturing...")
                print("Warm-up complete. Starting actual capture.")
            }
        }
    }

    // MARK: - Stop Capture Logic
    func stopCapture() {
        guard isCapturing || isWarmingUp else { return }

        // Cancel warm-up if active
        warmUpTimer?.invalidate()
        warmUpTimer = nil

        if isWarmingUp {
            // Delete warm-up directory if capture was stopped during warm-up
            if let captureDir = captureDirectory {
                do {
                    try FileManager.default.removeItem(at: captureDir)
                    print("Deleted warm-up directory: \(captureDir.path)")
                } catch {
                    print("Error deleting warm-up directory: \(error)")
                }
            }

            isWarmingUp = false
            updateStatusText("Ready")
            return
        }

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
        }

        warmUpTimer?.invalidate()  // NEW: Cancel warm-up if stopping
        warmUpTimer = nil

        DispatchQueue.main.async {
            self.cropFactorText = "1.0x"
        }
    }

    private func capturePhoto() {
        // NEW: Skip buffer check during warm-up
        if isCapturing {  // Only check buffer during actual capture
            bufferLock.lock()
            let currentBufferSize = frameBuffer.count
            bufferLock.unlock()

            if currentBufferSize >= maxBufferSize {
                print(
                    "Skipping capture: buffer full (\(currentBufferSize)/\(maxBufferSize))"
                )
                return
            }
        }

        
        captureSerialQueue.async {
            // Check buffer size
            self.bufferLock.lock()
            let currentBufferSize = self.frameBuffer.count
            self.bufferLock.unlock()

            if currentBufferSize >= self.maxBufferSize {
                print("Skipping capture: buffer full (\(currentBufferSize)/\(self.maxBufferSize))")
                return
            }

            // Calculate crop factor based on target FPS
            let cropFactor: Double
            switch self.targetFPS {
            case 20: cropFactor = 1.0
            case 24: cropFactor = 1.5
            default:
                // Linear interpolation between 20-24 FPS
                cropFactor = min(1.5, max(1.0, 1.0 + (Double(self.targetFPS) - 20.0) * 0.125))
            }
            
            DispatchQueue.main.async {
                self.cropFactorText = String(format: "%.1fx", cropFactor)
            }

            // Get dimensions - CORRECTED VERSION
            guard let fullDimensions = self.captureDevice.activeFormat.supportedMaxPhotoDimensions.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
                print("Failed to get max photo dimensions")
                return
            }

            // CORRECTED CROP CALCULATION
            let croppedWidth = Int32(Double(fullDimensions.width) / cropFactor)
            let croppedHeight = Int32(Double(fullDimensions.height) / cropFactor)
            let croppedDimensions = CMVideoDimensions(width: croppedWidth, height: croppedHeight)

            // Create settings
            let settings: AVCapturePhotoSettings
            if self.supportedRawPixelFormats.isEmpty {
                settings = AVCapturePhotoSettings()
                print("Falling back to JPEG capture")
            } else {
                settings = AVCapturePhotoSettings(rawPixelFormatType: self.selectedRawPixelFormat)
            }

            // Configure settings
            settings.maxPhotoDimensions = croppedDimensions
            settings.isHighResolutionPhotoEnabled = false
            settings.flashMode = .off

            // Capture
            DispatchQueue.main.async {
                self.photoOutput.capturePhoto(with: settings, delegate: self)
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
    // Max time to wait for pending frames
    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        // NEW: Skip processing during warm-up
        guard (isCapturing || isFinishing) && !isWarmingUp else {
            print("Discarding warm-up frame")
            return
        }

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
