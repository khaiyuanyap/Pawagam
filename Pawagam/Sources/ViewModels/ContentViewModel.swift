import Combine
import Foundation
import SwiftUI

class ContentViewModel: ObservableObject {
    var cameraManager = CameraManager()

    @Published var showSettings = false
    @Published var showISOPopup = false
    @Published var showShutterPopup = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        cameraManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // Standard Increments
    let standardISOs: [Double] = [
        24, 25, 50, 54, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800,
        1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000,
        10000, 12800, 16000, 20000, 25600, 32000, 40000, 51200,
    ]

    let standardShutterAngles: [Double] = [
        1, 2, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360,
    ]

    func roundToIncrement(_ value: Double, increments: [Double]) -> Double {
        guard !increments.isEmpty else { return value }
        let clampedValue = min(max(value, Double(cameraManager.minISO)), Double(cameraManager.maxISO))
        let first = increments[0]
        let last = increments[increments.count - 1]

        // Handle values outside the increments range
        if value <= first { return first }
        if value >= last { return last }

        // Binary search for the first element >= value
        var low = 0
        var high = increments.count - 1
        var index = increments.count // Default if not found (shouldn't happen due to bounds)

        while low <= high {
            let mid = (low + high) / 2
            if increments[mid] < value {
                low = mid + 1
            } else {
                index = mid
                high = mid - 1
            }
        }

        // Compare adjacent candidates for the closest increment
        let candidate1 = increments[index - 1]
        let candidate2 = increments[index]
        let diff1 = value - candidate1
        let diff2 = candidate2 - value

        return diff1 <= diff2 ? candidate1 : candidate2
    }
} 
