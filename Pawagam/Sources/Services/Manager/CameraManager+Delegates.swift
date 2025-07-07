import AVFoundation
import SwiftUI

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output == videoOutput {
            // Handle video buffer for histogram
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let histogramData = calculateHistogramData(from: pixelBuffer)
            DispatchQueue.main.async {
                self.histogramPublisher.send(histogramData)
            }
        } else if output == audioOutput && audioEnabled {
            // Handle audio buffer for recording
            handleAudioSampleBuffer(sampleBuffer)
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        pipelineQueue.async {
            let currentFrameID = self.nextFrameID
            self.nextFrameID += 1

            self.captureGroup?.enter()

            DispatchQueue.main.async {
                self.captureCount = currentFrameID
            }

            if let error = error {
                print("Error processing photo: \(error.localizedDescription)")
                self.handleFrameCompletion(frameID: currentFrameID, success: false)
                return
            }

            self.processFrame(photo, frameID: currentFrameID)
        }
    }
} 