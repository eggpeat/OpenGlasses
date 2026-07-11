import Foundation

/// What a caption row's speaker chip shows (BM P7). Pure value produced by `SpeakerChipModel` so
/// chip presence / label / colour are unit-testable; the SwiftUI capsule in
/// `AmbientCaptionOverlay` is the thin edge.
struct SpeakerChip: Equatable {
    let speakerId: Int
    let label: String
    let colorIndex: Int
}

/// PURE chip decision for a caption entry: no speaker id (the single-speaker /
/// diarization-off path never sets one) ⇒ no chip; otherwise the registry resolves the display
/// name (or "Speaker N") and the stable palette slot, including merge-on-same-name
/// canonicalisation.
enum SpeakerChipModel {
    static func chip(speaker: Int?, registry: SpeakerRegistry) -> SpeakerChip? {
        guard let speaker else { return nil }
        return SpeakerChip(
            speakerId: speaker,
            label: registry.displayLabel(for: speaker),
            colorIndex: registry.colorIndex(for: speaker))
    }
}
