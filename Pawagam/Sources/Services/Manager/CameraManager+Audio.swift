import AVFoundation

extension CameraManager {
    
    // MARK: - Audio Handling
    
    // NEW: Configures the shared audio session for stereo recording.
    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Use .playAndRecord category for stereo recording
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
            
            // Use the user's preferred sample rate
            try session.setPreferredSampleRate(self.preferredAudioSampleRate)
            
            try session.setActive(true)
            
            // Configure stereo recording
            configureStereoRecording()
            
            print("AVAudioSession configured for stereo recording.")
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }
    
    // Configure stereo audio recording
    func configureStereoRecording() {
        let session = AVAudioSession.sharedInstance()
        
        // Find and enable built-in microphone
        enableBuiltInMic()
        
        // Configure stereo directionality
        configureMicrophoneDirectionality()
    }
    
    private func enableBuiltInMic() {
        let session = AVAudioSession.sharedInstance()
        
        // Find the built-in microphone input
        guard let availableInputs = session.availableInputs,
              let builtInMicInput = availableInputs.first(where: { $0.portType == .builtInMic }) else {
            print("The device must have a built-in microphone.")
            return
        }
        
        // Make the built-in microphone input the preferred input
        do {
            try session.setPreferredInput(builtInMicInput)
            print("Built-in microphone set as preferred input.")
        } catch {
            print("Unable to set the built-in mic as the preferred input: \(error)")
        }
    }
    
    private func configureMicrophoneDirectionality() {
        let session = AVAudioSession.sharedInstance()
        
        // Initialize stereo support to false
        self.isStereoSupported = false
        
        guard let preferredInput = session.preferredInput,
              let dataSources = preferredInput.dataSources else {
            print("No data sources available for preferred input.")
            return
        }
        
        // Try to find a data source that supports stereo
        for dataSource in dataSources {
            guard let supportedPolarPatterns = dataSource.supportedPolarPatterns else { continue }
            
            do {
                if supportedPolarPatterns.contains(.stereo) {
                    // Set the preferred polar pattern to stereo
                    try dataSource.setPreferredPolarPattern(.stereo)
                    
                    // Set this as the preferred data source
                    try preferredInput.setPreferredDataSource(dataSource)
                    
                    // Set input orientation to match device orientation
                    try session.setPreferredInputOrientation(.landscapeLeft)
                    
                    // Mark stereo as supported
                    self.isStereoSupported = true
                    
                    print("Stereo recording configured with data source: \(dataSource.dataSourceName)")
                    return
                } else {
                    // Fall back to omnidirectional for better audio quality
                    if supportedPolarPatterns.contains(.omnidirectional) {
                        try dataSource.setPreferredPolarPattern(.omnidirectional)
                        try preferredInput.setPreferredDataSource(dataSource)
                        print("Omnidirectional recording configured with data source: \(dataSource.dataSourceName)")
                    }
                }
            } catch {
                print("Error configuring data source \(dataSource.dataSourceName): \(error)")
            }
        }
    }
    
    // MODIFIED: Gets audio device and sets quality parameters from the active session.
    func addAudioInput() {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("Could not find default audio device.")
            return
        }
        
        // Update sample rate and channel count based on user preferences and stereo support
        let session = AVAudioSession.sharedInstance()
        
        // Use preferred settings if available, fallback to hardware capabilities
        self.audioSampleRate = self.preferredAudioSampleRate
        
        // Use the stereo support flag that was set during audio session configuration
        if isStereoSupported && preferredAudioChannels == 2 {
            self.audioChannelCount = 2 // Use stereo
        } else {
            self.audioChannelCount = 1 // Fall back to mono
        }
        
        print("Audio configuration: \(audioSampleRate) Hz, \(audioChannelCount) channels, stereo supported: \(isStereoSupported)")

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