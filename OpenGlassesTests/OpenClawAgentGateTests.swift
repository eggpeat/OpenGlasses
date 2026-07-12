import XCTest
@testable import OpenGlasses

/// Plan BK P0 — the OpenClaw gateway (`execute` / `openclaw_skills`) and remote-agent dispatch are
/// autonomous capabilities and must sit behind `agentModeEnabled`, not merely `isOpenClawConfigured`.
/// With Agent Mode OFF: the gateway is neither advertised to the model nor invocable (fail-closed);
/// with it ON: behaviour is unchanged.
@MainActor
final class OpenClawAgentGateTests: XCTestCase {

    private var savedAgent = false
    private var savedEnabled = false
    private var savedToken = ""

    override func setUp() {
        super.setUp()
        savedAgent = Config.agentModeEnabled
        savedEnabled = Config.openClawEnabled
        savedToken = Config.openClawGatewayToken
    }
    override func tearDown() {
        Config.setAgentModeEnabled(savedAgent)
        Config.setOpenClawEnabled(savedEnabled)
        Config.setOpenClawGatewayToken(savedToken)
        super.tearDown()
    }

    /// Put a gateway on file (so `isOpenClawConfigured` is true) with Agent Mode either way.
    private func configureGateway(agentMode: Bool) {
        Config.setOpenClawEnabled(true)
        Config.setOpenClawGatewayToken("test-token")
        Config.setAgentModeEnabled(agentMode)
    }

    // MARK: - The combined gate

    func testIsOpenClawAgentActiveRequiresBothConfiguredAndAgentMode() {
        configureGateway(agentMode: false)
        XCTAssertTrue(Config.isOpenClawConfigured)
        XCTAssertFalse(Config.isOpenClawAgentActive, "configured but Agent Mode off ⇒ not active")

        Config.setAgentModeEnabled(true)
        XCTAssertTrue(Config.isOpenClawAgentActive)

        // Agent Mode on but no gateway configured ⇒ still not active.
        Config.setOpenClawEnabled(false)
        Config.setOpenClawGatewayToken("")
        XCTAssertFalse(Config.isOpenClawAgentActive)
    }

    // MARK: - delegateTask fails closed (the flagship hole)

    func testDelegateTaskFailsClosedWithAgentModeOff() async {
        configureGateway(agentMode: false)
        let bridge = OpenClawBridge()
        let statusBefore = bridge.lastToolCallStatus

        let result = await bridge.delegateTask(task: "read my files")
        guard case .failure(let message) = result else { return XCTFail("expected failure") }
        XCTAssertTrue(message.contains("Agent mode"), "got: \(message)")
        // It returns before touching the socket or the status — nothing was attempted.
        XCTAssertEqual(bridge.lastToolCallStatus, statusBefore, "no socket work; status untouched")
    }

    func testAgentRequestThrowsWithAgentModeOff() async {
        configureGateway(agentMode: false)
        let bridge = OpenClawBridge()
        do {
            _ = try await bridge.agentRequest(method: "agent.run", params: [:])
            XCTFail("agentRequest must throw with Agent Mode off")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Agent mode"), "got: \(error)")
        }
    }

    // MARK: - Dispatch service-layer gate

    func testDispatchReturnsAgentModeOffWithAgentModeOff() async {
        Config.setAgentModeEnabled(false)
        let service = AgentSessionService()
        service.configure(registry: AgentHarnessRegistry([GateStubHarness()]), speak: { _ in })
        let result = await service.dispatch(prompt: "do x", project: nil)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .agentModeOff)
    }

    // MARK: - Tool schema: `execute` gated by includeOpenClaw

    func testExecuteSchemaOmittedWhenIncludeOpenClawFalse() {
        let off = ToolDeclarations.allDeclarations(registry: nil, includeOpenClaw: false)
        XCTAssertFalse(off.contains { $0["name"] as? String == "execute" })
        let on = ToolDeclarations.allDeclarations(registry: nil, includeOpenClaw: true)
        XCTAssertTrue(on.contains { $0["name"] as? String == "execute" })
    }

    // MARK: - openclaw_skills registration + execution gate

    func testSkillsToolNotRegisteredWithAgentModeOff() {
        configureGateway(agentMode: false)
        let registry = NativeToolRegistry(locationService: LocationService(), openClawBridge: OpenClawBridge())
        XCTAssertFalse(registry.toolNames.contains("openclaw_skills"),
                       "the gateway-skills tool must not appear in the prompt/schema with Agent Mode off")
    }

    func testSkillsToolRegisteredWithAgentModeOn() {
        configureGateway(agentMode: true)
        let registry = NativeToolRegistry(locationService: LocationService(), openClawBridge: OpenClawBridge())
        XCTAssertTrue(registry.toolNames.contains("openclaw_skills"))
    }

    func testSkillsToolExecuteRefusesWithAgentModeOff() async throws {
        configureGateway(agentMode: false)
        let bridge = OpenClawBridge()
        var tool = OpenClawSkillsTool()
        tool.openClawBridge = bridge
        let reply = try await tool.execute(args: ["action": "list_skills"])
        XCTAssertTrue(reply.contains("Agent Mode is off"), "got: \(reply)")
    }
}

/// Minimal configured harness for the dispatch-gate test (the gate returns before it's consulted).
private struct GateStubHarness: AgentHarness {
    let kind: AgentHarnessKind = .custom
    var displayName: String { "Gate stub" }
    var isConfigured: Bool { true }
    func start(prompt: String, project: String?) async throws -> AgentRun {
        AgentRun(id: "r", harness: kind, prompt: prompt, project: project, status: .running, startedAt: Date())
    }
    func events(for run: AgentRun) -> AsyncStream<AgentEvent> { AsyncStream { $0.finish() } }
    func status(_ run: AgentRun) async throws -> AgentRunStatus { run.status }
    func cancel(_ run: AgentRun) async throws {}
    func respondToInput(_ run: AgentRun, approved: Bool) async throws {}
}
