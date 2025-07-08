import AVFoundation
import SwiftUI

extension CameraManager {
    
    // MARK: - Camera Configuration
    
    func discoverCameras() {
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
             
             // Add the audio input back if enabled
             if self.audioEnabled {
                 self.addAudioInput()
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
            
            // Enforce manual exposure after camera change
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.updateExposureSettings()
                self.enforceManualExposure()
            }
            
            // Update UI
            DispatchQueue.main.async {
                self.currentCameraType = selectedCamera.deviceType == .builtInTelephotoCamera ? "Telephoto" :
                                         selectedCamera.deviceType == .builtInUltraWideCamera ? "Ultra-wide" : "Wide"
                self.pixelFormatName = newPixelFormatName
            }
        }
    }
    
    // Update to include all desired frame rates
    func updateAvailableFrameRates() {
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
    
    // Camera Setup
    func setupCamera() {
        setupMetal()
        discoverCameras()
        
        captureSession.beginConfiguration()
        
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
        
        // Add audio output for recording if enabled
        if audioEnabled {
            addAudioInput()
            audioOutput = AVCaptureAudioDataOutput()
            if captureSession.canAddOutput(audioOutput) {
                audioOutput.setSampleBufferDelegate(self, queue: audioProcessingQueue)
                captureSession.addOutput(audioOutput)
                print("Audio output added to session.")
            } else {
                print("Could not add audio output to session.")
            }
        }


        captureSession.sessionPreset = .photo
        
        // Set continuous autofocus by default
        setContinuousAutofocus()
        
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
            captureSession.commitConfiguration()
            return
        }

        captureDevice = camera

        do {
            deviceConfigurationQueue.sync {
                do {
                    try captureDevice.lockForConfiguration()
                    minISO = captureDevice.activeFormat.minISO
                    maxISO = captureDevice.activeFormat.maxISO
                    
                    if captureDevice.isExposureModeSupported(.custom) {
                        captureDevice.exposureMode = .custom
                    }
                    
                    captureDevice.unlockForConfiguration()
                } catch {
                    print("Error getting ISO range: \(error)")
                }
            }
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
            captureSession.commitConfiguration()
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
        
        captureSession.commitConfiguration()

        // Start session
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.updateExposureSettings()
                self.enforceManualExposure()
            }
        }
    }
    
    func configureCamera() {
        deviceConfigurationQueue.async { [weak self] in
            guard let self = self, let device = self.captureDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                // DISABLE ALL AUTOMATIC ADJUSTMENTS
                device.automaticallyAdjustsVideoHDREnabled = false
                
                // Configure autofocus ONLY
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                // LOCK WHITE BALANCE - NO AUTO ADJUSTMENTS
                if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }

                // Set frame rate for high-speed capture
                if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= Double(self.targetFPS) }) {
                    let timeValue = CMTimeValue(1)
                    let timeScale = CMTimeScale(self.targetFPS)
                    device.activeVideoMinFrameDuration = CMTime(value: timeValue, timescale: timeScale)
                    device.activeVideoMaxFrameDuration = CMTime(value: timeValue, timescale: timeScale)
                }
                
                // FORCE CUSTOM EXPOSURE MODE - NO AUTO EXPOSURE
                device.exposureMode = .custom
                
                // DISABLE EXPOSURE POINT OF INTEREST
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) // Center
                    device.exposureMode = .custom // Ensure it stays custom
                }
                
                // Apply manual exposure settings
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
} 
