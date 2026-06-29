import XCTest
@testable import OpenGlasses

final class ModelPricingOverridesTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "modelPricingOverrides")
        ModelPricing.overrides = [:]
        super.tearDown()
    }

    func testRateCodableRoundTrip() throws {
        let rate = ModelPricing.Rate(3.5, 14.25)
        let data = try JSONEncoder().encode(rate)
        XCTAssertEqual(try JSONDecoder().decode(ModelPricing.Rate.self, from: data), rate)
    }

    func testOverridesPersistAndApply() {
        Config.setModelPricingOverrides(["gpt-4o": ModelPricing.Rate(99, 88)])
        // Applied to the live table immediately…
        XCTAssertEqual(ModelPricing.rate(for: "gpt-4o"), ModelPricing.Rate(99, 88))
        // …and persisted for reload.
        XCTAssertEqual(Config.modelPricingOverrides["gpt-4o"], ModelPricing.Rate(99, 88))

        // Simulate a fresh launch: clear the in-memory table, re-apply from storage.
        ModelPricing.overrides = [:]
        Config.applyModelPricingOverrides()
        XCTAssertEqual(ModelPricing.rate(for: "gpt-4o"), ModelPricing.Rate(99, 88))
        // The override flows through to a cost estimate.
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimate(model: "gpt-4o", tokensIn: 1_000_000, tokensOut: 0)), 99, accuracy: 1e-9)
    }

    func testEmptyOverridesResetToDefaults() {
        Config.setModelPricingOverrides(["gpt-4o": ModelPricing.Rate(1, 1)])
        Config.setModelPricingOverrides([:])
        XCTAssertEqual(ModelPricing.rate(for: "gpt-4o"), ModelPricing.Rate(2.50, 10))  // bundled default
        XCTAssertTrue(Config.modelPricingOverrides.isEmpty)
    }
}
