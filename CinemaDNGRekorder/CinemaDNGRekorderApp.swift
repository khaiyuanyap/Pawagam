//
//  CinemaDNGRekorderApp.swift
//  CinemaDNGRekorder
//
//  Created by Khai Yuan Yap on 12/06/2025.
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

// Add this outside any class/struct in the file
func formatTimeInterval(_ interval: TimeInterval) -> String {
    let minutes = Int(interval) / 60
    let seconds = Int(interval) % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

// User Preferences Keys
struct UserPreferences {
    static let showGridKey = "showGrid"
    static let showHistogramKey = "showHistogram"
    static let targetFPSKey = "targetFPS"
    static let isoKey = "iso"
    static let shutterAngleKey = "shutterAngle"
    static let directoryBookmarkKey = "captureDirectoryBookmark"
}

// UserDefaults Extension
extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if let value = self.value(forKey: key) as? Bool {
            return value
        }
        return defaultValue
    }
    
    func integer(forKey key: String, defaultValue: Int) -> Int {
        if let value = self.value(forKey: key) as? Int {
            return value
        }
        return defaultValue
    }
    
    func float(forKey key: String, defaultValue: Float) -> Float {
        if let value = self.value(forKey: key) as? Float {
            return value
        }
        return defaultValue
    }
    
    func double(forKey key: String, defaultValue: Double) -> Double {
        if let value = self.value(forKey: key) as? Double {
            return value
        }
        return defaultValue
    }
}

// Global variable to control printing
var isPrintingEnabled = false

// Override the standard print function
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    guard isPrintingEnabled else { return }
    
    // Reconstruct the output string
    let output = items.map { "\($0)" }.joined(separator: separator)
    
    // Call the original print function from Swift standard library
    Swift.print(output, terminator: terminator)
}


// Main App
@main
struct DNGCameraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
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

// Extension for safe array access
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}


// Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
