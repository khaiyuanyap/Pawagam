import AVFoundation
import Combine

extension CameraManager {
    
    // MARK: - Manual Exposure Control (NO AUTO EXPOSURE)
    
    var desiredExposureDuration: CMTime {
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        let exposureDurationSeconds = (shutterAngle / 360.0) * Double(frameDuration.seconds)
        return CMTime(seconds: exposureDurationSeconds, preferredTimescale: 1_000_000)
    }
    
    func updateExposureSettings() {
        guard let device = captureDevice else { return }
        
        // Clamp ISO to valid range
        let clampedISO = max(minISO, min(iso, maxISO))
        
        deviceConfigurationQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                try device.lockForConfiguration()
                
                // FORCE CUSTOM EXPOSURE MODE - NO AUTO EXPOSURE
                device.exposureMode = .custom
                
                // Set manual exposure using user preferences
                device.setExposureModeCustom(duration: self.desiredExposureDuration, iso: clampedISO)
                
                device.unlockForConfiguration()
                
                // Update published ISO if clamping occurred
                if clampedISO != self.iso {
                    DispatchQueue.main.async {
                        self.iso = clampedISO
                    }
                }
            } catch {
                print("Error setting manual exposure: \(error.localizedDescription)")
            }
        }
    }
    
    func setupExposureObservers() {
        $iso
            .dropFirst()
            .sink { [weak self] newISO in
                self?.setManualExposure(iso: newISO)
            }
            .store(in: &cancellables)

        $shutterAngle
            .dropFirst()
            .sink { [weak self] newAngle in
                self?.setManualShutterAngle(newAngle)
            }
            .store(in: &cancellables)
    }
    
    func setManualExposure(iso: Float) {
        guard let device = captureDevice else { return }
        
        let clampedISO = max(minISO, min(iso, maxISO))

        deviceConfigurationQueue.async {
            do {
                try device.lockForConfiguration()
                
                // MANUAL EXPOSURE ONLY - Keep current duration, set new ISO
                device.setExposureModeCustom(duration: device.exposureDuration, iso: clampedISO)
                
                device.unlockForConfiguration()
            } catch {
                print("Error setting manual ISO: \(error.localizedDescription)")
            }
        }
    }

    func setManualShutterAngle(_ angle: Double) {
        guard let device = captureDevice else { return }

        deviceConfigurationQueue.async {
            do {
                try device.lockForConfiguration()

                // Calculate exposure duration from shutter angle
                let frameDuration = CMTime(value: 1, timescale: CMTimeScale(self.targetFPS))
                let exposureDurationSeconds = (angle / 360.0) * Double(frameDuration.seconds)
                let exposureDuration = CMTime(seconds: exposureDurationSeconds, preferredTimescale: 1_000_000)

                // MANUAL EXPOSURE ONLY - Set duration, keep current ISO
                device.setExposureModeCustom(duration: exposureDuration, iso: device.iso)

                device.unlockForConfiguration()
            } catch {
                print("Error setting manual shutter angle: \(error.localizedDescription)")
            }
        }
    }
    
    func enforceManualExposure() {
        guard let device = captureDevice else { return }
        
        deviceConfigurationQueue.async {
            do {
                try device.lockForConfiguration()
                
                // AGGRESSIVE MANUAL EXPOSURE ENFORCEMENT
                device.exposureMode = .custom
                
                // DISABLE ALL AUTO EXPOSURE FEATURES
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                
                // FORCE MANUAL VALUES
                device.setExposureModeCustom(duration: self.desiredExposureDuration, iso: self.iso)
                
                // ENSURE IT STAYS CUSTOM
                device.exposureMode = .custom
                
                device.unlockForConfiguration()
                print("✅ MANUAL EXPOSURE ENFORCED - ISO: \(self.iso), Shutter: \(self.shutterAngle)°, Mode: \(device.exposureMode.rawValue)")
            } catch {
                print("❌ Error enforcing manual exposure: \(error.localizedDescription)")
            }
        }
    }
    
    func startContinuousExposureEnforcement() {
        // Cancel any existing timer
        continuousExposureTimer?.invalidate()
        
        // Start timer to continuously enforce manual exposure
        continuousExposureTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let device = self.captureDevice else { return }
            
            // Check if exposure mode has changed from custom
            if device.exposureMode != .custom {
                print("⚠️ EXPOSURE MODE CHANGED TO: \(device.exposureMode.rawValue) - RE-ENFORCING MANUAL")
                self.enforceManualExposure()
            }
        }
    }
    
    func stopContinuousExposureEnforcement() {
        continuousExposureTimer?.invalidate()
        continuousExposureTimer = nil
    }
} 