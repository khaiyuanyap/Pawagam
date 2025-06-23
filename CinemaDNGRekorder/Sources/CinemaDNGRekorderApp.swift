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

// Global variable to control printing
var isPrintingEnabled = true

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
