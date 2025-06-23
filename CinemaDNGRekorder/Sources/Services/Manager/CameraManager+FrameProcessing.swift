import AVFoundation
import UIKit

extension CameraManager {
    
    // MARK: - Frame Processing
    
    func processFrame(_ photo: AVCapturePhoto, frameID: Int) {
        pipelineQueue.async {
            self.bufferLock.lock()
            self.pendingFrames.insert(frameID)
            self.frameBuffer[frameID] = Date()
            self.bufferLock.unlock()
            self.updatePipelineStatus()

            if self.supportedRawPixelFormats.contains(where: {
                $0 == self.selectedRawPixelFormat
            }) {
                self.processRawFrame(photo, frameID: frameID)
            } else {
                self.processJPEGFrame(photo, frameID: frameID)
            }
        }
    }

    func processRawFrame(_ photo: AVCapturePhoto, frameID: Int) {
        pipelineSemaphore.wait()
        rawProcessingQueue.async {
            defer { self.pipelineSemaphore.signal() }
            
            guard let dngData = photo.fileDataRepresentation() else {
                self.handleFrameCompletion(frameID: frameID, success: false)
                return
            }
            
            self.savingSemaphore.wait()
            self.fileSavingQueue.async {
                defer { self.savingSemaphore.signal() }
                self.saveDNGData(dngData, frameID: frameID)
            }
        }
    }

    func processJPEGFrame(_ photo: AVCapturePhoto, frameID: Int) {
        pipelineSemaphore.wait()
        jpegProcessingQueue.async {
            defer { self.pipelineSemaphore.signal() }

            guard let cgImage = photo.previewCGImageRepresentation() else {
                self.handleFrameCompletion(frameID: frameID, success: false)
                return
            }

            let uiImage = UIImage(cgImage: cgImage)
            guard let jpegData = uiImage.jpegData(compressionQuality: 0.9) else {
                self.handleFrameCompletion(frameID: frameID, success: false)
                return
            }
            // Note: JPEG data is generated but not saved here in this branch.
            // Assuming the main path is raw processing.
        }
    }

    func processImageData(_ photo: AVCapturePhoto, frameID: Int) {
        if let dngData = photo.fileDataRepresentation() {
            self.saveDNGData(dngData, frameID: frameID)
        } else if let cgImage = photo.previewCGImageRepresentation() {
            self.saveProcessedData(cgImage, frameID: frameID)
        } else {
            print("Failed to get any image data for frame \(frameID)")
            self.handleFrameCompletion(frameID: frameID, success: false)
        }
    }
    
    func saveDNGData(_ dngData: Data, frameID: Int) {
        guard let captureDir = captureDirectory else { return }
        
        let filename = String(format: "IMG_%04d.dng", frameID)
        let fileURL = captureDir.appendingPathComponent(filename)
        
        do {
            try dngData.write(to: fileURL)
            handleFrameCompletion(frameID: frameID, success: true)
        } catch {
            handleFrameCompletion(frameID: frameID, success: false)
        }
    }

    func saveProcessedData(_ cgImage: CGImage, frameID: Int) {
        guard let captureDir = captureDirectory else {
            self.handleFrameCompletion(frameID: frameID, success: false)
            return
        }

        let filename = String(format: "IMG_%04d.jpg", frameID)
        let fileURL = captureDir.appendingPathComponent(filename)

        do {
            let uiImage = UIImage(cgImage: cgImage)
            if let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
                try jpegData.write(to: fileURL)
                print("Saved JPEG: \(filename)")
                self.handleFrameCompletion(frameID: frameID, success: true)
            } else {
                throw NSError(
                    domain: "ImageProcessing", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Failed to create JPEG data"
                    ])
            }
        } catch {
            print("Error saving JPEG file: \(error.localizedDescription)")
            self.handleFrameCompletion(frameID: frameID, success: false)
        }
    }

    func handleFrameCompletion(frameID: Int, success: Bool) {
        pipelineQueue.async {
            self.bufferLock.lock()
            self.pendingFrames.remove(frameID)
            self.frameBuffer.removeValue(forKey: frameID)
            self.frameDataCache.removeValue(forKey: frameID)

            let cacheFile = self.diskCacheURL!.appendingPathComponent("frame_\(frameID).dng")
            if FileManager.default.fileExists(atPath: cacheFile.path) {
                try? FileManager.default.removeItem(at: cacheFile)
            }

            self.lastSavedFrameID = max(self.lastSavedFrameID, frameID)
            self.bufferLock.unlock()

            self.updatePipelineStatus()
            self.captureGroup?.leave()

            if !success {
                DispatchQueue.main.async {
                    self.errorCount += 1
                }
            }
        }
    }
} 