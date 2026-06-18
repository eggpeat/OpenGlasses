import Foundation

/// Describes the downloadable on-device ASR model — SenseVoice on sherpa-onnx (Additional Capabilities
/// #8). Unlike the Kokoro TTS bundle, SenseVoice is just two flat files (`model.int8.onnx` + `tokens.txt`,
/// hosted unpacked on HuggingFace), so the downloader fetches them directly — no repo-tree enumeration,
/// no extraction.
///
/// (A follow-up can unify this with the Kokoro `…ModelBundle/Store/Downloader` into one shared sherpa-onnx
/// model layer; kept parallel here so the on-device ASR tier ships without touching the shipped Kokoro
/// code.)
struct ASRModelBundle: Equatable {

    /// Stable identifier (also the upstream repo's model name).
    let id: String
    /// User-facing name for the Settings status row.
    let displayName: String
    /// Sub-directory under Application Support that holds the model files.
    let directoryName: String
    /// HuggingFace repo hosting the (unpacked) files.
    let huggingFaceRepo: String
    /// Rough total download size, for the Settings status row.
    let approxDownloadBytes: Int64
    /// Files that must each be present and non-empty for the model to count as installed.
    let requiredFiles: [String]

    /// The download URL for a file within the repo.
    func huggingFaceResolveURL(for path: String) -> URL {
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        // swiftlint:disable:next force_unwrapping — repo id + percent-escaped filename.
        return URL(string: "https://huggingface.co/\(huggingFaceRepo)/resolve/main/\(escaped)")!
    }

    /// The shipped bundle: SenseVoice int8, multilingual (zh/en/ja/ko/yue), ~240 MB.
    static let senseVoiceMultiLang = ASRModelBundle(
        id: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17",
        displayName: "SenseVoice (multilingual)",
        directoryName: "SenseVoiceASR",
        huggingFaceRepo: "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17",
        approxDownloadBytes: 240_000_000,
        requiredFiles: ["model.int8.onnx", "tokens.txt"]
    )

    /// The bundle the app ships with.
    static let active = senseVoiceMultiLang
}
