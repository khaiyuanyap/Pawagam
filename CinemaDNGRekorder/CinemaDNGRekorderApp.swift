//
//  CinemaDNGRekorderApp.swift
//  CinemaDNGRekorder
//
//  Created by Khai Yuan Yap on 12/06/2025.
//

import SwiftUI
import AVFoundation
import Photos

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
            CameraPreview(session: cameraManager.captureSession)
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
                .background(LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                
                Spacer()
                
                // Bottom Controls
                VStack(spacing: 16) {
                    // Capture Button
                    Button(action: {
                        if cameraManager.isCapturing {
                            cameraManager.stopCapture()
                        } else {
                            cameraManager.startCapture()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(cameraManager.isCapturing ? Color.green : Color.red)
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: cameraManager.isCapturing ? "stop.fill" : "camera.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .scaleEffect(cameraManager.isCapturing ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: cameraManager.isCapturing)
                    
                    // Status Text
                    Text(cameraManager.isCapturing ? "Recording DNG..." : "Tap to Start")
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
            Button("OK") { }
        } message: {
            Text(cameraManager.alertMessage)
        }
        .alert("Capture Complete", isPresented: $cameraManager.showCaptureComplete) {
            Button("OK") { }
        } message: {
            Text("Saved \(cameraManager.captureCount) DNG files to 'On My iPhone' in Files app.\n\nPath: DNG Camera > DNG_Captures > \(cameraManager.captureDirectory?.lastPathComponent ?? "")")
        }
        .onAppear {
            cameraManager.requestPermissions()
        }
    }
}

// MARK: - Camera Preview UIViewRepresentable
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}

// MARK: - Camera Manager
class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isCapturing = false
    @Published var captureCount = 0
    @Published var statusText = "Ready"
    @Published var showAlert = false
    @Published var showCaptureComplete = false
    @Published var alertMessage = ""
    @Published var pipelineStatus = "0/0/0" // Capture/Process/Save
    
    // MARK: - Camera Properties
    let captureSession = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput!
    private var captureDevice: AVCaptureDevice!
    
    // MARK: - Capture Properties
    let targetFPS = 24
    private var captureTimer: Timer?
    private let captureInterval: TimeInterval
    
    // MARK: - Pipeline System
    private let pipelineQueue = DispatchQueue(label: "com.cinemadngrekorder.pipeline", qos: .userInitiated,
                                             attributes: .concurrent)
    private let dngProcessingQueue = DispatchQueue(label: "com.cinemadngrekorder.dngprocessing", qos: .userInitiated,
                                                  attributes: .concurrent)
    private let fileSavingQueue = DispatchQueue(label: "com.cinemadngrekorder.filesaving", qos: .utility)
    
    private var frameBuffer = [Int: (photo: AVCapturePhoto, timestamp: Date)]()
    private var nextFrameID = 1
    private var lastSavedFrameID = 0
    private let bufferLock = NSLock()
    private let pipelineSemaphore: DispatchSemaphore
    
    // MARK: - File Management
    private var documentsPath: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    var captureDirectory: URL?
    
    // MARK: - Initialization
    override init() {
        self.captureInterval = 1.0 / Double(targetFPS)
        self.pipelineSemaphore = DispatchSemaphore(value: ProcessInfo.processInfo.processorCount)
        super.init()
        setupCamera()
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {
        captureSession.sessionPreset = .photo
        
        // Setup camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
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
            showError("Unable to create camera input: \(error.localizedDescription)")
            return
        }
        
        // Setup photo output
        photoOutput = AVCapturePhotoOutput()
        photoOutput.maxPhotoQualityPrioritization = .speed
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        
        // Configure camera for high-speed capture
        configureCameraForHighSpeed()
        
        // Start session
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    private func configureCameraForHighSpeed() {
        do {
            try captureDevice.lockForConfiguration()
            
            // Set frame rate for high-speed capture
            if captureDevice.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= Double(targetFPS) }) {
                captureDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                captureDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            }
            
            // Lock settings for consistent capture
            if captureDevice.isFocusModeSupported(.locked) {
                captureDevice.focusMode = .locked
            }
            
            if captureDevice.isExposureModeSupported(.locked) {
                captureDevice.exposureMode = .locked
            }
            
            if captureDevice.isWhiteBalanceModeSupported(.locked) {
                captureDevice.whiteBalanceMode = .locked
            }
            
            captureDevice.unlockForConfiguration()
        } catch {
            print("Error configuring camera: \(error)")
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
        // Create capture directory in Documents (visible in "On My iPhone")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        
        // Create a folder specifically for DNG captures
        let dngCapturesFolder = documentsPath.appendingPathComponent("DNG_Captures")
        captureDirectory = dngCapturesFolder.appendingPathComponent("Capture_\(timestamp)")
        
        guard var captureDir = captureDirectory else { return }
        
        do {
            // Create the main DNG_Captures folder if it doesn't exist
            try FileManager.default.createDirectory(at: dngCapturesFolder, withIntermediateDirectories: true)
            // Create the specific capture session folder
            try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
            
            // Make sure the files are visible in Files app
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            try captureDir.setResourceValues(resourceValues)
            
            print("Created capture directory: \(captureDir.path)")
            
        } catch {
            showError("Failed to create capture directory: \(error.localizedDescription)")
            return
        }
        
        // Reset pipeline state
        isCapturing = true
        captureCount = 0
        nextFrameID = 1
        lastSavedFrameID = 0
        frameBuffer.removeAll()
        statusText = "Capturing..."
        updatePipelineStatus()
        
        // Start high-speed capture timer
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            self?.capturePhoto()
        }
    }
    
    func stopCapture() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        statusText = "Finishing..."
        
        // Wait for pipeline to finish
        pipelineQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Wait for all frames to be processed
            while self.lastSavedFrameID < self.nextFrameID - 1 {
                Thread.sleep(forTimeInterval: 0.01)
            }
            
            DispatchQueue.main.async {
                self.statusText = "Ready"
                self.showCaptureComplete = true
            }
        }
    }
    
    private func capturePhoto() {
        guard isCapturing else { return }
        
        // Create photo settings for DNG capture
        let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: kCVPixelFormatType_14Bayer_RGGB)
        
        // Configure settings for speed
        photoSettings.maxPhotoDimensions = CMVideoDimensions(width: 0, height: 0)
        photoSettings.flashMode = .off
        
        // Capture photo
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
        
        // Update frame counter
        pipelineQueue.async {
            self.captureCount += 1
        }
    }
    
    // MARK: - Pipeline Processing
    private func processFrame(_ photo: AVCapturePhoto, frameID: Int) {
        pipelineQueue.async {
            // Add to frame buffer
            self.bufferLock.lock()
            self.frameBuffer[frameID] = (photo, Date())
            self.bufferLock.unlock()
            
            self.updatePipelineStatus()
            
            // Process frame in parallel
            self.pipelineSemaphore.wait()
            self.dngProcessingQueue.async {
                self.processDNGData(photo, frameID: frameID)
                self.pipelineSemaphore.signal()
            }
        }
    }
    
    private func processDNGData(_ photo: AVCapturePhoto, frameID: Int) {
        guard let dngData = photo.fileDataRepresentation() else {
            print("Failed to get DNG data for frame \(frameID)")
            return
        }
        
        fileSavingQueue.async {
            self.saveDNGData(dngData, frameID: frameID)
        }
    }
    
    private func saveDNGData(_ dngData: Data, frameID: Int) {
        guard let captureDir = captureDirectory else { return }
        
        let filename = String(format: "IMG_%04d.dng", frameID)
        let fileURL = captureDir.appendingPathComponent(filename)
        
        do {
            try dngData.write(to: fileURL)
            print("Saved DNG: \(filename)")
            
            // Update last saved frame
            pipelineQueue.async {
                self.bufferLock.lock()
                self.frameBuffer[frameID] = nil
                self.lastSavedFrameID = max(self.lastSavedFrameID, frameID)
                self.bufferLock.unlock()
                self.updatePipelineStatus()
            }
        } catch {
            print("Error saving DNG file: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.showError("Failed to save DNG file: \(error.localizedDescription)")
            }
        }
    }
    
    private func updatePipelineStatus() {
        bufferLock.lock()
        let captureCount = frameBuffer.count
        let oldestTimestamp = frameBuffer.values.map { $0.timestamp }.min()
        let age = oldestTimestamp.map { -$0.timeIntervalSinceNow } ?? 0
        bufferLock.unlock()
        
        let status = "C:\(captureCount) P:\(ProcessInfo.processInfo.processorCount) A:\(String(format: "%.2f", age))s"
        
        DispatchQueue.main.async {
            self.pipelineStatus = status
        }
    }
    
    // MARK: - Error Handling
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.alertMessage = message
            self.showAlert = true
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard isCapturing else { return }
        
        if let error = error {
            print("Error capturing DNG photo: \(error.localizedDescription)")
            return
        }
        
        pipelineQueue.async {
            let currentFrameID = self.nextFrameID
            self.nextFrameID += 1
            
            // Process frame in pipeline
            self.processFrame(photo, frameID: currentFrameID)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error in photo capture: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.showError("Capture error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
