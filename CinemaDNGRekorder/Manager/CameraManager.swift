//
//  CameraManager.swift
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

// Camera Manager
class CameraManager: NSObject, ObservableObject,
    AVCaptureVideoDataOutputSampleBufferDelegate
{
    
    @Published var isLoadingCameras = true

    
    @Published var availableCameras: [CameraInfo] = []
    @Published var selectedCameraID: String = "" {
           didSet {
               if !selectedCameraID.isEmpty && oldValue != selectedCameraID {
                   reconfigureCamera()
                   savePreferences()
               }
           }
       }
       
       private var initialSetupDone = false
    @Published var currentCameraType: String = "Wide"

    // Add this struct inside CameraManager or at the top level
    struct CameraInfo: Identifiable {
        let id: String
        let device: AVCaptureDevice
        let position: AVCaptureDevice.Position
        let type: String
    }

    // Add this method to CameraManager
    private func discoverCameras() {
        var discoveredCameras: [CameraInfo] = []
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        for device in discoverySession.devices {
            let cameraType: String
            switch device.deviceType {
            case .builtInTelephotoCamera:
                cameraType = "Telephoto"
            case .builtInUltraWideCamera:
                cameraType = "Ultra-wide"
            default:
                cameraType = "Wide"
            }
            
            discoveredCameras.append(CameraInfo(
                id: device.uniqueID,
                device: device,
                position: device.position,
                type: cameraType
            ))
        }
        
        print("Available cameras: \(discoveredCameras.map { "\($0.type) (\($0.position == .back ? "Back" : "Front"))" })")
            
            DispatchQueue.main.async { [weak self] in
                self?.availableCameras = discoveredCameras
                self?.isLoadingCameras = false
                
                // Set default camera if none selected
                if let self = self, self.selectedCameraID.isEmpty {
                    if let backWideCamera = discoveredCameras.first(where: {
                        $0.position == .back && $0.type == "Wide"
                    }) {
                        self.selectedCameraID = backWideCamera.id
                        self.currentCameraType = "Wide"
                        self.reconfigureCamera()
                    }
                }
            }
    }
    
    private let deviceConfigurationQueue = DispatchQueue(label: "com.cinemadngrekorder.device.configuration")
    
    private var desiredExposureDuration: CMTime {
        // USE CURRENT TARGET FPS
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        let exposureDurationSeconds = (shutterAngle / 360.0) * Double(frameDuration.seconds)
        return CMTime(seconds: exposureDurationSeconds, preferredTimescale: 1_000_000)
    }
    
    private func updateExposureSettings() {
        guard let device = captureDevice else { return }
        
        // Clamp ISO to valid range
        let clampedISO = max(minISO, min(iso, maxISO))
        
        deviceConfigurationQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                try device.lockForConfiguration()
                
                // Force custom exposure mode
                if device.isExposureModeSupported(.custom) {
                    device.exposureMode = .custom
                }
                
                // Set exposure using calculated duration and ISO
                device.setExposureModeCustom(duration: self.desiredExposureDuration, iso: clampedISO)
                device.unlockForConfiguration()
                
                // Update published ISO if clamping occurred
                if clampedISO != self.iso {
                    DispatchQueue.main.async {
                        self.iso = clampedISO
                    }
                }
            } catch {
                print("Error setting exposure: \(error.localizedDescription)")
            }
        }
    }
    
    private var metalDevice: MTLDevice!
    private var metalCommandQueue: MTLCommandQueue!
    private var histogramPipeline: MTLComputePipelineState!
    private var textureCache: CVMetalTextureCache?
    private var histogramBuffer: MTLBuffer!
    private let histogramSemaphore = DispatchSemaphore(value: 1)
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
        metalDevice = device
        metalCommandQueue = device.makeCommandQueue()
        
        // Create texture cache
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textureCache)
        
        // Create histogram buffer
        histogramBuffer = metalDevice.makeBuffer(length: 256 * MemoryLayout<UInt32>.size,
                                                options: .storageModeShared)
        
        // Load compute shader
        guard let library = metalDevice.makeDefaultLibrary(),
              let function = library.makeFunction(name: "luminanceHistogram") else {
            print("Failed to create Metal shader")
            return
        }
        
        do {
            histogramPipeline = try metalDevice.makeComputePipelineState(function: function)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    private let savingSemaphore = DispatchSemaphore(value: 2)
    @Published var droppedFrames: Int = 0
    
    @Published var lastRecordingDuration: TimeInterval = 0.0
    
    // User Preferences Properties
    @Published var showGrid: Bool = false {
        didSet { savePreferences() }
    }
    
    @Published var showHistogram: Bool = true {
        didSet { savePreferences() }
    }
    
    @Published var targetFPS: Int = 24 {
        didSet {
            if oldValue != targetFPS {
                setFrameRate(targetFPS)
                updateExposureSettings() // Add this line
                savePreferences()
            }
        }
    }
    
    @Published var iso: Float = 100.0 {
        didSet {
            guard !isCapturing else { return } // Prevent changes during capture
            if oldValue != iso {
                updateExposureSettings()
                savePreferences()
            }
        }
    }

    // Updated shutter angle property
    @Published var shutterAngle: Double = 180.0 {
        didSet {
            guard !isCapturing else { return }
            if oldValue != shutterAngle {
                updateExposureSettings()
                savePreferences()
            }
        }
    }
    
    @Published var cameraPosition: AVCaptureDevice.Position = .back {
        didSet {
            if oldValue != cameraPosition {
                reconfigureCamera()
            }
        }
    }

    
     func reconfigureCamera() {
         deviceConfigurationQueue.async { [weak self] in
             guard let self = self else { return }
             
             // Stop session
             self.captureSession.stopRunning()
             
             // Remove existing inputs
             for input in self.captureSession.inputs {
                 self.captureSession.removeInput(input)
             }
             
             // Find the selected camera device
             guard let selectedCamera = self.availableCameras.first(where: {
                 $0.id == self.selectedCameraID
             })?.device else {
                 self.showError("Selected camera not available")
                 return
             }
             
             self.captureDevice = selectedCamera
             
             // UPDATE MIN/MAX ISO FOR NEW CAMERA
             do {
                 try selectedCamera.lockForConfiguration()
                 // Get new ISO range
                             let newMinISO = selectedCamera.activeFormat.minISO
                             let newMaxISO = selectedCamera.activeFormat.maxISO
                             
                             // Clamp current ISO to new camera's range
                             let clampedISO = max(newMinISO, min(self.iso, newMaxISO))
                             
                             selectedCamera.unlockForConfiguration()
                             
                             // Update published properties on main thread
                             DispatchQueue.main.async {
                                 self.minISO = newMinISO
                                 self.maxISO = newMaxISO
                                 if clampedISO != self.iso {
                                     self.iso = clampedISO
                                 }
                             }
                         } catch {
                             print("Error updating ISO range: \(error)")
                             DispatchQueue.main.async {
                                 self.showError("Error configuring camera: \(error.localizedDescription)")
                             }
                         }
                         
                         // Rest of camera configuration remains the same...
                         do {
                             let input = try AVCaptureDeviceInput(device: selectedCamera)
                             if self.captureSession.canAddInput(input) {
                                 self.captureSession.addInput(input)
                             }
                         } catch {
                             self.showError("Unable to create camera input: \(error.localizedDescription)")
                             return
                         }
            
            do {
                let input = try AVCaptureDeviceInput(device: selectedCamera)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                }
            } catch {
                self.showError("Unable to create camera input: \(error.localizedDescription)")
                return
            }
            
            let supportedFormats = self.photoOutput.availableRawPhotoPixelFormatTypes
                print("Available raw formats: \(supportedFormats)")
                
                // Select a compatible format using local variables
                var selectedFormat: OSType = 0
                var newPixelFormatName = "Unknown"
                
                if supportedFormats.contains(kCVPixelFormatType_14Bayer_RGGB) {
                    selectedFormat = kCVPixelFormatType_14Bayer_RGGB
                    newPixelFormatName = "14b RGGB"
                } else if supportedFormats.contains(kCVPixelFormatType_14Bayer_GRBG) {
                    selectedFormat = kCVPixelFormatType_14Bayer_GRBG
                    newPixelFormatName = "14b GRBG"
                } else if supportedFormats.contains(kCVPixelFormatType_14Bayer_BGGR) {
                    selectedFormat = kCVPixelFormatType_14Bayer_BGGR
                    newPixelFormatName = "14b BGGR"
                } else if supportedFormats.contains(kCVPixelFormatType_14Bayer_GBRG) {
                    selectedFormat = kCVPixelFormatType_14Bayer_GBRG
                    newPixelFormatName = "14b GBRG"
                } else if let firstFormat = supportedFormats.first {
                    selectedFormat = firstFormat
                    newPixelFormatName = "Raw \(firstFormat)"
                } else {
                    newPixelFormatName = "JPEG"
                    print("Device doesn't support raw photo capture")
                }
                
                // Update published properties on main thread
                DispatchQueue.main.async {
                    self.supportedRawPixelFormats = supportedFormats
                    self.selectedRawPixelFormat = selectedFormat
                    self.pixelFormatName = newPixelFormatName
                }
            
            // Configure camera settings
            self.configureCamera()
            
            // Restart session
            self.captureSession.startRunning()
            
            // Update UI
            DispatchQueue.main.async {
                self.currentCameraType = selectedCamera.deviceType == .builtInTelephotoCamera ? "Telephoto" :
                                         selectedCamera.deviceType == .builtInUltraWideCamera ? "Ultra-wide" : "Wide"
                self.pixelFormatName = newPixelFormatName
            }
        }
    }
    
    // Directory bookmark properties
    private let directoryBookmarkKey = UserPreferences.directoryBookmarkKey
    @Published var captureDirectoryURL: URL? {
        didSet { savePreferences() }
    }

    // Add frame rate properties
    let desiredFramerates = [20, 24, 30, 60, 120]
    @Published var availableFramerates: [Int] = [20, 24, 30, 60, 120]  // Default values

    // Update to include all desired frame rates
    private func updateAvailableFrameRates() {
        guard let device = captureDevice else { return }

        var rates = Set<Int>()
        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                let minRate = Int(range.minFrameRate)
                let maxRate = Int(range.maxFrameRate)
                // Check against our desired frame rates
                for rate in desiredFramerates {
                    if rate >= minRate && rate <= maxRate {
                        rates.insert(rate)
                    }
                }
            }
        }

        let sortedRates = rates.sorted()
        DispatchQueue.main.async { [weak self] in
            self?.availableFramerates = sortedRates
        }
        print("Available frame rates: \(availableFramerates)")
    }

    func setFrameRate(_ fps: Int) {
        guard availableFramerates.contains(fps) else {
            print("Frame rate \(fps) not supported")
            return
        }

        // Only reconfigure if frame rate actually changed
        if fps != targetFPS {
            targetFPS = fps
            configureCamera()
        }
    }

    // Add video output properties
    private var videoOutput: AVCaptureVideoDataOutput!
    private let videoProcessingQueue = DispatchQueue(
        label: "com.cinemadngrekorder.videoprocessing")

    // Histogram publisher
    @Published var histogramPublisher = PassthroughSubject<[CGFloat], Never>()

    // Method to calculate histogram from camera buffer
    func updateHistogram(from pixelBuffer: CVPixelBuffer) {
        // Calculate histogram data and publish
        let histogramData = calculateHistogramData(from: pixelBuffer)
        histogramPublisher.send(histogramData)
    }

    // Histogram calculation function
    private func calculateHistogramData(from pixelBuffer: CVPixelBuffer) -> [CGFloat] {
        guard histogramSemaphore.wait(timeout: .now() + 0.1) == .success else {
            return Array(repeating: 0, count: 64)
        }
        defer { histogramSemaphore.signal() }
        
        // Reset histogram buffer
        let bufferPtr = histogramBuffer.contents().bindMemory(to: UInt32.self, capacity: 256)
        memset(bufferPtr, 0, 256 * MemoryLayout<UInt32>.size)
        
        // Create Metal texture
        guard let textureCache = textureCache,
              let metalTexture = createMetalTexture(from: pixelBuffer, using: textureCache) else {
            return Array(repeating: 0, count: 64)
        }
        
        // Process with Metal
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return Array(repeating: 0, count: 64)
        }
        
        commandEncoder.setComputePipelineState(histogramPipeline)
        commandEncoder.setTexture(metalTexture, index: 0)
        commandEncoder.setBuffer(histogramBuffer, offset: 0, index: 0)
        
        // Configure threadgroups
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupCount = MTLSize(
            width: (metalTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (metalTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        commandEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Convert to normalized [0,1] values
        let bins = (0..<64).map { CGFloat(bufferPtr[$0 * 4]) } // 256 bins → 64 bins
        guard let maxValue = bins.max(), maxValue > 0 else {
            return Array(repeating: 0, count: 64)
        }
        
        return bins.map { $0 / CGFloat(maxValue) }
    }

    private func createMetalTexture(from pixelBuffer: CVPixelBuffer, using textureCache: CVMetalTextureCache) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvMetalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvMetalTexture
        )
        
        guard status == kCVReturnSuccess,
              let unwrappedTexture = cvMetalTexture,
              let texture = CVMetalTextureGetTexture(unwrappedTexture) else {
            return nil
        }
        
        return texture
    }

    @Published var isFocusLocked = false

    private func lockFocus() {
        guard let device = captureDevice else { return }

        deviceConfigurationQueue.async {
            do {
                try device.lockForConfiguration()
                
                // FOCUS LOCKING ONLY (no exposure)
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                    DispatchQueue.main.async { [weak self] in
                        self?.isFocusLocked = true
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
    }

    private func unlockFocus() {
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                DispatchQueue.main.async { [weak self] in
                    self?.isFocusLocked = false
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
                DispatchQueue.main.async { [weak self] in
                    self?.isFocusLocked = false
                }
                print("Focus reset to continuous")
            }

            device.unlockForConfiguration()
        } catch {
            print("Error resetting focus: \(error.localizedDescription)")
        }
    }

    // Raw Format Support
    @Published var supportedRawPixelFormats: [OSType] = []
    @Published var selectedRawPixelFormat: OSType = 0
    
    // Exposure properties
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
    private let maxBufferSize = 500000  // Up from 100
    private let maxMemoryFrames = 100000  // Keep only recent frames in memory

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
        qos: .userInitiated)

    // Prioritization
    private var processingPriority = [Int: Bool]()
    private let priorityQueue = DispatchQueue(
        label: "com.cinemadngrekorder.priority",
        qos: .userInteractive)

    private var pendingFrames = Set<Int>()  // Track all frames that need processing
    private let finishQueue = DispatchQueue(
        label: "com.cinemadngrekorder.finish")
    private let maxWaitTime: TimeInterval = 10.0

    // Published Properties
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

    // Camera Properties
    let captureSession = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput!
    var captureDevice: AVCaptureDevice!

    // Focus Properties
    private var focusTimer: Timer?
    private let focusDuration: TimeInterval = 2.0

    // Capture Properties
    private var captureTimer: DispatchSourceTimer?

    // Pipeline System
    private let pipelineQueue = DispatchQueue(
        label: "com.cinemadngrekorder.pipeline", qos: .userInitiated)
    private let dngProcessingQueue = DispatchQueue(
        label: "com.cinemadngrekorder.dngprocessing", qos: .userInitiated,
        attributes: .concurrent)

    private var frameBuffer = [Int: Date]()  // frameID: timestamp
    private var nextFrameID = 1
    private var lastSavedFrameID = 0
    private let bufferLock = NSLock()
    private let pipelineSemaphore: DispatchSemaphore
    private var captureGroup: DispatchGroup?

    // Capture Readiness
    private let captureSerialQueue = DispatchQueue(
        label: "com.cinemadngrekorder.captureserial")

    // File Management
    private var documentsPath: URL {
        return FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
    }
    var captureDirectory: URL?
    
    // Preferences Management
    private func loadPreferences() {
        let defaults = UserDefaults.standard
        
        showGrid = defaults.bool(forKey: UserPreferences.showGridKey, defaultValue: false)
        showHistogram = defaults.bool(forKey: UserPreferences.showHistogramKey, defaultValue: true)
        targetFPS = defaults.integer(forKey: UserPreferences.targetFPSKey, defaultValue: 24)
        iso = defaults.float(forKey: UserPreferences.isoKey, defaultValue: 100.0)
        shutterAngle = defaults.double(forKey: UserPreferences.shutterAngleKey, defaultValue: 180.0)
        
        if let savedCameraID = defaults.string(forKey: UserPreferences.selectedCameraIDKey) {
                   selectedCameraID = savedCameraID
               }
        
        // Directory loading
        if let data = defaults.data(forKey: UserPreferences.directoryBookmarkKey),
           let url = URL.fromBookmarkData(data) {
            captureDirectoryURL = url
        } else {
            captureDirectoryURL = documentsPath.appendingPathComponent("DNG_Captures")
        }
    }
    
    private func savePreferences() {
        let defaults = UserDefaults.standard
        
        defaults.set(showGrid, forKey: UserPreferences.showGridKey)
        defaults.set(showHistogram, forKey: UserPreferences.showHistogramKey)
        defaults.set(targetFPS, forKey: UserPreferences.targetFPSKey)
        defaults.set(iso, forKey: UserPreferences.isoKey)
        defaults.set(shutterAngle, forKey: UserPreferences.shutterAngleKey)
        defaults.set(selectedCameraID, forKey: UserPreferences.selectedCameraIDKey)
        
        if let url = captureDirectoryURL, let bookmark = url.bookmarkData() {
            defaults.set(bookmark, forKey: UserPreferences.directoryBookmarkKey)
        }
    }
    
    private func loadCaptureDirectory() {
        // This is now handled in loadPreferences()
    }
        
    func setCaptureDirectory(_ url: URL) {
        captureDirectoryURL = url
    }
    
    // Make captureInterval computed rather than stored
       private var captureInterval: TimeInterval {
           1.0 / Double(targetFPS)
       }

       // Initialization
       override init() {
           
           // Initialize semaphore first
           self.pipelineSemaphore = DispatchSemaphore(
                  value: ProcessInfo.processInfo.processorCount)
              
              super.init()
              
              // Load preferences BEFORE setting up camera
              loadPreferences()
              setupCamera()
           
           initialSetupDone = true

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

    private func lockWhiteBalance() {
        guard let device = captureDevice else { return }

        deviceConfigurationQueue.async {
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
    }

    private func unlockWhiteBalance() {
        guard let device = captureDevice else { return }

        deviceConfigurationQueue.async {
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

    // Camera Setup
    private func setupCamera() {
        setupMetal()

        discoverCameras()
        
        
        // Add video output for histogram
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_32BGRA
        ]

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.sessionPreset = .photo
        
        if selectedCameraID.isEmpty,
                   let backWideCamera = availableCameras.first(where: {
                       $0.position == .back && $0.type == "Wide"
                   }) {
                    selectedCameraID = backWideCamera.id
                    currentCameraType = "Wide"
                }

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
            
            
            deviceConfigurationQueue.sync {
                do {
                    try captureDevice.lockForConfiguration()
                    minISO = captureDevice.activeFormat.minISO
                    maxISO = captureDevice.activeFormat.maxISO
                    
                    // FORCE CUSTOM EXPOSURE MODE
                    if captureDevice.isExposureModeSupported(.custom) {
                        captureDevice.exposureMode = .custom
                    }
                    
                    captureDevice.unlockForConfiguration()
                } catch {
                    print("Error getting ISO range: \(error)")
                }
            }
            
            // APPLY USER PREFERENCES
            updateExposureSettings()
            
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

        // Configure camera for high-speed capture and autofocus
        configureCamera()

        // Start session
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.updateExposureSettings()
                self.lockExposure()
            }
        }

    }

    private func configureCamera() {
        deviceConfigurationQueue.async { [weak self] in
            guard let self = self, let device = self.captureDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                // Configure autofocus
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                // Configure auto white balance
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }

                // Set frame rate for high-speed capture
                if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= Double(self.targetFPS) }) {
                    let timeValue = CMTimeValue(1)
                    let timeScale = CMTimeScale(self.targetFPS)
                    device.activeVideoMinFrameDuration = CMTime(value: timeValue, timescale: timeScale)
                    device.activeVideoMaxFrameDuration = CMTime(value: timeValue, timescale: timeScale)
                }
                
                // MAINTAIN CUSTOM EXPOSURE MODE
                if device.isExposureModeSupported(.custom) {
                    device.exposureMode = .custom
                }
                
                // Apply exposure settings
                let clampedISO = max(self.minISO, min(self.iso, self.maxISO))
                device.setExposureModeCustom(
                    duration: self.desiredExposureDuration,
                    iso: clampedISO
                )
                
                device.unlockForConfiguration()
            } catch {
                print("Error configuring camera: \(error)")
                DispatchQueue.main.async {
                    self.showError("Camera configuration failed: \(error.localizedDescription)")
                }
            }
            
            // Update frame rates on main thread
            DispatchQueue.main.async {
                self.updateAvailableFrameRates()
            }
        }
    }

    // Exposure Control
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

        deviceConfigurationQueue.async {
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
                device.unlockForConfiguration()

                // Reset focus to continuous after delay
                self.resetFocusAfterDelay()
            } catch {
                print("Error setting focus point: \(error.localizedDescription)")
            }
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

        deviceConfigurationQueue.async {
            do {
                try device.lockForConfiguration()
                
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                    DispatchQueue.main.async { [weak self] in
                        self?.isFocusLocked = false
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                print("Error resetting focus: \(error.localizedDescription)")
            }
        }
    }

    // Permissions
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

    // Capture Control
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

        // Use selected directory instead of hard-coded path
        let baseDirectory = captureDirectoryURL ?? documentsPath.appendingPathComponent("DNG_Captures")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        captureDirectory = baseDirectory.appendingPathComponent("Capture_\(timestamp)")

        guard var captureDir = captureDirectory else { return }

        do {
            // Create the directories
            try FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: captureDir,
                withIntermediateDirectories: true
            )

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

        updateExposureSettings()
        
        lockFocus()
        lockWhiteBalance()
    }

    // Stop Capture Logic
    func stopCapture() {
        guard isCapturing else { return }

        lastRecordingDuration = elapsedTime
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
            unlockWhiteBalance()  // ADD THIS LINE

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
            
            // SUPPRESS SHUTTER SOUND IF SUPPORTED
            if #available(iOS 14.0, *), self.photoOutput.isShutterSoundSuppressionSupported {
                photoSettings.isShutterSoundSuppressionEnabled = true
            }

            // Capture photo
            DispatchQueue.main.async {
                self.photoOutput.capturePhoto(
                    with: photoSettings, delegate: self)
            }
        }
    }

    // Pipeline Processing
    private func processFrame(_ photo: AVCapturePhoto, frameID: Int) {
        pipelineQueue.async {
            // Track frame in buffer
            self.bufferLock.lock()
            self.pendingFrames.insert(frameID)
            self.frameBuffer[frameID] = Date()
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
            
            // DIRECT SAVING - NO CACHE
            self.savingSemaphore.wait()
            self.fileSavingQueue.async {
                defer { self.savingSemaphore.signal() }
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

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        // Calculate histogram
        let histogramData = calculateHistogramData(from: pixelBuffer)

        // Publish on main thread
        DispatchQueue.main.async {
            self.histogramPublisher.send(histogramData)
        }
    }

    private func saveDNGData(_ dngData: Data, frameID: Int) {
        guard let captureDir = captureDirectory else { return }
        
        let filename = String(format: "IMG_%04d.dng", frameID)
        let fileURL = captureDir.appendingPathComponent(filename)
        
        do {
            try dngData.write(to: fileURL)
            handleFrameCompletion(frameID: frameID, success: true)
        } catch {
            handleFrameCompletion(frameID: frameID, success: false)
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

    // Thread-Safe UI Updates
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
        bufferLock.unlock()

        let status =
            "C:\(captureCount) P:\(ProcessInfo.processInfo.processorCount)"
        
        DispatchQueue.main.async {
            self.pipelineStatus = status
        }
    }

    // Error Handling
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

// AVCapturePhotoCaptureDelegate
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

// In CameraManager, add this method to lock exposure
extension CameraManager {
    func lockExposure() {
        guard let device = captureDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Lock exposure at current values
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
                print("Exposure locked")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error locking exposure: \(error.localizedDescription)")
        }
    }
}
