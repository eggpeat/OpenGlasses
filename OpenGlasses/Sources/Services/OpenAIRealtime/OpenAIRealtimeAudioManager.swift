import AVFoundation
import Foundation

/// Audio engine for OpenAI Realtime mode.
/// Both input and output use 24kHz Int16 PCM mono (OpenAI's native format).
/// Includes client-side amplitude-based voice activity detection for fast interrupts.
///
/// Self-healing across OS audio interruptions (phone calls, Siri) and Bluetooth/LE-Audio route
/// changes: the `AVAudioEngine` is kept permanent for the manager's lifetime (teardown only stops
/// and detaches child nodes), all graph mutations run on a single serial lifecycle queue, and a
/// generation counter discards stale tap buffers so audio from a torn-down session can't bleed into
/// the next one. The interruption/route → action decisions live in pure, tested policies
/// (`AudioInterruptionPolicy`, `AudioRoutePolicy`); this class only executes them.
final class OpenAIRealtimeAudioManager {
    var onAudioCaptured: ((Data) -> Void)?

    /// Fires when the user's voice amplitude exceeds the interrupt threshold
    /// while the model is speaking. Faster than waiting for server VAD.
    var onVoiceInterrupt: (() -> Void)?

    // Keep the engine container permanent for the manager's lifetime. Teardown only stops and
    // detaches child nodes; it never nils or replaces this engine.
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    // All engine-graph mutations run here so observer-driven recovery can't race start/stop.
    private let audioLifecycleQueue = DispatchQueue(label: "openai.audio.lifecycle", qos: .userInitiated)
    private let audioLifecycleQueueKey = DispatchSpecificKey<Void>()

    private var isCapturing = false
    private var isInputTapInstalled = false
    private var isPlayerNodeAttached = false
    private var useIPhoneMode = false
    /// Bumped on every (re)start and teardown; tags tap buffers so stale ones are dropped.
    private var audioGraphGeneration: UInt64 = 0
    /// Our claim on the shared session, held while the conversation owns the mic.
    private var sessionLease: AudioSessionLease?

    // Audio format: 24kHz PCM16 mono for both directions
    static let sampleRate: Double = 24000
    static let channels: UInt32 = 1
    static let bitsPerSample: UInt32 = 16

    // Accumulate resampled PCM into ~100ms chunks before sending
    private let sendQueue = DispatchQueue(label: "openai.audio.accumulator")
    private var accumulatedData = Data()
    private var accumulatorGeneration: UInt64 = 0
    private let minSendBytes = 4800  // 100ms at 24kHz mono Int16 = 2400 frames * 2 bytes

    // Client-side VAD for interruption
    private var isModelCurrentlySpeaking = false
    private let interruptAmplitudeThreshold: Float = 0.05
    private var consecutiveHighFrames = 0
    private let requiredHighFrames = 3  // ~3 buffers above threshold to trigger

    private var observers: [NSObjectProtocol] = []

    init() {
        audioLifecycleQueue.setSpecific(key: audioLifecycleQueueKey, value: ())
    }

    deinit {
        removeObservers()
    }

    /// Set this from the session manager to enable/disable interrupt detection.
    var modelSpeaking: Bool {
        get { isModelCurrentlySpeaking }
        set {
            isModelCurrentlySpeaking = newValue
            if !newValue { consecutiveHighFrames = 0 }
        }
    }

    /// Configure the audio session for OpenAI Realtime.
    func setupAudioSession(useIPhoneMode: Bool = false) throws {
        self.useIPhoneMode = useIPhoneMode
        let session = AVAudioSession.sharedInstance()
        guard AVAudioApplication.shared.recordPermission != .denied else {
            throw AudioSessionError.microphonePermissionDenied
        }
        let mode: AVAudioSession.Mode = useIPhoneMode ? .voiceChat : .videoChat
        // Acquire the shared session through the coordinator (single owner); supersedes any prior
        // holder and lets a clean `release` deactivate it for whoever runs next (e.g. wake word).
        sessionLease = try AudioSessionCoordinator.shared.acquire(
            .openAIRealtime,
            category: .playAndRecord,
            mode: mode,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        ) { session in
            // Preferred rate/buffer are hints — a rejected hint must not abort activation.
            try? session.setPreferredSampleRate(Self.sampleRate)
            try? session.setPreferredIOBufferDuration(0.064)
        }
        applyRoutePolicy(session, useIPhoneMode: useIPhoneMode)
        installSessionObservers()
        NSLog("[OpenAI Audio] Session mode: %@", useIPhoneMode ? "voiceChat" : "videoChat")
    }

    /// Start capturing microphone audio.
    func startCapture() throws {
        try syncOnAudioLifecycleQueue {
            try startCaptureOnQueue()
        }
    }

    private func startCaptureOnQueue() throws {
        guard !isCapturing else { return }

        // Idempotent setup: clear any stale tap, attach the player exactly once.
        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
        if !isPlayerNodeAttached {
            audioEngine.attach(playerNode)
            isPlayerNodeAttached = true
        }

        let playerFormat = try AudioFormatFactory.pcm(
            .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: Self.channels,
            interleaved: false,
            context: "playback"
        )
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playerFormat)

        let inputNode = audioEngine.inputNode
        let inputNativeFormat = inputNode.outputFormat(forBus: 0)

        let needsResample = inputNativeFormat.sampleRate != Self.sampleRate
            || inputNativeFormat.channelCount != Self.channels

        NSLog("[OpenAI Audio] Native: %.0fHz %dch, needs resample: %@",
              inputNativeFormat.sampleRate, inputNativeFormat.channelCount,
              needsResample ? "YES" : "NO")

        // New generation: the tap below tags its buffers with it; the accumulator only accepts the
        // current generation, so buffers from a previous (torn-down) capture are dropped.
        audioGraphGeneration &+= 1
        let captureGeneration = audioGraphGeneration
        sendQueue.sync {
            accumulatedData = Data()
            accumulatorGeneration = captureGeneration
        }

        // Build the resample target format once and reuse it for every tap buffer (it's
        // constant), rather than reconstructing — and force-unwrapping — it per buffer.
        var converter: AVAudioConverter?
        var targetFormat: AVAudioFormat?
        if needsResample {
            let format = try AudioFormatFactory.pcm(
                .pcmFormatFloat32,
                sampleRate: Self.sampleRate,
                channels: Self.channels,
                interleaved: false,
                context: "capture resampling"
            )
            targetFormat = format
            converter = AVAudioConverter(from: inputNativeFormat, to: format)
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputNativeFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let pcmData: Data
            let amplitudeBuffer: AVAudioPCMBuffer

            if let converter, let targetFormat {
                guard let resampled = self.convertBuffer(buffer, using: converter, targetFormat: targetFormat) else {
                    return
                }
                pcmData = self.float32ToInt16Data(resampled)
                amplitudeBuffer = resampled
            } else {
                pcmData = self.float32ToInt16Data(buffer)
                amplitudeBuffer = buffer
            }

            // Client-side VAD: check amplitude for fast interrupt
            if self.isModelCurrentlySpeaking {
                let rms = self.calculateRMS(amplitudeBuffer)
                if rms > self.interruptAmplitudeThreshold {
                    self.consecutiveHighFrames += 1
                    if self.consecutiveHighFrames >= self.requiredHighFrames {
                        NSLog("[OpenAI Audio] Client VAD interrupt (RMS: %.4f)", rms)
                        self.consecutiveHighFrames = 0
                        self.onVoiceInterrupt?()
                    }
                } else {
                    self.consecutiveHighFrames = 0
                }
            }

            self.sendQueue.async {
                // Drop buffers from a superseded capture generation (a reset happened mid-flight).
                guard self.accumulatorGeneration == captureGeneration else { return }
                self.accumulatedData.append(pcmData)
                if self.accumulatedData.count >= self.minSendBytes {
                    let chunk = self.accumulatedData
                    self.accumulatedData = Data()
                    self.onAudioCaptured?(chunk)
                }
            }
        }
        isInputTapInstalled = true

        do {
            try audioEngine.start()
            playerNode.play()
            isCapturing = true
        } catch {
            tearDownEngineGraphOnQueue(flushPendingAudio: false)
            throw error
        }
    }

    /// Play received PCM audio (Int16 24kHz mono).
    func playAudio(data: Data) {
        guard !data.isEmpty else { return }
        audioLifecycleQueue.async { [weak self] in
            self?.playAudioOnQueue(data: data)
        }
    }

    private func playAudioOnQueue(data: Data) {
        guard isCapturing, isPlayerNodeAttached, audioEngine.isRunning, !data.isEmpty else { return }

        guard let playerFormat = try? AudioFormatFactory.pcm(
            .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: Self.channels,
            interleaved: false,
            context: "playback"
        ) else {
            NSLog("[OpenAI Audio] Invalid playback format — dropping %d bytes", data.count)
            return
        }

        let frameCount = UInt32(data.count) / (Self.bitsPerSample / 8 * Self.channels)
        guard frameCount > 0 else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        guard let floatData = buffer.floatChannelData else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<Int(frameCount) {
                floatData[0][i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        playerNode.scheduleBuffer(buffer)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    /// Stop playback but keep engine running (used on interrupt).
    func stopPlayback() {
        audioLifecycleQueue.async { [weak self] in
            self?.stopPlaybackOnQueue()
        }
    }

    private func stopPlaybackOnQueue() {
        guard isPlayerNodeAttached else { return }
        playerNode.stop()
        if isCapturing, audioEngine.isRunning {
            playerNode.play()
        }
    }

    /// Stop capture and tear down the engine graph (the engine container itself is kept).
    func stopCapture() {
        syncOnAudioLifecycleQueue {
            tearDownEngineGraphOnQueue(flushPendingAudio: true)
        }
        removeObservers()
        // Release our claim on the shared session; the coordinator deactivates it only if no newer
        // owner has acquired since (so a late stop can't stomp the next session).
        if let lease = sessionLease {
            sessionLease = nil
            AudioSessionCoordinator.shared.release(lease)
        }
    }

    // MARK: - Audio Interruption & Route Change Handling

    private func installSessionObservers() {
        removeObservers()
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { [weak self] note in
                self?.handleInterruptionNotification(note)
            }
        )
        observers.append(
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { [weak self] note in
                self?.handleRouteChangeNotification(note)
            }
        )
    }

    private func removeObservers() {
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
    }

    private func handleInterruptionNotification(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        var shouldResume = false
        if type == .ended, let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
            shouldResume = AVAudioSession.InterruptionOptions(rawValue: optsRaw).contains(.shouldResume)
        }

        audioLifecycleQueue.async { [weak self] in
            guard let self else { return }
            switch AudioInterruptionPolicy.action(for: type, shouldResume: shouldResume, isCapturing: self.isCapturing) {
            case .pause:
                // Keep `isCapturing` true through the pause so the matching `.ended` resumes.
                self.audioEngine.pause()
                NSLog("[OpenAI Audio] Interruption began — engine paused")
            case .resume:
                NSLog("[OpenAI Audio] Interruption ended — resuming")
                self.resumeAfterInterruptionOnQueue()
            case .resetGraph:
                self.attemptAudioResetOnQueue()
            case .none:
                break
            }
        }
    }

    private func handleRouteChangeNotification(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

        audioLifecycleQueue.async { [weak self] in
            guard let self else { return }
            if AudioInterruptionPolicy.action(for: reason, isCapturing: self.isCapturing) == .resetGraph {
                NSLog("[OpenAI Audio] Route changed (reason %lu) — resetting engine", raw)
                self.attemptAudioResetOnQueue()
            }
        }
    }

    private func resumeAfterInterruptionOnQueue() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
            if isCapturing, !audioEngine.isRunning {
                try audioEngine.start()
            }
            if isCapturing, isPlayerNodeAttached, !playerNode.isPlaying {
                playerNode.play()
            }
            NSLog("[OpenAI Audio] Resumed after interruption")
        } catch {
            NSLog("[OpenAI Audio] Resume failed: %@ — resetting", error.localizedDescription)
            attemptAudioResetOnQueue()
        }
    }

    /// Rebuild the session + engine on a fresh route. Runs on the lifecycle queue; the actual
    /// re-setup hops to the main actor (the normal `setupAudioSession`/`startCapture` path), which
    /// re-enters the lifecycle queue via `syncOnAudioLifecycleQueue` without deadlocking.
    private func attemptAudioResetOnQueue() {
        let wasCapturing = isCapturing
        let mode = useIPhoneMode
        tearDownEngineGraphOnQueue(flushPendingAudio: false) { [weak self] in
            guard let self, wasCapturing else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                do {
                    try self.setupAudioSession(useIPhoneMode: mode)
                    try self.startCapture()
                    NSLog("[OpenAI Audio] Audio reset successful")
                } catch {
                    NSLog("[OpenAI Audio] Audio reset failed: %@", error.localizedDescription)
                }
            }
        }
    }

    /// Tear down the engine graph: stop the engine, remove the tap, detach the player. The engine
    /// container is preserved. `completion` runs after the pending-audio flush is processed.
    private func tearDownEngineGraphOnQueue(flushPendingAudio: Bool, completion: (() -> Void)? = nil) {
        audioGraphGeneration &+= 1
        isCapturing = false

        audioEngine.stop()

        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
        if isPlayerNodeAttached {
            if playerNode.isPlaying { playerNode.stop() }
            audioEngine.disconnectNodeOutput(playerNode)
            audioEngine.detach(playerNode)
            isPlayerNodeAttached = false
        }

        sendQueue.async {
            defer { completion?() }
            let pending = self.accumulatedData
            self.accumulatedData = Data()
            self.accumulatorGeneration = 0
            if flushPendingAudio, !pending.isEmpty {
                self.onAudioCaptured?(pending)
            }
        }
    }

    /// Apply `AudioRoutePolicy`: prefer the glasses (Bluetooth/LE) input when present, otherwise
    /// fall back to the phone speaker with a logged message.
    private func applyRoutePolicy(_ session: AVAudioSession, useIPhoneMode: Bool) {
        let availableInputs = (session.availableInputs ?? []).map { $0.portType }
        let routePorts = session.currentRoute.inputs.map { $0.portType }
            + session.currentRoute.outputs.map { $0.portType }
        let decision = AudioRoutePolicy.decide(
            availableInputs: availableInputs,
            currentRoute: routePorts,
            useIPhoneMode: useIPhoneMode,
            forceSpeaker: false
        )

        if let portType = decision.preferredInputPortType,
           let input = session.availableInputs?.first(where: { $0.portType == portType }) {
            do {
                try session.setPreferredInput(input)
                NSLog("[OpenAI Audio] Preferred input: %@ (%@)", input.portName, portType.rawValue)
            } catch {
                NSLog("[OpenAI Audio] Could not set preferred input: %@", error.localizedDescription)
            }
        }
        if decision.overrideToSpeaker {
            try? session.overrideOutputAudioPort(.speaker)
        }
        if let message = decision.fallbackMessage {
            NSLog("[OpenAI Audio] %@", message)
        }
    }

    private func syncOnAudioLifecycleQueue<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: audioLifecycleQueueKey) != nil {
            return try work()
        }
        return try audioLifecycleQueue.sync(execute: work)
    }

    // MARK: - Private

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let floatData = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let sample = floatData[0][i]
            sum += sample * sample
        }
        return sqrtf(sum / Float(count))
    }

    private func float32ToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let floatData = buffer.floatChannelData else { return Data() }
        var int16Array = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, floatData[0][i]))
            int16Array[i] = Int16(sample * Float(Int16.max))
        }
        return int16Array.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }
    }

    private func convertBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCount = UInt32(Double(inputBuffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        return error == nil ? outputBuffer : nil
    }
}
