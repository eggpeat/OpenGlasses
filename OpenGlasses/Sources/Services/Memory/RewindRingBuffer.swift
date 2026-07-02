import Foundation
import os.lock

/// Fixed-capacity byte ring buffer for Memory Rewind's rolling audio window.
///
/// The old `MemoryRewindService` accumulated PCM into one growing `Data` and, once full, called
/// `removeFirst(excess)` on every audio callback — an O(n) memmove of the whole (up to ~58 MB)
/// buffer ~10–15×/sec. This ring overwrites the oldest bytes in place, so an append is O(bytes
/// appended) regardless of window size. Lock-guarded so the audio-render thread can write while the
/// main actor reads a snapshot for transcription.
final class RewindRingBuffer: @unchecked Sendable {

    private let lock = OSAllocatedUnfairLock()
    private var storage: [UInt8]
    /// Index where the next byte will be written.
    private var writeIndex = 0
    /// Number of valid bytes currently held (≤ capacity).
    private var filled = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(0, capacity)
        storage = [UInt8](repeating: 0, count: self.capacity)
    }

    /// Bytes currently buffered.
    var count: Int { lock.withLock { filled } }

    /// Append bytes, overwriting the oldest once full. Safe to call from the audio thread.
    func append(_ data: Data) {
        guard capacity > 0, !data.isEmpty else { return }
        lock.withLock {
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let src = raw.bindMemory(to: UInt8.self)
                // If the incoming chunk is larger than the whole ring, keep only its tail.
                let start = src.count > capacity ? src.count - capacity : 0
                storage.withUnsafeMutableBufferPointer { dst in
                    var i = start
                    while i < src.count {
                        let chunk = min(src.count - i, capacity - writeIndex)
                        dst.baseAddress!.advanced(by: writeIndex)
                            .update(from: src.baseAddress!.advanced(by: i), count: chunk)
                        writeIndex = (writeIndex + chunk) % capacity
                        i += chunk
                    }
                }
                filled = min(filled + (src.count - start), capacity)
            }
        }
    }

    /// Return the most recent `maxBytes` bytes in chronological order (oldest → newest). Passing a
    /// value ≥ `count` returns the whole buffer. Safe to call from the main actor.
    func snapshotSuffix(_ maxBytes: Int) -> Data {
        lock.withLock {
            let n = min(max(0, maxBytes), filled)
            guard n > 0 else { return Data() }
            var out = [UInt8](repeating: 0, count: n)
            // The newest byte is at (writeIndex - 1); the oldest of our n bytes is n back from there.
            let startLogical = filled - n                 // 0 = oldest valid byte
            let oldestPhysical = (writeIndex - filled + capacity * 2) % capacity
            let readStart = (oldestPhysical + startLogical) % capacity
            out.withUnsafeMutableBufferPointer { dst in
                storage.withUnsafeBufferPointer { src in
                    var i = 0
                    var pos = readStart
                    while i < n {
                        let chunk = min(n - i, capacity - pos)
                        dst.baseAddress!.advanced(by: i)
                            .update(from: src.baseAddress!.advanced(by: pos), count: chunk)
                        pos = (pos + chunk) % capacity
                        i += chunk
                    }
                }
            }
            return Data(out)
        }
    }

    func reset() {
        lock.withLock {
            writeIndex = 0
            filled = 0
        }
    }
}
