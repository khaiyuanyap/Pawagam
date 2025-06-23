import AVFoundation

extension CameraManager {
    
    // MARK: - White Balance Control
    
    func lockWhiteBalance() {
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

    func unlockWhiteBalance() {
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
} 