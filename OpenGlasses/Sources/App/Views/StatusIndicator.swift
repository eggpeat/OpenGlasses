import SwiftUI
import UIKit

/// Center status panel — card showing current state + quick action buttons.
///
/// The panel grows vertically as the user adds more quick actions.
/// Status info at top, action grid below.
struct StatusIndicator: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var session: GeminiLiveSessionManager
    @ObservedObject var openAISession: OpenAIRealtimeSessionManager

    @State private var pulseScale: CGFloat = 1.0
    @State private var executingActionId: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isGemini: Bool { appState.currentMode == .geminiLive }
    private var isOpenAI: Bool { appState.currentMode == .openaiRealtime }
    private var isRealtime: Bool { appState.currentMode.isRealtime }

    private var actions: [QuickAction] { Config.quickActions }

    private var isIdle: Bool {
        !appState.isProcessing
        && !appState.isListening
        && !appState.speechService.isSpeaking
        && !appState.cameraService.isCaptureInProgress
        && executingActionId == nil
    }

    private var showActions: Bool {
        appState.isConnected && isIdle && appState.currentMode == .direct && !actions.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status row
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(ringColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                        .scaleEffect(pulseScale)

                    Image(systemName: iconName)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(ringColor)
                        .symbolEffect(.pulse, isActive: isPulsing)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLabel)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(modeLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))

                        if isRealtime && appState.cameraService.isStreaming {
                            HStack(spacing: 3) {
                                Circle().fill(.green).frame(width: 5, height: 5)
                                Text("CAM")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.green.opacity(0.8))
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, showActions ? 10 : 14)

            // Tool call / reconnecting
            if isGemini && session.toolCallStatus.isActive {
                toolCallPill(session.toolCallStatus.displayText, color: .purple)
                    .padding(.bottom, 10)
            } else if !isRealtime && appState.llmService.toolCallStatus.isActive {
                toolCallPill(appState.llmService.toolCallStatus.displayText, color: .purple)
                    .padding(.bottom, 10)
            }

            if isGemini && session.reconnecting {
                reconnectingLabel.padding(.bottom, 10)
            }
            if isOpenAI && openAISession.reconnecting {
                reconnectingLabel.padding(.bottom, 10)
            }

            // Quick action buttons — grid that grows with user's actions
            if showActions {
                Divider()
                    .background(.white.opacity(0.08))
                    .padding(.horizontal, 16)

                quickActionGrid
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(ringColor.opacity(isPulsing ? 0.2 : 0.06), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
        .onAppear { startPulse() }
        .onChange(of: isPulsing) { _, active in
            if active { startPulse() } else { stopPulse() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(statusLabel). \(modeLabel)")
    }

    // MARK: - Quick Action Grid

    private var quickActionGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: 70, maximum: 100), spacing: 8)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(actions) { action in
                quickActionButton(action)
            }
        }
    }

    private func quickActionButton(_ action: QuickAction) -> some View {
        let isExecuting = executingActionId == action.id

        return Button {
            guard !isExecuting else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            executingActionId = action.id
            Task {
                await appState.executeQuickAction(action)
                executingActionId = nil
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.06))
                        .frame(height: 42)

                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: action.icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Text(action.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
    }

    // MARK: - Computed Properties

    private var iconName: String {
        if !appState.isConnected {
            return "eyeglasses"
        }

        if isGemini {
            switch session.connectionState {
            case .ready where session.isModelSpeaking: return "speaker.wave.3.fill"
            case .ready: return "waveform.circle.fill"
            case .connecting, .settingUp: return "antenna.radiowaves.left.and.right"
            case .error: return "exclamationmark.triangle.fill"
            case .disconnected: return "waveform.circle"
            }
        } else if isOpenAI {
            switch openAISession.connectionState {
            case .ready where openAISession.isModelSpeaking: return "speaker.wave.3.fill"
            case .ready: return "waveform.circle.fill"
            case .connecting, .settingUp: return "antenna.radiowaves.left.and.right"
            case .error: return "exclamationmark.triangle.fill"
            case .disconnected: return "waveform.circle"
            }
        } else {
            if appState.isListening { return "waveform.circle.fill" }
            if appState.speechService.isSpeaking { return "speaker.wave.3.fill" }
            return "mic.circle"
        }
    }

    private var ringColor: Color {
        if !appState.isConnected { return .gray }

        if isGemini {
            switch session.connectionState {
            case .ready where session.isModelSpeaking: return .orange
            case .ready: return .cyan
            case .connecting, .settingUp: return .orange
            case .error: return .red
            case .disconnected: return .gray
            }
        } else if isOpenAI {
            switch openAISession.connectionState {
            case .ready where openAISession.isModelSpeaking: return .orange
            case .ready: return .cyan
            case .connecting, .settingUp: return .orange
            case .error: return .red
            case .disconnected: return .gray
            }
        } else {
            if appState.isListening { return .cyan }
            if appState.speechService.isSpeaking { return .orange }
            return .gray
        }
    }

    private var isPulsing: Bool {
        if !appState.isConnected { return false }

        if isGemini {
            return session.isActive && session.connectionState == .ready
        } else if isOpenAI {
            return openAISession.isActive && openAISession.connectionState == .ready
        } else {
            return appState.isListening
        }
    }

    private var statusLabel: String {
        if !appState.isConnected {
            let status = appState.glassesService.connectionStatus
            if status == "Not connected" { return "Glasses Not Connected" }
            return status
        }

        if isGemini {
            if !session.isActive { return "Ready" }
            switch session.connectionState {
            case .ready where session.isModelSpeaking: return "Speaking..."
            case .ready: return "Listening..."
            case .connecting: return "Connecting..."
            case .settingUp: return "Setting Up..."
            case .error(let msg): return msg
            case .disconnected: return session.reconnecting ? "Reconnecting..." : "Disconnected"
            }
        } else if isOpenAI {
            if !openAISession.isActive { return "Ready" }
            switch openAISession.connectionState {
            case .ready where openAISession.isModelSpeaking: return "Speaking..."
            case .ready: return "Listening..."
            case .connecting: return "Connecting..."
            case .settingUp: return "Setting Up..."
            case .error(let msg): return msg
            case .disconnected: return openAISession.reconnecting ? "Reconnecting..." : "Disconnected"
            }
        } else {
            if appState.isListening { return "Listening..." }
            if appState.speechService.isSpeaking { return "Speaking..." }
            return "Ready"
        }
    }

    private var modeLabel: String {
        if isGemini {
            return "Gemini Live"
        } else if isOpenAI {
            return "OpenAI Realtime"
        } else {
            return "Voice \u{00B7} \(appState.llmService.activeModelName)"
        }
    }

    // MARK: - Helpers

    private var reconnectingLabel: some View {
        Text("Reconnecting...")
            .font(.system(size: 12))
            .foregroundStyle(.orange.opacity(0.8))
    }

    private func toolCallPill(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7).tint(.white)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(color.opacity(0.3), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.5))
    }

    private func startPulse() {
        guard !reduceMotion else {
            pulseScale = 1.0
            return
        }
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
    }

    private func stopPulse() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.5)) {
            pulseScale = 1.0
        }
    }
}
