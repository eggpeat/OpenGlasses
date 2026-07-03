import XCTest
@testable import OpenGlasses

/// Plan BG P5 — pins the key, default, and round-trip for each `Config` toggle migrated to
/// `@UserDefaultsBacked`. A wrong key or default in the wrapper is a *silent* behaviour change,
/// so these guard the migration: each assertion ties the property to its exact UserDefaults key.
final class ConfigDefaultsTests: XCTestCase {

    private let keys = [
        "silentMode", "glassesOnlyAudio", "audioOnlyMode", "memoryNudgesEnabled",
        "showAllQuickActions", "siriAskOpensApp", "mcpServerEnabled", "accessibilityModeEnabled",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    /// Absent key → `false`, matching the legacy `UserDefaults.bool(forKey:)` getter.
    func testDefaultsAreFalse() {
        XCTAssertFalse(Config.silentMode)
        XCTAssertFalse(Config.glassesOnlyAudio)
        XCTAssertFalse(Config.audioOnlyMode)
        XCTAssertFalse(Config.memoryNudgesEnabled)
        XCTAssertFalse(Config.showAllQuickActions)
        XCTAssertFalse(Config.siriAskOpensApp)
        XCTAssertFalse(Config.mcpServerEnabled)
        XCTAssertFalse(Config.accessibilityModeEnabled)
    }

    /// Each `setX` façade writes the property, and it round-trips through the exact legacy key.
    func testSettersRoundTripThroughTheCorrectKey() {
        assertRoundTrip("silentMode", set: Config.setSilentMode, get: { Config.silentMode })
        assertRoundTrip("glassesOnlyAudio", set: Config.setGlassesOnlyAudio, get: { Config.glassesOnlyAudio })
        assertRoundTrip("audioOnlyMode", set: Config.setAudioOnlyMode, get: { Config.audioOnlyMode })
        assertRoundTrip("memoryNudgesEnabled", set: Config.setMemoryNudgesEnabled, get: { Config.memoryNudgesEnabled })
        assertRoundTrip("showAllQuickActions", set: Config.setShowAllQuickActions, get: { Config.showAllQuickActions })
        assertRoundTrip("siriAskOpensApp", set: Config.setSiriAskOpensApp, get: { Config.siriAskOpensApp })
        assertRoundTrip("mcpServerEnabled", set: Config.setMCPServerEnabled, get: { Config.mcpServerEnabled })
        assertRoundTrip("accessibilityModeEnabled", set: Config.setAccessibilityModeEnabled, get: { Config.accessibilityModeEnabled })
    }

    /// A raw value written under the legacy key (as the old setter did) is read by the new property —
    /// proves the wrapper's key is unchanged, so previously-persisted user settings survive.
    func testLegacyPersistedValuesStillRead() {
        UserDefaults.standard.set(true, forKey: "silentMode")
        XCTAssertTrue(Config.silentMode)
        UserDefaults.standard.set(true, forKey: "accessibilityModeEnabled")
        XCTAssertTrue(Config.accessibilityModeEnabled)
    }

    private func assertRoundTrip(_ key: String, set: (Bool) -> Void, get: () -> Bool,
                                 file: StaticString = #file, line: UInt = #line) {
        set(true)
        XCTAssertTrue(get(), "\(key) should read true after set(true)", file: file, line: line)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key), "\(key) must persist under its exact key", file: file, line: line)
        set(false)
        XCTAssertFalse(get(), "\(key) should read false after set(false)", file: file, line: line)
    }
}
