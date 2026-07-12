import XCTest
@testable import OpenGlasses

/// Plan BN P1 — the shared remote-action consent surface: the self-approval hole is closed (a
/// `code_agent confirm` tool call can raise the user-distinct prompt but never answer it), the
/// coordinator carries a source line, and the voice yes/no path resolves only unambiguous answers.
@MainActor
final class RemoteActionConsentTests: XCTestCase {

    // MARK: - Prompt composition (source attribution)

    func testConsentPromptCarriesTheSource() {
        XCTAssertEqual(
            RemoteActionConsentRequest(source: .codingAgent, summary: "push to main").attributedSummary,
            "The coding agent wants: push to main")
        XCTAssertEqual(
            RemoteActionConsentRequest(source: .gateway, summary: "take a photo").spokenPrompt,
            "The gateway wants: take a photo. Approve?")
        XCTAssertEqual(
            RemoteActionConsentRequest(source: .opsPeer(label: "Ops platform"), summary: "take a photo").attributedSummary,
            "Ops platform wants: take a photo")
        XCTAssertEqual(
            RemoteActionConsentRequest(source: .opsPeer(label: ""), summary: "x").attributedSummary,
            "An ops platform wants: x")
        XCTAssertEqual(
            RemoteActionConsentRequest(source: .assistant, summary: "send a message").attributedSummary,
            "The assistant wants: send a message")
    }

    // MARK: - Voice yes/no interpretation

    func testVoiceConsentInterpretation() {
        // Approvals.
        for phrase in ["yes", "Yes.", "yep", "approve", "go ahead", "do it", "okay", "yes please"] {
            XCTAssertEqual(RemoteActionVoiceConsent.interpret(phrase), true, "\(phrase) should approve")
        }
        // Denials.
        for phrase in ["no", "No!", "nope", "cancel", "deny", "stop", "cancel it", "abort"] {
            XCTAssertEqual(RemoteActionVoiceConsent.interpret(phrase), false, "\(phrase) should deny")
        }
        // Ambiguous / unrelated → nil (flows to the normal turn pipeline; never guess).
        for phrase in ["what's the weather", "yes and also send it to everyone I know",
                       "don't do it unless it's safe", "", "maybe", "okay cancel"] {
            XCTAssertNil(RemoteActionVoiceConsent.interpret(phrase), "\(phrase) must not resolve a prompt")
        }
    }

    // MARK: - Coordinator: source + voice resolution

    func testCoordinatorPendingCarriesSourceAndSpeaksAttributedPrompt() async {
        let coordinator = ToolConfirmationCoordinator()
        var spoken: [String] = []
        coordinator.onSpeakPrompt = { spoken.append($0) }

        let task = Task {
            await coordinator.requestConfirmation(toolName: "code_agent", summary: "push to main", source: .codingAgent)
        }
        // Let the request suspend and publish.
        while coordinator.pending == nil { await Task.yield() }

        XCTAssertEqual(coordinator.pending?.source, .codingAgent)
        XCTAssertEqual(spoken, ["The coding agent wants: push to main. Approve?"])

        coordinator.resolve(true)
        let approved = await task.value
        XCTAssertTrue(approved)
        XCTAssertNil(coordinator.pending)
    }

    func testCoordinatorVoiceResolution() async {
        let coordinator = ToolConfirmationCoordinator()
        let task = Task {
            await coordinator.requestConfirmation(toolName: "t", summary: "s", source: .gateway)
        }
        while coordinator.pending == nil { await Task.yield() }

        // An ambiguous phrase is NOT consumed and leaves the prompt pending.
        XCTAssertFalse(coordinator.resolveByVoice("what's the time"))
        XCTAssertNotNil(coordinator.pending)

        // A clear "no" is consumed and denies.
        XCTAssertTrue(coordinator.resolveByVoice("no"))
        let approved = await task.value
        XCTAssertFalse(approved)

        // Nothing pending → voice is never consumed.
        XCTAssertFalse(coordinator.resolveByVoice("yes"))
    }

    // MARK: - The self-approval hole (Plan N confirm)

    private func awaitingService(_ mock: ConsentStubHarness) async -> AgentSessionService {
        let service = AgentSessionService()
        service.setHarness(mock)
        _ = await service.dispatch(prompt: "p", project: nil)
        service.handle(.awaitingInput(prompt: "Push to main?"))
        return service
    }

    func testConfirmToolCallFailsClosedWithoutConsentSurface() async {
        // No consent seam wired (the injected-turn scenario in a headless context): the tool
        // call must NOT approve anything.
        let mock = ConsentStubHarness()
        let service = await awaitingService(mock)

        let reply = await service.confirmPendingActionViaUserPrompt()
        XCTAssertTrue(reply.contains("nothing was approved"), "got: \(reply)")
        XCTAssertEqual(service.activeRun?.status, .awaitingInput, "the run must stay waiting")
        XCTAssertNil(mock.respondedApproved, "the harness must never hear an approval")
    }

    func testConfirmToolCallRoutesThroughUserPromptAndGrantApproves() async {
        let mock = ConsentStubHarness()
        let service = await awaitingService(mock)

        var requests: [RemoteActionConsentRequest] = []
        service.requestUserConsent = { request in
            requests.append(request)
            return true   // the wearer approves at the real prompt
        }

        let reply = await service.confirmPendingActionViaUserPrompt()
        XCTAssertEqual(reply, "Confirmed — the agent will proceed.")
        XCTAssertEqual(service.activeRun?.status, .running)
        XCTAssertEqual(mock.respondedApproved, true)
        // The prompt is source-attributed with the run's own awaiting prompt.
        XCTAssertEqual(requests, [RemoteActionConsentRequest(source: .codingAgent, summary: "Push to main?")])
    }

    func testConfirmToolCallDeniedAtPromptCancelsRun() async {
        let mock = ConsentStubHarness()
        let service = await awaitingService(mock)
        service.requestUserConsent = { _ in false }   // the wearer denies

        let reply = await service.confirmPendingActionViaUserPrompt()
        XCTAssertEqual(reply, "Okay, I won't proceed.")
        XCTAssertEqual(service.activeRun?.status, .cancelled, "decline still cancels (safety default)")
        XCTAssertEqual(mock.respondedApproved, false)
    }

    func testConfirmToolCallWithNothingPendingIsRefused() async {
        let service = AgentSessionService()
        service.requestUserConsent = { _ in
            XCTFail("no prompt should be shown when nothing is awaiting input")
            return true
        }
        let reply = await service.confirmPendingActionViaUserPrompt()
        XCTAssertEqual(reply, "There's nothing waiting for confirmation.")
    }
}

/// Minimal scripted harness recording what the session tells it.
private final class ConsentStubHarness: AgentHarness {
    let kind: AgentHarnessKind = .custom
    var displayName: String { "Stub" }
    var isConfigured: Bool { true }
    private(set) var respondedApproved: Bool?

    func start(prompt: String, project: String?) async throws -> AgentRun {
        AgentRun(id: "run1", harness: kind, prompt: prompt, project: project, status: .running, startedAt: Date())
    }
    func events(for run: AgentRun) -> AsyncStream<AgentEvent> { AsyncStream { $0.finish() } }
    func status(_ run: AgentRun) async throws -> AgentRunStatus { run.status }
    func cancel(_ run: AgentRun) async throws {}
    func respondToInput(_ run: AgentRun, approved: Bool) async throws { respondedApproved = approved }
}
