import AVFoundation
import Combine

extension CameraManager {
    
    // MARK: - Exposure Control
    
    var desiredExposureDuration: CMTime {
        // USE CURRENT TARGET FPS
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
    
    func setupExposureObservers() {
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
    
    func setExposure(iso: Float) {
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

    func setShutterAngle(_ angle: Double) {
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