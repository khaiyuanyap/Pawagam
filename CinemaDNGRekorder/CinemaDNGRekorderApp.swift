//
//  CinemaDNGRekorderApp.swift
//  CinemaDNGRekorder
//
//  Created by Khai Yuan Yap on 12/06/2025.
//

import AVFoundation
import Photos
import SwiftUI

// MARK: - Main App
@main
struct DNGCameraApp: App {
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
    private let fileSavingQueue = DispatchQueue(
        label: "com.cinemadngrekorder.filesaving", qos: .utility)

    private var frameBuffer = [Int: (photo: AVCapturePhoto, timestamp: Date)]()
    private var nextFrameID = 1
    private var lastSavedFrameID = 0
    private let bufferLock = NSLock()
    private let pipelineSemaphore: DispatchSemaphore
    private var captureGroup: DispatchGroup?

    // MARK: - Capture Readiness
    private var frameProcessingStatus = [Int: Bool]()  // Track frame processing state
    private let maxBufferSize = 30000  // Maximum frames to buffer
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
        isCapturing = true
        isFinishing = false
        captureCount = 0
        errorCount = 0
        nextFrameID = 1
        lastSavedFrameID = 0
        frameBuffer.removeAll()
        frameProcessingStatus.removeAll()  // Reset tracking
        captureGroup = DispatchGroup()
        updateStatusText("Capturing...")
        updatePipelineStatus()

        // Start high-speed capture timer using DispatchSourceTimer for better precision
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
        }
    }

    private func capturePhoto() {
        guard isCapturing else { return }

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

    /// MARK: - Pipeline Processing
    private func processFrame(_ photo: AVCapturePhoto, frameID: Int) {
        pipelineQueue.async {
            // Track this frame as pending
            self.bufferLock.lock()
            self.pendingFrames.insert(frameID)
            self.frameBuffer[frameID] = (photo, Date())
            self.bufferLock.unlock()

            self.updatePipelineStatus()

            // Process frame
            self.pipelineSemaphore.wait()
            self.dngProcessingQueue.async {
                self.processImageData(photo, frameID: frameID)
                self.pipelineSemaphore.signal()
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

    private func saveDNGData(_ dngData: Data, frameID: Int) {
        guard let captureDir = captureDirectory else {
            self.handleFrameCompletion(frameID: frameID, success: false)
            return
        }

        let filename = String(format: "IMG_%04d.dng", frameID)
        let fileURL = captureDir.appendingPathComponent(filename)

        do {
            try dngData.write(to: fileURL)
            print("Saved DNG: \(filename)")

            // Update frame status
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
            // Update frame status
            self.bufferLock.lock()
            self.pendingFrames.remove(frameID)
            self.frameBuffer[frameID] = nil
            self.lastSavedFrameID = max(self.lastSavedFrameID, frameID)
            self.bufferLock.unlock()

            self.updatePipelineStatus()

            // Leave group for this frame
            self.captureGroup?.leave()
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
        guard isCapturing || isFinishing else { return }

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
