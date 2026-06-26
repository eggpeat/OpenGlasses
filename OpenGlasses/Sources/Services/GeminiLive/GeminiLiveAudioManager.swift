import AVFoundation
import Foundation

/// Dedicated audio engine for Gemini Live mode.
/// Captures microphone input as 16kHz Int16 PCM and plays back 24kHz Int16 PCM from Gemini.
/// Separate from WakeWordService's audio engine — the two cannot coexist.
///
/// Self-healing across OS audio interruptions (phone calls, Siri) and Bluetooth/LE-Audio route
/// changes: the `AVAudioEngine` is kept permanent for the manager's lifetime (teardown only stops
/// and detaches child nodes), all graph mutations run on a single serial lifecycle queue, and a
/// generation counter discards stale tap buffers so audio from a torn-down session can't bleed into
/// the next one. The interruption/route → action decisions live in pure, tested policies
/// (`AudioInterruptionPolicy`, `AudioRoutePolicy`); this class only executes them.
final class GeminiLiveAudioManager {
    var onAudioCaptured: ((Data) -> Void)?

    // Keep the engine container permanent for the manager's lifetime. Teardown only stops and
    // detaches child nodes; it never nils or replaces this engine.
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    // All engine-graph mutations run here so observer-driven recovery can't race start/stop.
    private let audioLifecycleQueue = DispatchQueue(label: "gemini.audio.lifecycle", qos: .userInitiated)
    private let audioLifecycleQueueKey = DispatchSpecificKey<Void>()

    private var isCapturing = false
    private var isInputTapInstalled = false
    private var isPlayerNodeAttached = false
    private var useIPhoneMode = false
    /// Bumped on every (re)start and teardown; tags tap buffers so stale ones are dropped.
    private var audioGraphGeneration: UInt64 = 0

    // Accumulate resampled PCM into ~100ms chunks before sending
    private let sendQueue = DispatchQueue(label: "audio.accumulator")
    private var accumulatedData = Data()
    private var accumulatorGeneration: UInt64 = 0
    private let minSendBytes = 3200  // 100ms at 16kHz mono Int16 = 1600 frames × 2 bytes

    private var observers: [NSObjectProtocol] = []

    init() {
        audioLifecycleQueue.setSpecific(key: audioLifecycleQueueKey, value: ())
    }

    deinit {
        removeObservers()
    }

    /// Configure the audio session for Gemini Live.
    /// - Parameter useIPhoneMode: `true` for `.voiceChat` (iPhone mic), `false` for `.videoChat` (glasses mic).
    func setupAudioSession(useIPhoneMode: Bool = false) throws {
        self.useIPhoneMode = useIPhoneMode
        let session = AVAudioSession.sharedInstance()
        guard AVAudioApplication.shared.recordPermission != .denied else {
            throw AudioSessionError.microphonePermissionDenied
        }
        let mode: AVAudioSession.Mode = useIPhoneMode ? .voiceChat : .videoChat
        try AudioSessionActivator.activate(
            session,
            category: .playAndRecord,
            mode: mode,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        ) { session in
            // Preferred rate/buffer are hints — a rejected hint must not abort activation.
            try? session.setPreferredSampleRate(Config.geminiLiveInputSampleRate)
            try? session.setPreferredIOBufferDuration(0.064)
        }
        applyRoutePolicy(session, useIPhoneMode: useIPhoneMode)
        installSessionObservers()
        NSLog("[Audio] Session mode: %@", useIPhoneMode ? "voiceChat (iPhone)" : "videoChat (glasses)")
    }

    /// Start capturing microphone audio and sending chunks via `onAudioCaptured`.
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
            sampleRate: Config.geminiLiveOutputSampleRate,
            channels: Config.geminiLiveAudioChannels,
            interleaved: false,
            context: "playback"
        )
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playerFormat)

        let inputNode = audioEngine.inputNode
        let inputNativeFormat = inputNode.outputFormat(forBus: 0)

        NSLog("[Audio] Native input format: %@ sampleRate=%.0f channels=%d",
              inputNativeFormat.commonFormat == .pcmFormatFloat32 ? "Float32" :
              inputNativeFormat.commonFormat == .pcmFormatInt16 ? "Int16" : "Other",
              inputNativeFormat.sampleRate, inputNativeFormat.channelCount)

        let needsResample = inputNativeFormat.sampleRate != Config.geminiLiveInputSampleRate
            || inputNativeFormat.channelCount != Config.geminiLiveAudioChannels

        NSLog("[Audio] Needs resample: %@", needsResample ? "YES" : "NO")

        // New generation: the tap below tags its buffers with it; the accumulator only accepts the
        // current generation, so buffers from a previous (torn-down) capture are dropped.
        audioGraphGeneration &+= 1
        let captureGeneration = audioGraphGeneration
        sendQueue.sync {
            accumulatedData = Data()
            accumulatorGeneration = captureGeneration
        }

        // Build the resample target format once and reuse it for every tap buffer
        // (it's constant), rather than reconstructing — and force-unwrapping — it per buffer.
        var converter: AVAudioConverter?
        var resampleFormat: AVAudioFormat?
        if needsResample {
            let format = try AudioFormatFactory.pcm(
                .pcmFormatFloat32,
                sampleRate: Config.geminiLiveInputSampleRate,
                channels: Config.geminiLiveAudioChannels,
                interleaved: false,
                context: "capture resampling"
            )
            resampleFormat = format
            converter = AVAudioConverter(from: inputNativeFormat, to: format)
        }

        var tapCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputNativeFormat) { [weak self] buffer, _ in
            guard let self else { return }

            tapCount += 1
            let currentTapCount = tapCount
            let pcmData: Data

            if let converter, let resampleFormat {
                guard let resampled = self.convertBuffer(buffer, using: converter, targetFormat: resampleFormat) else {
                    if currentTapCount <= 3 { NSLog("[Audio] Resample failed for tap #%d", currentTapCount) }
                    return
                }
                pcmData = self.float32BufferToInt16Data(resampled)
            } else {
                pcmData = self.float32BufferToInt16Data(buffer)
            }

            self.sendQueue.async {
                // Drop buffers from a superseded capture generation (a reset happened mid-flight).
                guard self.accumulatorGeneration == captureGeneration else { return }
                self.accumulatedData.append(pcmData)
                if self.accumulatedData.count >= self.minSendBytes {
                    let chunk = self.accumulatedData
                    self.accumulatedData = Data()
                    if currentTapCount <= 3 {
                        NSLog("[Audio] Sending chunk: %d bytes (~%dms)",
                              chunk.count, chunk.count / 32)
                    }
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

    /// Play received PCM audio data (Int16 at 24kHz) through the speaker.
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
            sampleRate: Config.geminiLiveOutputSampleRate,
            channels: Config.geminiLiveAudioChannels,
            interleaved: false,
            context: "playback"
        ) else {
            NSLog("[Audio] Invalid playback format — dropping %d bytes", data.count)
            return
        }

        let frameCount = UInt32(data.count) / (Config.geminiLiveAudioBitsPerSample / 8 * Config.geminiLiveAudioChannels)
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

    /// Stop playback but keep the engine running (used when interrupted by Gemini barge-in).
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
                NSLog("[Audio] Interruption began — engine paused")
            case .resume:
                NSLog("[Audio] Interruption ended — resuming")
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
                NSLog("[Audio] Route changed (reason %lu) — resetting engine", raw)
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
            NSLog("[Audio] Resumed after interruption")
        } catch {
            NSLog("[Audio] Resume failed: %@ — resetting", error.localizedDescription)
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
                    NSLog("[Audio] Audio reset successful")
                } catch {
                    NSLog("[Audio] Audio reset failed: %@", error.localizedDescription)
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
                NSLog("[Audio] Preferred input: %@ (%@)", input.portName, portType.rawValue)
            } catch {
                NSLog("[Audio] Could not set preferred input: %@", error.localizedDescription)
            }
        }
        if decision.overrideToSpeaker {
            try? session.overrideOutputAudioPort(.speaker)
        }
        if let message = decision.fallbackMessage {
            NSLog("[Audio] %@", message)
        }
    }

    private func syncOnAudioLifecycleQueue<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: audioLifecycleQueueKey) != nil {
            return try work()
        }
        return try audioLifecycleQueue.sync(execute: work)
    }

    // MARK: - Private Helpers

    private func float32BufferToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data {
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

        if error != nil {
            return nil
        }

        return outputBuffer
    }
}
