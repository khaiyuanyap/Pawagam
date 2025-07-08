import AVFoundation
import Metal
import MetalKit

extension CameraManager {
    
    // MARK: - Histogram
    
    func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
        metalDevice = device
        metalCommandQueue = device.makeCommandQueue()
        
        // Create texture cache
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textureCache)
        
        // Create histogram buffer
        histogramBuffer = metalDevice.makeBuffer(length: 256 * MemoryLayout<UInt32>.size,
                                                options: .storageModeShared)
        
        // Load compute shader
        guard let library = metalDevice.makeDefaultLibrary(),
              let function = library.makeFunction(name: "luminanceHistogram") else {
            print("Failed to create Metal shader")
            return
        }
        
        do {
            histogramPipeline = try metalDevice.makeComputePipelineState(function: function)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    // Method to calculate histogram from camera buffer
    func updateHistogram(from pixelBuffer: CVPixelBuffer) {
        // Calculate histogram data and publish
        let histogramData = calculateHistogramData(from: pixelBuffer)
        histogramPublisher.send(histogramData)
    }

    // Histogram calculation function
    func calculateHistogramData(from pixelBuffer: CVPixelBuffer) -> [CGFloat] {
        guard histogramSemaphore.wait(timeout: .now() + 0.1) == .success else {
            return Array(repeating: 0, count: 64)
        }
        defer { histogramSemaphore.signal() }
        
        switch histogramMode {
        case .luminance:
            return calculateLuminanceHistogram(from: pixelBuffer)
        case .rgb:
            return calculateRGBHistogram(from: pixelBuffer)
        case .red:
            return calculateChannelHistogram(from: pixelBuffer, channel: 0)
        case .green:
            return calculateChannelHistogram(from: pixelBuffer, channel: 1)
        case .blue:
            return calculateChannelHistogram(from: pixelBuffer, channel: 2)
        }
    }
    
    private func calculateLuminanceHistogram(from pixelBuffer: CVPixelBuffer) -> [CGFloat] {
        // Reset histogram buffer
        let bufferPtr = histogramBuffer.contents().bindMemory(to: UInt32.self, capacity: 256)
        memset(bufferPtr, 0, 256 * MemoryLayout<UInt32>.size)
        
        // Create Metal texture
        guard let textureCache = textureCache,
              let metalTexture = createMetalTexture(from: pixelBuffer, using: textureCache) else {
            return Array(repeating: 0, count: 64)
        }
        
        // Process with Metal
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return Array(repeating: 0, count: 64)
        }
        
        commandEncoder.setComputePipelineState(histogramPipeline)
        commandEncoder.setTexture(metalTexture, index: 0)
        commandEncoder.setBuffer(histogramBuffer, offset: 0, index: 0)
        
        // Configure threadgroups
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupCount = MTLSize(
            width: (metalTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (metalTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        commandEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Convert to normalized [0,1] values
        let bins = (0..<64).map { CGFloat(bufferPtr[$0 * 4]) } // 256 bins → 64 bins
        guard let maxValue = bins.max(), maxValue > 0 else {
            return Array(repeating: 0, count: 64)
        }
        
        return bins.map { $0 / CGFloat(maxValue) }
    }
    
    private func calculateRGBHistogram(from pixelBuffer: CVPixelBuffer) -> [CGFloat] {
        // For RGB mode, interleave R, G, B values in groups of 3
        let redBins = calculateChannelHistogram(from: pixelBuffer, channel: 0)
        let greenBins = calculateChannelHistogram(from: pixelBuffer, channel: 1)
        let blueBins = calculateChannelHistogram(from: pixelBuffer, channel: 2)
        
        // Interleave the channels for RGB display (simplified to 21 bins per channel)
        var rgbBins: [CGFloat] = []
        let binsPerChannel = 21
        
        for i in 0..<binsPerChannel {
            let index = i * 64 / binsPerChannel
            rgbBins.append(redBins[min(index, redBins.count - 1)])
            rgbBins.append(greenBins[min(index, greenBins.count - 1)])
            rgbBins.append(blueBins[min(index, blueBins.count - 1)])
        }
        
        // Pad to 64 bins if needed
        while rgbBins.count < 64 {
            rgbBins.append(0)
        }
        
        return Array(rgbBins.prefix(64))
    }
    
    private func calculateChannelHistogram(from pixelBuffer: CVPixelBuffer, channel: Int) -> [CGFloat] {
        // CPU-based calculation for individual color channels
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return Array(repeating: 0, count: 64)
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        var histogram = Array<Int>(repeating: 0, count: 256)
        
        let pixels = baseAddress.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
        
        // Sample every 4th pixel for performance
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let pixelIndex = y * bytesPerRow + x * 4
                let channelValue = pixels[pixelIndex + channel]
                histogram[Int(channelValue)] += 1
            }
        }
        
        // Convert to 64 bins and normalize
        let bins = (0..<64).map { binIndex in
            let startIndex = binIndex * 4
            let endIndex = min(startIndex + 4, 256)
            return histogram[startIndex..<endIndex].reduce(0, +)
        }
        
        guard let maxValue = bins.max(), maxValue > 0 else {
            return Array(repeating: 0, count: 64)
        }
        
        return bins.map { CGFloat($0) / CGFloat(maxValue) }
    }

    func createMetalTexture(from pixelBuffer: CVPixelBuffer, using textureCache: CVMetalTextureCache) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvMetalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvMetalTexture
        )
        
        guard status == kCVReturnSuccess,
              let unwrappedTexture = cvMetalTexture,
              let texture = CVMetalTextureGetTexture(unwrappedTexture) else {
            return nil
        }
        
        return texture
    }
} 