import XCTest
import AVFoundation
@testable import OpenGlasses

/// Plan BM P0 — cloud diarization must stop egressing audio the moment HIPAA flips on, not just
/// at session start. Fresh service instances with an injected `isConfigured` seam (never the
/// Keychain-backed `Config.isDiarizationConfigured`, which can't be driven headless).
@MainActor
final class HIPAADiarizationGuardTests: XCTestCase {

    private func makeBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        return buffer
    }

    // MARK: - Start-time gate

    func testStartRefusesWhenNotConfigured() {
        let svc = DeepgramSTTService()
        svc.isConfigured = { false }   // e.g. HIPAA mode on
        svc.start()
        XCTAssertEqual(svc.state, .error("Diarization not available"))
    }

    func testStartArmsWhenConfigured() {
        let svc = DeepgramSTTService()
        svc.isConfigured = { true }
        svc.start()
        XCTAssertEqual(svc.state, .connecting)
    }

    // MARK: - Runtime invariant: a mid-session HIPAA flip stops audio

    func testSendAudioTearsDownWhenConfigRevokedMidSession() {
        let svc = DeepgramSTTService()
        var configured = true
        svc.isConfigured = { configured }
        svc.start()
        XCTAssertEqual(svc.state, .connecting)

        // HIPAA flips on while the stream is live — the next captured buffer must close it.
        configured = false
        svc.sendAudio(makeBuffer())
        XCTAssertEqual(svc.state, .idle, "revoking config mid-session tears the socket down")
    }

    func testSendAudioIsInertWhenNeverArmed() {
        let svc = DeepgramSTTService()
        svc.isConfigured = { false }
        svc.sendAudio(makeBuffer())   // no start(); must not crash or leave a dangling state
        XCTAssertEqual(svc.state, .idle)
    }

    // MARK: - Toggle plumbing

    func testSetModeWritesFlagAndFiresCallback() {
        let svc = HIPAAComplianceService()
        let original = Config.hipaaMode
        defer { Config.hipaaMode = original }

        var fired = 0
        svc.onModeChanged = { fired += 1 }

        svc.setMode(true)
        XCTAssertTrue(Config.hipaaMode)
        XCTAssertEqual(fired, 1)

        svc.setMode(false)
        XCTAssertFalse(Config.hipaaMode)
        XCTAssertEqual(fired, 2)
    }

    func testReconfigureForModeChangeIsNoOpWhenInactive() {
        let captions = AmbientCaptionService()
        captions.reconfigureForModeChange()   // nothing running — must stay inactive
        XCTAssertFalse(captions.isActive)
    }
}
