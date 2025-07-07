import Foundation
import SwiftUI

// A placeholder for UserPreferences. In a real app, this might be in its own file.
struct UserPreferences {
    static let directoryBookmarkKey = "directoryBookmarkKey"
    static let showGridKey = "showGridKey"
    static let showHistogramKey = "showHistogramKey"
    static let targetFPSKey = "targetFPSKey"
    static let isoKey = "isoKey"
    static let shutterAngleKey = "shutterAngleKey"
    static let selectedCameraIDKey = "selectedCameraIDKey"
}



// URL Bookmark Extension
extension URL {
    func bookmarkData() -> Data? {
        do {
            return try self.bookmarkData(
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            print("Error creating bookmark: \(error.localizedDescription)")
            return nil
        }
    }
    
    static func fromBookmarkData(_ data: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return isStale ? nil : url
        } catch {
            print("Error resolving bookmark: \(error.localizedDescription)")
            return nil
        }
    }
}


extension CameraManager {
    
    // MARK: - File Management & Preferences
    
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
    
    func loadPreferences() {
        let defaults = UserDefaults.standard
        
        showGrid = defaults.bool(forKey: UserPreferences.showGridKey)
        showHistogram = defaults.bool(forKey: UserPreferences.showHistogramKey)
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
    
    func savePreferences() {
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
    
    func loadCaptureDirectory() {
        // This is now handled in loadPreferences()
    }
        
    func setCaptureDirectory(_ url: URL) {
        captureDirectoryURL = url
    }
    
    @objc func handleMemoryWarning() {
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

    func setupDiskCache() {
        let tempDir = FileManager.default.temporaryDirectory
        diskCacheURL = tempDir.appendingPathComponent("Pagawam_Cache")

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
}

extension UserDefaults {
    func bool(forKey defaultName: String, defaultValue: Bool) -> Bool {
        if object(forKey: defaultName) == nil {
            return defaultValue
        }
        return bool(forKey: defaultName)
    }

    func integer(forKey defaultName: String, defaultValue: Int) -> Int {
        if object(forKey: defaultName) == nil {
            return defaultValue
        }
        return integer(forKey: defaultName)
    }

    func float(forKey defaultName: String, defaultValue: Float) -> Float {
        if object(forKey: defaultName) == nil {
            return defaultValue
        }
        return float(forKey: defaultName)
    }

    func double(forKey defaultName: String, defaultValue: Double) -> Double {
        if object(forKey: defaultName) == nil {
            return defaultValue
        }
        return double(forKey: defaultName)
    }
} 
