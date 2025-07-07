import AVFoundation
import SwiftUI

extension CameraManager {
    
    // MARK: - Capture Control
    
    func startCapture() {
        elapsedTime = 0

        captureStartTime = Date()
        metricsTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0, repeats: true
        ) { [weak self] _ in
            guard let self = self, let startTime = self.captureStartTime else { return }
            self.elapsedTime = Date().timeIntervalSince(startTime)
        }

        pendingFrames.removeAll()
        let baseDirectory = captureDirectoryURL ?? documentsPath.appendingPathComponent("DNG_Captures")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        captureDirectory = baseDirectory.appendingPathComponent("Capture_\(timestamp)")

        guard var captureDir = captureDirectory else { return }

        do {
            try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            try captureDir.setResourceValues(resourceValues)
            print("Created capture directory: \(captureDir.path)")
        } catch {
            showError("Failed to create capture directory: \(error.localizedDescription)")
            return
        }
        
        // --- START: Setup Audio Writer ---
        setupAudioWriter()
        // --- END: Setup Audio Writer ---

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

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.pawagam.capturetimer"))
        timer.schedule(deadline: .now(), repeating: captureInterval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.capturePhoto() }
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
        
        // --- START: Finish Audio Recording ---
        // Finish audio writing first as it's quick
        finishAudioRecording()
        // --- END: Finish Audio Recording ---

        finishQueue.async { [weak self] in
            guard let self = self else { return }

            let result = self.captureGroup?.wait(timeout: .now() + self.maxWaitTime)

            if result == .timedOut {
                print("Timeout waiting for DNG frames to finish")
                self.bufferLock.lock()
                let remainingFrames = self.pendingFrames
                self.bufferLock.unlock()
                for frameID in remainingFrames {
                    print("Force completing frame \(frameID)")
                    self.captureGroup?.leave()
                }
            }

            self.bufferLock.lock()
            self.pendingFrames.removeAll()
            self.frameBuffer.removeAll()
            self.bufferLock.unlock()

            DispatchQueue.main.async {
                self.isFinishing = false
                self.updateStatusText("Ready")
                self.showCaptureComplete = true
            }

            self.unlockFocus()
            self.unlockWhiteBalance()
        }
    }
    
    func capturePhoto() {
        bufferLock.lock()
        let currentBufferSize = frameBuffer.count
        bufferLock.unlock()

        if currentBufferSize >= maxBufferSize {
            print("Skipping capture: buffer full (\(currentBufferSize)/\(maxBufferSize))")
            return
        }

        captureSerialQueue.async {
            self.bufferLock.lock()
            let currentBufferSize = self.frameBuffer.count
            self.bufferLock.unlock()

            if currentBufferSize >= self.maxBufferSize {
                print("Skipping capture: buffer full (\(currentBufferSize)/\(self.maxBufferSize))")
                return
            }

            let photoSettings: AVCapturePhotoSettings
            if self.supportedRawPixelFormats.isEmpty {
                photoSettings = AVCapturePhotoSettings()
            } else {
                photoSettings = AVCapturePhotoSettings(rawPixelFormatType: self.selectedRawPixelFormat)
            }
            photoSettings.isHighResolutionPhotoEnabled = false
            photoSettings.flashMode = .off
            if #available(iOS 14.0, *), self.photoOutput.isShutterSoundSuppressionSupported {
                photoSettings.isShutterSoundSuppressionEnabled = true
            }

            DispatchQueue.main.async {
                self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
            }
        }
    }
} 
