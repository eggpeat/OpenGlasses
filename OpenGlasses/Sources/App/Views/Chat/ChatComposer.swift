import SwiftUI
import PhotosUI

/// Reusable chat composer: text input + optional photo attach (vision-gated) + send.
/// Used by the Chat tab (`ChatThreadView`) and, wrapped, by the Voice tab's inline chat input.
/// Owns its own draft/attachment state; the host decides what `onSend` does.
struct ChatComposer: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appAccent) private var accent

    var placeholder: String = "Type a message..."
    /// Focus the text field as soon as the composer appears.
    var autoFocus: Bool = false
    /// When set, a mic button is shown leading; tapping it runs this (e.g. switch back to voice).
    var voiceAction: (() -> Void)? = nil
    /// When set, a paperclip button is shown; tapping it runs this (e.g. open a file importer).
    var onAttachDocument: (() -> Void)? = nil
    /// Called with the trimmed text and optional image data when the user sends.
    var onSend: (String, Data?) -> Void

    @State private var messageText = ""
    @State private var attachedImage: UIImage?
    @State private var attachedImageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @FocusState private var isTextFieldFocused: Bool

    private var visionEnabled: Bool { Config.activeModel?.visionEnabled ?? false }
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appState.isProcessing
    }

    var body: some View {
        VStack(spacing: 8) {
            if let image = attachedImage { attachmentPreview(image) }
            inputRow
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .onAppear { if autoFocus { isTextFieldFocused = true } }
    }

    private func attachmentPreview(_ image: UIImage) -> some View {
        HStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Button {
                        attachedImage = nil
                        attachedImageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .accessibilityLabel("Remove attached photo")
                    .offset(x: 8, y: -8),
                    alignment: .topTrailing
                )
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            // Keyboard dismiss — only while editing.
            if isTextFieldFocused {
                Button {
                    isTextFieldFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: 36, height: 36)
                        .glassEffect(in: .circle)
                }
                .accessibilityLabel("Dismiss keyboard")
                .transition(.opacity)
            }

            // Optional voice button (e.g. switch back to voice input).
            if let voiceAction {
                Button {
                    voiceAction()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: 36, height: 36)
                        .glassEffect(in: .circle)
                }
                .accessibilityLabel("Switch to voice input")
            }

            // Document attach (Chat tab only).
            if let onAttachDocument {
                Button(action: onAttachDocument) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: 36, height: 36)
                        .glassEffect(in: .circle)
                }
                .accessibilityLabel("Attach document")
            }

            // Photo attach (only for vision-capable models).
            if visionEnabled {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: 36, height: 36)
                        .glassEffect(in: .circle)
                }
                .accessibilityLabel("Attach photo")
                .onChange(of: selectedPhotoItem) { _, item in
                    Task {
                        guard let item else { return }
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            attachedImageData = data
                            attachedImage = UIImage(data: data)
                        }
                        selectedPhotoItem = nil
                    }
                }
            }

            TextField(placeholder, text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(in: .rect(cornerRadius: 20))
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? accent : Color(.tertiaryLabel))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.15), value: isTextFieldFocused)
    }

    private func send() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appState.isProcessing else { return }
        let image = attachedImageData
        messageText = ""
        attachedImage = nil
        attachedImageData = nil
        onSend(text, image)
    }
}
