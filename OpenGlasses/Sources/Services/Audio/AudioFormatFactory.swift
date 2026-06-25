import AVFoundation

/// Constructs `AVAudioFormat` values without force-unwrapping.
///
/// `AVAudioFormat`'s initializer is failable: it returns `nil` for parameter combinations the
/// OS can't represent. In practice this bites on unexpected native input formats from some
/// Bluetooth / iOS LE-Audio mic routes — exactly the routes these glasses use — where a
/// force-unwrap (`AVAudioFormat(...)!`) becomes a hard crash mid-call. This helper turns that
/// failure into a typed `AudioSessionError.invalidFormat(context:)` the caller can handle.
enum AudioFormatFactory {
    /// A PCM `AVAudioFormat`, or throw `AudioSessionError.invalidFormat(context:)`.
    ///
    /// - Parameter context: names the role (e.g. "playback", "capture resampling") for the
    ///   thrown error and any logging — purely diagnostic.
    static func pcm(
        _ commonFormat: AVAudioCommonFormat,
        sampleRate: Double,
        channels: AVAudioChannelCount,
        interleaved: Bool,
        context: String
    ) throws -> AVAudioFormat {
        // Guard the obviously-degenerate inputs up front: AVAudioFormat asserts (rather than
        // returning nil) on a zero channel count, so we must not reach its initializer with one.
        guard sampleRate > 0, channels > 0,
              let format = AVAudioFormat(
                commonFormat: commonFormat,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: interleaved
              )
        else {
            throw AudioSessionError.invalidFormat(context: context)
        }
        return format
    }
}
