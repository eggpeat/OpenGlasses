import XCTest
@testable import OpenGlasses

/// Tests for the pure ASR engine-selection policy (Additional Capabilities #8): given availability
/// (Apple Speech authorized, SenseVoice model present, online), the user's preference, it produces the
/// `On-Device ↔ Apple Speech` fallback chain.
final class ASREngineSelectorTests: XCTestCase {

    private typealias Availability = ASREngineSelector.Availability

    private func chain(_ p: ASREnginePreference, _ a: Availability) -> [ASREngine] {
        ASREngineSelector.chain(preference: p, availability: a)
    }

    func testAutoPrefersAppleSpeechWhenOnline() {
        let result = chain(.auto, Availability(appleSpeechReady: true, onDeviceReady: true, online: true))
        XCTAssertEqual(result, [.appleSpeech, .onDevice])
    }

    func testAutoPromotesOnDeviceWhenOffline() {
        // Apple Speech may need the network; offline, the fully-local recognizer leads.
        let result = chain(.auto, Availability(appleSpeechReady: true, onDeviceReady: true, online: false))
        XCTAssertEqual(result, [.onDevice, .appleSpeech])
    }

    func testAutoOfflineWithoutModelStaysOnAppleSpeech() {
        let result = chain(.auto, Availability(appleSpeechReady: true, onDeviceReady: false, online: false))
        XCTAssertEqual(result, [.appleSpeech])
    }

    func testAutoWithoutModelIsAppleSpeechOnly() {
        let result = chain(.auto, Availability(appleSpeechReady: true, onDeviceReady: false, online: true))
        XCTAssertEqual(result, [.appleSpeech])
    }

    func testOnDevicePreferenceLeadsWithOnDevice() {
        let result = chain(.onDevice, Availability(appleSpeechReady: true, onDeviceReady: true, online: true))
        XCTAssertEqual(result, [.onDevice, .appleSpeech])
    }

    func testOnDevicePreferenceFallsBackWhenModelAbsent() {
        let result = chain(.onDevice, Availability(appleSpeechReady: true, onDeviceReady: false, online: true))
        XCTAssertEqual(result, [.appleSpeech])
    }

    func testAppleSpeechPreferenceForcesAppleFirst() {
        let result = chain(.appleSpeech, Availability(appleSpeechReady: true, onDeviceReady: true, online: false))
        XCTAssertEqual(result.first, .appleSpeech)   // even offline, the user forced Apple
    }

    func testNothingAvailableYieldsEmptyChainAndNilSelection() {
        // Apple Speech unauthorized and no on-device model → no recognizer at all.
        let availability = Availability(appleSpeechReady: false, onDeviceReady: false, online: true)
        XCTAssertTrue(chain(.auto, availability).isEmpty)
        XCTAssertNil(ASREngineSelector.select(preference: .auto, availability: availability))
    }

    func testOnDeviceOnlyWhenAppleUnauthorized() {
        let result = chain(.auto, Availability(appleSpeechReady: false, onDeviceReady: true, online: true))
        XCTAssertEqual(result, [.onDevice])
    }

    func testSelectMatchesChainHead() {
        let combos: [(ASREnginePreference, Availability)] = [
            (.auto, Availability(appleSpeechReady: true, onDeviceReady: true, online: true)),
            (.onDevice, Availability(appleSpeechReady: true, onDeviceReady: true, online: false)),
            (.auto, Availability(appleSpeechReady: true, onDeviceReady: false, online: true)),
        ]
        for (p, a) in combos {
            XCTAssertEqual(ASREngineSelector.select(preference: p, availability: a),
                           ASREngineSelector.chain(preference: p, availability: a).first)
        }
    }
}
