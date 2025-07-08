//
//  CameraManager.swift
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

// Camera Manager
class CameraManager: NSObject, ObservableObject {
    
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
       
    var initialSetupDone = false
    @Published var currentCameraType: String = "Wide"

    // Add this struct inside CameraManager or at the top level
    struct CameraInfo: Identifiable {
        let id: String
        let device: AVCaptureDevice
        let position: AVCaptureDevice.Position
        let type: String
    }
    
    let deviceConfigurationQueue = DispatchQueue(label: "com.pawagam.device.configuration")
    
    var metalDevice: MTLDevice!
    var metalCommandQueue: MTLCommandQueue!
    var histogramPipeline: MTLComputePipelineState!
    var textureCache: CVMetalTextureCache?
    var histogramBuffer: MTLBuffer!
    let histogramSemaphore = DispatchSemaphore(value: 1)
    
    let savingSemaphore = DispatchSemaphore(value: 2)
    @Published var droppedFrames: Int = 0
    
    @Published var lastRecordingDuration: TimeInterval = 0.0
    
    // User Preferences Properties
    @Published var showGrid: Bool = false {
        didSet { savePreferences() }
    }
    
    @Published var showHistogram: Bool = true {
        didSet { savePreferences() }
    }
    
    @Published var audioEnabled: Bool = true {
        didSet { savePreferences() }
    }
    
    @Published var preferredAudioSampleRate: Double = 48000.0 {
        didSet { 
            savePreferences()
            updateAudioConfiguration()
        }
    }
    
    @Published var preferredAudioChannels: Int = 2 {
        didSet { 
            savePreferences()
            updateAudioConfiguration()
        }
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
    
    // Directory bookmark properties
    let directoryBookmarkKey = "directoryBookmarkKey" // Stays here
    @Published var captureDirectoryURL: URL? {
        didSet { savePreferences() }
    }

    // Add frame rate properties
    let desiredFramerates = [20, 24, 30, 60, 120]
    @Published var availableFramerates: [Int] = [20, 24, 30, 60, 120]  // Default values

    // Add video output properties
    var videoOutput: AVCaptureVideoDataOutput!
    let videoProcessingQueue = DispatchQueue(
        label: "com.pawagam.videoprocessing")
    
    // --- START: Audio Recording Properties ---
    var audioOutput: AVCaptureAudioDataOutput!
    var assetWriter: AVAssetWriter?
    var assetWriterInput: AVAssetWriterInput?
    let audioProcessingQueue = DispatchQueue(label: "com.pawagam.audioprocessing")
    var isAudioSessionStarted = false
    var audioFileURL: URL?
    var audioInput: AVCaptureDeviceInput?
    // --- NEW: Properties for high-quality audio ---
    var audioSampleRate: Double = 48000.0 // Default to high quality
    var audioChannelCount: Int = 2        // Default to stereo
    var isStereoSupported: Bool = false   // Track if device supports stereo recording
    // --- END: Audio Recording Properties ---

    // Histogram publisher
    @Published var histogramPublisher = PassthroughSubject<[CGFloat], Never>()
    
    
    // Histogram display options
    @Published var histogramMode: HistogramMode = .luminance {
        didSet { savePreferences() }
    }
    
    enum HistogramMode: String, CaseIterable {
        case luminance = "Luminance"
        case rgb = "RGB"
        case red = "Red"
        case green = "Green"
        case blue = "Blue"
    }
    

    @Published var isFocusLocked = false

    // Raw Format Support
    @Published var supportedRawPixelFormats: [OSType] = []
    @Published var selectedRawPixelFormat: OSType = 0
    
    // Exposure properties
    @Published var minISO: Float = 0.0
    @Published var maxISO: Float = 0.0
    var cancellables = Set<AnyCancellable>()


    @Published var elapsedTime: TimeInterval = 0

    var metricsTimer: Timer?
    var captureStartTime: Date?
    // Increased buffer size
    let maxBufferSize = 50  // Up from 100
    let maxMemoryFrames = 100 // Keep only recent frames in memory

    // New buffer management properties
    var frameDataCache = [Int: Data]()
    var diskCacheURL: URL?
    var isLowMemory = false

    // Enhanced threading system
    let rawProcessingQueue = DispatchQueue(
        label: "com.pawagam.rawprocessing",
        qos: .userInitiated,
        attributes: .concurrent)

    let jpegProcessingQueue = DispatchQueue(
        label: "com.pawagam.jpegprocessing",
        qos: .userInitiated,
        attributes: .concurrent)

    let fileSavingQueue = DispatchQueue(
        label: "com.pawagam.filesaving",
        qos: .userInitiated)

    // Prioritization
    var processingPriority = [Int: Bool]()
    let priorityQueue = DispatchQueue(
        label: "com.pawagam.priority",
        qos: .userInteractive)

    var pendingFrames = Set<Int>()  // Track all frames that need processing
    let finishQueue = DispatchQueue(
        label: "com.pawagam.finish")
    let maxWaitTime: TimeInterval = 10.0

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
    var photoOutput: AVCapturePhotoOutput!
    var captureDevice: AVCaptureDevice!

    // Focus Properties
    var focusTimer: Timer?
    let focusDuration: TimeInterval = 2.0

    // Capture Properties
    var captureTimer: DispatchSourceTimer?

    // Pipeline System
    let pipelineQueue = DispatchQueue(
        label: "com.pawagam.pipeline", qos: .userInitiated)
    let dngProcessingQueue = DispatchQueue(
        label: "com.pawagam.dngprocessing", qos: .userInitiated,
        attributes: .concurrent)

    var frameBuffer = [Int: Date]()  // frameID: timestamp
    var nextFrameID = 1
    var lastSavedFrameID = 0
    let bufferLock = NSLock()
    let pipelineSemaphore: DispatchSemaphore
    var captureGroup: DispatchGroup?

    // Capture Readiness
    let captureSerialQueue = DispatchQueue(
        label: "com.pawagam.captureserial")

    // File Management
    var documentsPath: URL {
        return FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
    }
    var captureDirectory: URL?
    
    // Make captureInterval computed rather than stored
    var captureInterval: TimeInterval {
       1.0 / Double(targetFPS)
    }

    // Initialization
    override init() {
        // Initialize semaphore first
        self.pipelineSemaphore = DispatchSemaphore(
            value: ProcessInfo.processInfo.processorCount
        )
        
        super.init()
        
        // --- NEW: Configure audio session early for high-quality input ---
        configureAudioSession()
        
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
    }
    
    // Permissions
    func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.resetFocus()
                } else {
                    self?.showError("Camera access is required for this app")
                }
            }
        }
        
        // Request audio permissions.
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                print("Audio permissions were not granted.")
                DispatchQueue.main.async {
                    self.showError("Audio permission is required to record sound.")
                }
            }
        }

        PHPhotoLibrary.requestAuthorization { status in
            // Handle photo library permission if needed
        }
    }

    // Thread-Safe UI Updates
    func updateStatusText(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }

    func updateCaptureCount(_ count: Int) {
        DispatchQueue.main.async {
            self.captureCount = count
        }
    }

    func updatePipelineStatus() {
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

    func showError(_ message: String) {
        DispatchQueue.main.async {
            self.alertMessage = message
            self.showAlert = true
        }
    }
    
    func updateAudioConfiguration() {
        guard audioEnabled else { return }
        
        deviceConfigurationQueue.async {
            self.configureAudioSession()
            DispatchQueue.main.async {
                // Reconfigure audio input with new settings
                if let audioInput = self.audioInput {
                    self.captureSession.removeInput(audioInput)
                }
                self.addAudioInput()
            }
        }
    }
}
