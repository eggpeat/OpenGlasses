import XCTest
@testable import OpenGlasses

/// Simple Mode is pure Settings-surface gating for handing the device to a non-technical user.
final class SimpleModeTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "simpleModeEnabled")
        super.tearDown()
    }

    func testDefaultsOff() {
        UserDefaults.standard.removeObject(forKey: "simpleModeEnabled")
        XCTAssertFalse(Config.simpleModeEnabled, "the owner sees the full app out of the box")
    }

    func testTogglePersists() {
        Config.simpleModeEnabled = true
        XCTAssertTrue(Config.simpleModeEnabled)
        Config.simpleModeEnabled = false
        XCTAssertFalse(Config.simpleModeEnabled)
    }
}
