import AVFoundation

extension CameraManager {
    
    // MARK: - Audio Handling
    
    // NEW: Configures the shared audio session for recording.
    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Use .videoRecording mode to optimize microphone selection and processing.
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
            
            // Prefer a high sample rate. The actual rate will be determined by the hardware.
            try session.setPreferredSampleRate(48000)
            
            try session.setActive(true)
            print("AVAudioSession configured for high-quality recording.")
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
            // Optionally show an error to the user.
        }
    }
    
    // MODIFIED: Gets audio device and sets quality parameters from the active session.
    func addAudioInput() {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("Could not find default audio device.")
            return
        }
        
        // Update sample rate and channel count based on the active audio session's properties.
        let session = AVAudioSession.sharedInstance()
        self.audioSampleRate = session.sampleRate // Use the session's actual hardware sample rate.
        self.audioChannelCount = min(session.inputNumberOfChannels, 2) // Use session's channels, max 2 for stereo.
        if self.audioChannelCount == 0 { self.audioChannelCount = 1 } // Failsafe for mono.

        print("Audio hardware configuration: \(audioSampleRate) Hz, \(audioChannelCount) channels.")

        do {
            let input = try AVCaptureDeviceInput(device: audioDevice)
            if captureSession.canAddInput(input) {
                // If an old audio input exists, remove it before adding the new one.
                if let existingAudioInput = self.audioInput {
                    captureSession.removeInput(existingAudioInput)
                }
                captureSession.addInput(input)
                self.audioInput = input
                print("Audio input added to session.")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }
    }
    
    // MODIFIED: Configures the writer for uncompressed LPCM in a .wav container.
    func setupAudioWriter() {
        guard let captureDir = captureDirectory else { return }
        // Create audio file name from the capture directory name
        let directoryName = captureDir.lastPathComponent
        let audioFileName = "\(directoryName)_audio.wav"
        audioFileURL = captureDir.appendingPathComponent(audioFileName)
        
        do {
            // Use .wav file type
            assetWriter = try AVAssetWriter(url: audioFileURL!, fileType: .wav)
            
            // Define settings for uncompressed LPCM audio (high quality)
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: audioSampleRate,
                AVNumberOfChannelsKey: audioChannelCount,
                AVLinearPCMBitDepthKey: 24, // 24-bit is a pro-audio standard
                AVLinearPCMIsBigEndianKey: false, // Standard for WAV on Apple platforms
                AVLinearPCMIsFloatKey: false, // Use float PCM
                AVLinearPCMIsNonInterleaved: false // Standard interleaved format
            ]
            
            print("Using audio settings: \(audioSettings)")
            
            assetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            assetWriterInput?.expectsMediaDataInRealTime = true
            
            if let writerInput = assetWriterInput, let writer = assetWriter, writer.canAdd(writerInput) {
                writer.add(writerInput)
                writer.startWriting()
                isAudioSessionStarted = false // Reset session flag
                print("Audio writer started for high-quality WAV.")
            } else {
                print("Could not add asset writer input for WAV.")
                assetWriter = nil
            }
        } catch {
            print("Failed to create asset writer for WAV: \(error)")
            assetWriter = nil
        }
    }
    
    func finishAudioRecording() {
        audioProcessingQueue.async { [weak self] in
            guard let self = self, let writer = self.assetWriter, writer.status == .writing else {
                return
            }
            
            self.assetWriterInput?.markAsFinished()
            writer.finishWriting {
                DispatchQueue.main.async {
                    if writer.status == .completed {
                        print("Audio file saved successfully to \(self.audioFileURL?.lastPathComponent ?? "N/A")")
                    } else {
                        print("Failed to save audio file. Error: \(writer.error?.localizedDescription ?? "Unknown error")")
                    }
                    self.assetWriter = nil
                    self.assetWriterInput = nil
                    self.audioFileURL = nil
                }
            }
        }
    }
    
    func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isCapturing,
              let writer = assetWriter,
              let writerInput = assetWriterInput,
              writer.status == .writing
        else { return }
        
        if !isAudioSessionStarted {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: startTime)
            isAudioSessionStarted = true
        }
        
        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sampleBuffer)
        }
    }
} 