import SwiftUI

/// Compact result card shown in the Siri / Shortcuts UI alongside the spoken
/// answer (the dialog stays for the eyes-free case; the snippet is additive).
struct AnswerSnippetView: View {
    let personaName: String?
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let personaName, !personaName.isEmpty {
                Label(personaName, systemImage: "person.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(answer)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
