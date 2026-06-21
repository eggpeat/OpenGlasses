import XCTest
@testable import OpenGlasses

/// Covers the pure config surface behind the Siri "Ask a Question" intent.
/// (The intent's `perform()` itself drives `AppState`/Wearables, which a unit
/// test must not touch — see the shared-services/Wearables testing note — so we
/// pin the persisted flag it reads instead.)
final class SiriIntentSupportTests: XCTestCase {

    private let key = "siriAskOpensApp"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    // MARK: - siriAskOpensApp

    func testSiriAskOpensAppDefaultsToFalse() {
        // Default false = hands-free background; Siri speaks the answer without
        // forcing the app to the foreground.
        XCTAssertFalse(Config.siriAskOpensApp)
    }

    func testSiriAskOpensAppSetAndGet() {
        Config.setSiriAskOpensApp(true)
        XCTAssertTrue(Config.siriAskOpensApp)

        Config.setSiriAskOpensApp(false)
        XCTAssertFalse(Config.siriAskOpensApp)
    }
}
