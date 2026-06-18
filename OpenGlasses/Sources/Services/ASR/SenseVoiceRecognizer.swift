#if SHERPA_ONNX_ENABLED
import Foundation
import SherpaOnnxWrapper

/// Wraps a sherpa-onnx `OfflineRecognizer` configured for the SenseVoice model and transcribes a PCM
/// buffer. Created lazily and reused (loading the ~240 MB model is expensive). All C calls run on a
/// private serial queue, so it's safe to call from any thread. Compiled only when `SHERPA_ONNX_ENABLED`
/// links the vendored sherpa-onnx binary.
final class SenseVoiceRecognizer: @unchecked Sendable {

    private let modelDirectory: URL
    private let queue = DispatchQueue(label: "com.openglasses.asr.sensevoice")
    private var recognizer: OpaquePointer?   // const SherpaOnnxOfflineRecognizer *

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    deinit {
        if let recognizer { SherpaOnnxDestroyOfflineRecognizer(recognizer) }
    }

    /// Transcribe mono float samples to text. Blocking — call off the main thread.
    func transcribe(samples: [Float], sampleRate: Double) throws -> String {
        try queue.sync {
            let engine = try recognizerHandle()
            guard let stream = SherpaOnnxCreateOfflineStream(engine) else {
                throw ASRError.recognitionFailed
            }
            defer { SherpaOnnxDestroyOfflineStream(stream) }

            let pcm = Self.resampleTo16k(samples: samples, sampleRate: sampleRate)
            pcm.withUnsafeBufferPointer { buffer in
                SherpaOnnxAcceptWaveformOffline(stream, 16000, buffer.baseAddress, Int32(buffer.count))
            }
            SherpaOnnxDecodeOfflineStream(engine, stream)

            guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
                throw ASRError.recognitionFailed
            }
            defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
            let text = result.pointee.text.map { String(cString: $0) } ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Build (once) and return the OfflineRecognizer, configured for the SenseVoice model.
    private func recognizerHandle() throws -> OpaquePointer {
        if let recognizer { return recognizer }

        func path(_ name: String) -> String { modelDirectory.appendingPathComponent(name).path }

        let handle: OpaquePointer? = path("model.int8.onnx").withCString { model in
            path("tokens.txt").withCString { tokens in
                "cpu".withCString { provider in
                    "".withCString { language in
                        "greedy_search".withCString { decoding in
                            var config = SherpaOnnxOfflineRecognizerConfig()
                            config.feat_config.sample_rate = 16000
                            config.feat_config.feature_dim = 80
                            config.model_config.tokens = tokens
                            config.model_config.num_threads = 2
                            config.model_config.provider = provider
                            config.model_config.debug = 0
                            config.model_config.sense_voice.model = model
                            config.model_config.sense_voice.language = language   // "" → auto-detect
                            config.model_config.sense_voice.use_itn = 1
                            config.decoding_method = decoding
                            return SherpaOnnxCreateOfflineRecognizer(&config)
                        }
                    }
                }
            }
        }

        guard let handle else { throw ASRError.modelLoadFailed }
        recognizer = handle
        return handle
    }

    /// SenseVoice expects 16 kHz mono. Linear-resample when the capture rate differs (typically
    /// 44.1/48 kHz). Good enough for ASR features; the model is robust to minor resampling artefacts.
    private static func resampleTo16k(samples: [Float], sampleRate: Double) -> [Float] {
        guard sampleRate > 0, abs(sampleRate - 16000) >= 1, samples.count > 1 else { return samples }
        let ratio = 16000.0 / sampleRate
        let outCount = max(Int(Double(samples.count) * ratio), 1)
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let src = Double(i) / ratio
            let i0 = min(Int(src), samples.count - 1)
            let i1 = min(i0 + 1, samples.count - 1)
            let frac = Float(src - Double(i0))
            out[i] = samples[i0] * (1 - frac) + samples[i1] * frac
        }
        return out
    }
}
#endif
