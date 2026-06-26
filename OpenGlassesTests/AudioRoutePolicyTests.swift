import AVFoundation
import XCTest
@testable import OpenGlasses

/// Tests the pure input-selection / speaker-fallback decision. On iOS 26 the glasses mic can ride
/// Bluetooth LE Audio (`.bluetoothLE`) rather than `.bluetoothHFP`; the policy must prefer either,
/// and fall back to the phone speaker with a message when neither is present.
final class AudioRoutePolicyTests: XCTestCase {

    func testGlassesModePrefersBluetoothHFPInput() {
        let decision = AudioRoutePolicy.decide(
            availableInputs: [.builtInMic, .bluetoothHFP],
            currentRoute: [.bluetoothHFP],
            useIPhoneMode: false,
            forceSpeaker: false
        )
        XCTAssertEqual(decision.preferredInputPortType, .bluetoothHFP)
        XCTAssertFalse(decision.overrideToSpeaker)
        XCTAssertNil(decision.fallbackMessage)
    }

    func testGlassesModePrefersBluetoothLEInput() {
        let decision = AudioRoutePolicy.decide(
            availableInputs: [.builtInMic, .bluetoothLE],
            currentRoute: [.bluetoothLE],
            useIPhoneMode: false,
            forceSpeaker: false
        )
        XCTAssertEqual(decision.preferredInputPortType, .bluetoothLE)
        XCTAssertFalse(decision.overrideToSpeaker)
        XCTAssertNil(decision.fallbackMessage)
    }

    func testGlassesModeWithoutHandsFreeFallsBackToSpeakerWithMessage() {
        let decision = AudioRoutePolicy.decide(
            availableInputs: [.builtInMic],
            currentRoute: [.builtInMic, .builtInSpeaker],
            useIPhoneMode: false,
            forceSpeaker: false
        )
        XCTAssertNil(decision.preferredInputPortType)
        XCTAssertTrue(decision.overrideToSpeaker)
        XCTAssertNotNil(decision.fallbackMessage)
    }

    func testGlassesModeNoHandsFreeInputButRouteHasOneSuppressesMessage() {
        // Odd case: no hands-free *input* offered, but the current route still shows a hands-free
        // port — don't nag the user with a fallback message.
        let decision = AudioRoutePolicy.decide(
            availableInputs: [.builtInMic],
            currentRoute: [.bluetoothHFP],
            useIPhoneMode: false,
            forceSpeaker: false
        )
        XCTAssertNil(decision.preferredInputPortType)
        XCTAssertTrue(decision.overrideToSpeaker)
        XCTAssertNil(decision.fallbackMessage)
    }

    func testIPhoneModeUsesSpeakerWithoutMessage() {
        let decision = AudioRoutePolicy.decide(
            availableInputs: [.builtInMic, .bluetoothHFP],
            currentRoute: [.bluetoothHFP],
            useIPhoneMode: true,
            forceSpeaker: false
        )
        XCTAssertNil(decision.preferredInputPortType)
        XCTAssertTrue(decision.overrideToSpeaker)
        XCTAssertNil(decision.fallbackMessage)
    }

    func testForceSpeakerInGlassesModeOverridesInputSelection() {
        let decision = AudioRoutePolicy.decide(
            availableInputs: [.bluetoothLE],
            currentRoute: [.bluetoothLE],
            useIPhoneMode: false,
            forceSpeaker: true
        )
        XCTAssertNil(decision.preferredInputPortType)
        XCTAssertTrue(decision.overrideToSpeaker)
        XCTAssertNil(decision.fallbackMessage)
    }
}
