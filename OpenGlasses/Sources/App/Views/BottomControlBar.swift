import SwiftUI

/// Bottom control bar — ergonomic layout for thumb and index finger use.
///
/// Layout: Two rows.
///   Row 1 (primary):  Wide mic/action capsule — the main touch target.
///   Row 2 (secondary): [Settings] [Camera] [Preview] [Model] [Persona]
///
/// The mic capsule is large enough to hit easily with a thumb from either hand.
/// Secondary buttons are spaced for index finger taps.
struct BottomControlBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var session: GeminiLiveSessionManager
    @ObservedObject var openAISession: OpenAIRealtimeSessionManager

    @Binding var showSettings: Bool
    @Binding var showModelPicker: Bool
    @Binding var showPreview: Bool
    @Binding var showPersonaPicker: Bool

    private var isRealtime: Bool { appState.currentMode.isRealtime }
    private var isGemini: Bool { appState.currentMode == .geminiLive }
    private var isOpenAI: Bool { appState.currentMode == .openaiRealtime }

    private var realtimeSessionActive: Bool {
        isGemini ? session.isActive : (isOpenAI ? openAISession.isActive : false)
    }

    private var previewVisible: Bool { appState.isConnected }

    private var photoDisabledForLocalModel: Bool {
        guard let model = Config.activeModel, model.llmProvider == .local else { return false }
        return !model.visionEnabled
    }

    var body: some View {
        VStack(spacing: 10) {
            // Primary: wide mic capsule
            heroCapsule
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            appState.micMuted.toggle()
                        }
                )

            // Secondary: utility row
            HStack(spacing: 0) {
                BarButton(icon: "gearshape", label: "Settings") {
                    showSettings = true
                }
                .frame(maxWidth: .infinity)

                cameraButton
                    .frame(maxWidth: .infinity)

                if previewVisible {
                    BarButton(
                        icon: "eye",
                        label: "Preview",
                        isActive: appState.videoRecorder.isRecording
                    ) {
                        showPreview = true
                    }
                    .frame(maxWidth: .infinity)
                }

                BarButton(
                    icon: "brain",
                    label: appState.llmService.activeModelName,
                    truncateLabel: true
                ) {
                    showModelPicker = true
                }
                .frame(maxWidth: .infinity)

                personaButton
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.5), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
        )
    }

    // MARK: - Hero Capsule

    @ViewBuilder
    private var heroCapsule: some View {
        if isGemini {
            ActionCapsule(
                icon: session.isActive ? "stop.fill" : "play.fill",
                label: session.isActive ? "Stop Session" : "Start Gemini Live",
                isActive: session.isActive,
                color: session.isActive ? .red : .cyan
            ) {
                Task {
                    if session.isActive { session.stopSession() }
                    else { await session.startSession() }
                }
            }
        } else if isOpenAI {
            ActionCapsule(
                icon: openAISession.isActive ? "stop.fill" : "play.fill",
                label: openAISession.isActive ? "Stop Session" : "Start OpenAI Realtime",
                isActive: openAISession.isActive,
                color: openAISession.isActive ? .red : .cyan
            ) {
                Task {
                    if openAISession.isActive { openAISession.stopSession() }
                    else { await openAISession.startSession() }
                }
            }
        } else if appState.isProcessing || appState.speechService.isSpeaking {
            ActionCapsule(
                icon: "stop.fill",
                label: appState.speechService.isSpeaking ? "Tap to stop" : "Cancel",
                isActive: true,
                color: .orange
            ) {
                appState.cancelCurrentResponse()
            }
        } else {
            ActionCapsule(
                icon: appState.isListening ? "mic.fill" : "mic",
                label: appState.isListening ? "Listening..." : "Tap to talk",
                isActive: appState.isListening,
                color: appState.isListening ? .cyan : .white,
                showMuteBadge: appState.micMuted
            ) {
                Task {
                    if appState.isListening {
                        await appState.returnToWakeWord()
                    } else {
                        appState.wakeWordService.stopListening()
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        await appState.handleWakeWordDetected()
                    }
                }
            }
        }
    }

    // MARK: - Secondary Buttons

    @ViewBuilder
    private var cameraButton: some View {
        if !appState.isConnected {
            BarButton(icon: "eyeglasses", label: "Connect") {
                Task { await appState.glassesService.connect() }
            }
        } else if isRealtime {
            BarButton(
                icon: "video.fill",
                label: appState.cameraService.isStreaming ? "Streaming" : "Camera",
                isActive: appState.cameraService.isStreaming,
                isDisabled: !realtimeSessionActive
            ) {
                if realtimeSessionActive && !appState.cameraService.isStreaming {
                    Task {
                        do { try await appState.cameraService.startStreaming() }
                        catch { appState.errorMessage = "Camera: \(error.localizedDescription)" }
                    }
                }
            }
        } else {
            BarButton(
                icon: "camera.fill",
                label: "Photo",
                isActive: appState.cameraService.isCaptureInProgress,
                isDisabled: appState.cameraService.isCaptureInProgress || photoDisabledForLocalModel
            ) {
                if !photoDisabledForLocalModel {
                    Task { await appState.captureAndAnalyzePhoto() }
                }
            }
        }
    }

    @ViewBuilder
    private var personaButton: some View {
        let activePersona = appState.activePersona
        let personaCount = Config.enabledPersonas.count
        BarButton(
            icon: activePersona?.icon ?? "person.2",
            label: activePersona?.name ?? "Modes",
            badge: personaCount > 1 ? "\(personaCount)" : nil
        ) {
            showPersonaPicker = true
        }
    }
}

// MARK: - Action Capsule (primary touch target)

/// Wide capsule button — the main interaction element.
/// Sized for easy thumb hits from either hand edge.
private struct ActionCapsule: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    var color: Color = .white
    var showMuteBadge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)

                    if showMuteBadge {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(3)
                            .background(.black.opacity(0.7), in: Circle())
                            .offset(x: 12, y: -8)
                    }
                }

                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(isActive ? color.opacity(0.15) : Color.clear)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isActive ? color.opacity(0.4) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Bar Button (secondary actions)

/// Compact button for the secondary utility row.
private struct BarButton: View {
    let icon: String
    var label: String = ""
    var isActive: Bool = false
    var isDisabled: Bool = false
    var badge: String? = nil
    var truncateLabel: Bool = false
    var action: () -> Void = {}

    private var foreground: Color {
        if isDisabled { return .white.opacity(0.25) }
        if isActive { return .white }
        return .white.opacity(0.7)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(foreground)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 10, y: -8)
                    }
                }
                .frame(width: 32, height: 28)

                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(foreground.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(truncateLabel ? .middle : .tail)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(label.isEmpty ? icon : label)
    }
}
