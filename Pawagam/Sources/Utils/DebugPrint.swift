import Foundation

// Global debug printing override
#if DEBUG
private let isPrintingEnabled = true
#else
private let isPrintingEnabled = false
#endif

// Override the global print function
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    if isPrintingEnabled {
        Swift.print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
    }
}