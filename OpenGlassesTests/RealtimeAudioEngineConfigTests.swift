import XCTest
import AVFoundation
@testable import OpenGlasses

/// Plan BG P4 — the merged `RealtimeAudioEngine` is parameterised by `RealtimeAudioEngineConfig`.
/// These pin the per-provider constants so the merge can't silently drift a sample rate, chunk size,
/// or VAD setting. (The engine itself is AVFoundation-bound and exercised on-device, not here.)
final class RealtimeAudioEngineConfigTests: XCTestCase {

    func testGeminiPreset() {
        let c = RealtimeAudioEngineConfig.geminiLive
        XCTAssertEqual(c.owner, .geminiLive)
        XCTAssertEqual(c.inputSampleRate, 16000)   // capture resampled to 16 kHz
        XCTAssertEqual(c.outputSampleRate, 24000)  // playback at 24 kHz (asymmetric)
        XCTAssertEqual(c.channels, 1)
        XCTAssertEqual(c.bitsPerSample, 16)
        XCTAssertNil(c.vad, "Gemini relies on server VAD, not client-side")
    }

    func testOpenAIPreset() {
        let c = RealtimeAudioEngineConfig.openAIRealtime
        XCTAssertEqual(c.owner, .openAIRealtime)
        XCTAssertEqual(c.inputSampleRate, 24000)   // symmetric 24 kHz both directions
        XCTAssertEqual(c.outputSampleRate, 24000)
        XCTAssertEqual(c.channels, 1)
        XCTAssertEqual(c.bitsPerSample, 16)
        XCTAssertEqual(c.vad?.amplitudeThreshold, 0.05)
        XCTAssertEqual(c.vad?.requiredHighFrames, 3)
    }

    /// ~100 ms of input PCM — the pre-merge managers hard-coded 3200 (Gemini) and 4800 (OpenAI).
    func testMinSendBytesMatchesLegacyConstants() {
        XCTAssertEqual(RealtimeAudioEngineConfig.geminiLive.minSendBytes, 3200)
        XCTAssertEqual(RealtimeAudioEngineConfig.openAIRealtime.minSendBytes, 4800)
    }

    func testPreferredSampleRateTracksInput() {
        XCTAssertEqual(RealtimeAudioEngineConfig.geminiLive.preferredSampleRate, 16000)
        XCTAssertEqual(RealtimeAudioEngineConfig.openAIRealtime.preferredSampleRate, 24000)
    }
}
