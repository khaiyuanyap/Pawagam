import AVFoundation
import SwiftUI

extension CameraManager {
    
    // MARK: - Focus Control
    
    func lockFocus() {
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

    func unlockFocus() {
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

    func resetFocus() {
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

    func resetFocusAfterDelay() {
        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(
            withTimeInterval: focusDuration, repeats: false
        ) { [weak self] _ in
            self?.resetToContinuousFocus()
        }
    }

    func resetToContinuousFocus() {
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
} 