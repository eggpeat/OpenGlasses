import XCTest
import CoreLocation
@testable import OpenGlasses

/// Plan BK P1 — geofencing must actually fire. Before this, `GeofenceTool` built its own
/// `CLLocationManager` and never set a delegate, so `handleRegionEvent` (the only path to the TTS
/// alert) was dead code, and `createGeofence` promised an alert it could never deliver. Driven
/// through an injected `RegionMonitoring` fake: region events reach the alert, and `createGeofence`
/// returns an honest can't-arm message when authorization/capability won't allow it.
@MainActor
final class GeofenceToolTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "geofence_reminders")
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "geofence_reminders")
        super.tearDown()
    }

    /// Fully controllable region monitor — no CLLocationManager, no permission prompt.
    @MainActor
    final class FakeRegionMonitor: RegionMonitoring {
        var regionAuthorizationStatus: CLAuthorizationStatus = .authorizedAlways
        var monitoredRegionCount = 0
        var available = true
        private(set) var started: [CLCircularRegion] = []
        private(set) var stopped: [CLCircularRegion] = []
        var alwaysRequested = 0
        var onRegionEvent: ((CLRegion, Bool) -> Void)?
        var onBecameAuthorizedAlways: (() -> Void)?

        func regionMonitoringAvailable() -> Bool { available }
        func requestAlwaysAuthorization() { alwaysRequested += 1 }
        func startMonitoringRegion(_ region: CLCircularRegion) { started.append(region); monitoredRegionCount = started.count }
        func stopMonitoringRegion(_ region: CLCircularRegion) { stopped.append(region) }
        func fire(_ region: CLRegion, didEnter: Bool) { onRegionEvent?(region, didEnter) }
    }

    private func tool(_ monitor: FakeRegionMonitor) -> GeofenceTool {
        GeofenceTool(locationService: LocationService(), regionMonitor: monitor)
    }

    private func createArgs(name: String = "office", trigger: String = "enter") -> [String: Any] {
        ["action": "create", "name": name, "latitude": 37.0, "longitude": -122.0, "trigger": trigger]
    }

    // MARK: - Armability (pure)

    func testArmabilityMatrix() {
        XCTAssertEqual(GeofenceTool.armability(status: .authorizedAlways, monitoringAvailable: true, monitoredCount: 0), .ok)
        XCTAssertEqual(GeofenceTool.armability(status: .authorizedAlways, monitoringAvailable: true, monitoredCount: 20), .atCapacity)
        XCTAssertEqual(GeofenceTool.armability(status: .notDetermined, monitoringAvailable: true, monitoredCount: 0), .needsPermission)
        XCTAssertEqual(GeofenceTool.armability(status: .authorizedWhenInUse, monitoringAvailable: true, monitoredCount: 0), .denied)
        XCTAssertEqual(GeofenceTool.armability(status: .denied, monitoringAvailable: true, monitoredCount: 0), .denied)
        XCTAssertEqual(GeofenceTool.armability(status: .restricted, monitoringAvailable: true, monitoredCount: 0), .denied)
        XCTAssertEqual(GeofenceTool.armability(status: .authorizedAlways, monitoringAvailable: false, monitoredCount: 0), .unavailable)
    }

    // MARK: - createGeofence honest messaging (no false promises)

    func testCreateArmsAndMonitorsWithAlways() async throws {
        let m = FakeRegionMonitor()
        let reply = try await tool(m).execute(args: createArgs())
        XCTAssertTrue(reply.contains("I'll alert you"), reply)
        XCTAssertEqual(m.started.count, 1, "the region must actually be monitored")
    }

    func testCreateWithWhenInUseReturnsCantArm() async throws {
        let m = FakeRegionMonitor(); m.regionAuthorizationStatus = .authorizedWhenInUse
        let reply = try await tool(m).execute(args: createArgs())
        XCTAssertTrue(reply.contains("Always"), reply)
        XCTAssertTrue(m.started.isEmpty, "must not claim monitoring without Always")
    }

    func testCreateWithDeniedReturnsCantArm() async throws {
        let m = FakeRegionMonitor(); m.regionAuthorizationStatus = .denied
        let reply = try await tool(m).execute(args: createArgs())
        XCTAssertTrue(reply.contains("isn't granted"), reply)
        XCTAssertTrue(m.started.isEmpty)
    }

    func testCreateWithMonitoringUnavailableReturnsCantArm() async throws {
        let m = FakeRegionMonitor(); m.available = false
        let reply = try await tool(m).execute(args: createArgs())
        XCTAssertTrue(reply.contains("can't monitor"), reply)
        XCTAssertTrue(m.started.isEmpty)
    }

    func testCreateNotDeterminedRequestsAlways() async throws {
        let m = FakeRegionMonitor(); m.regionAuthorizationStatus = .notDetermined
        let reply = try await tool(m).execute(args: createArgs())
        XCTAssertEqual(m.alwaysRequested, 1, "must request Always permission")
        XCTAssertTrue(reply.contains("asked for it"), reply)
        XCTAssertTrue(m.started.isEmpty, "not armed until Always is granted")
    }

    func testTwentyFirstRegionReturnsCantArm() async throws {
        let m = FakeRegionMonitor(); m.monitoredRegionCount = 20   // OS cap already reached
        let reply = try await tool(m).execute(args: createArgs())
        XCTAssertTrue(reply.contains("maximum of 20"), reply)
        XCTAssertTrue(m.started.isEmpty)
    }

    // MARK: - Region events reach the alert (the whole point)

    func testEnteringRegionFiresTheAlert() async throws {
        let m = FakeRegionMonitor()
        let t = tool(m)
        var alerts: [String] = []
        t.onAlert = { msg, _ in alerts.append(msg) }
        t.activate()   // wires the region-event forwarder
        _ = try await t.execute(args: createArgs(name: "office"))

        let region = try XCTUnwrap(m.started.last, "created geofence should be monitored")
        m.fire(region, didEnter: true)
        XCTAssertEqual(alerts.count, 1, "entering the region must fire the alert")
        XCTAssertTrue(alerts[0].contains("office"), alerts.first ?? "")
    }

    func testExitEventUsesLeftWording() async throws {
        let m = FakeRegionMonitor()
        let t = tool(m)
        var alerts: [String] = []
        t.onAlert = { msg, _ in alerts.append(msg) }
        t.activate()
        _ = try await t.execute(args: createArgs(name: "home", trigger: "exit"))

        let region = try XCTUnwrap(m.started.last)
        m.fire(region, didEnter: false)
        XCTAssertTrue(alerts.first?.contains("left") == true, alerts.first ?? "")
    }

    func testUnknownRegionEventDoesNotFire() async throws {
        let m = FakeRegionMonitor()
        let t = tool(m)
        var fired = false
        t.onAlert = { _, _ in fired = true }
        t.activate()
        // A region we never created (no matching reminder) is ignored.
        m.fire(CLCircularRegion(center: .init(latitude: 0, longitude: 0), radius: 50, identifier: "ghost"), didEnter: true)
        XCTAssertFalse(fired)
    }

    func testGrantingAlwaysArmsDeferredGeofences() async throws {
        // Created while permission is pending → saved but not armed. Granting Always arms it.
        let m = FakeRegionMonitor(); m.regionAuthorizationStatus = .notDetermined
        let t = tool(m)
        t.activate()   // wires onBecameAuthorizedAlways; restore is a no-op while notDetermined
        _ = try await t.execute(args: createArgs(name: "gym"))
        XCTAssertTrue(m.started.isEmpty)

        m.regionAuthorizationStatus = .authorizedAlways
        m.onBecameAuthorizedAlways?()   // the delegate flip
        XCTAssertEqual(m.started.count, 1, "the deferred geofence arms once Always is granted")
    }
}
