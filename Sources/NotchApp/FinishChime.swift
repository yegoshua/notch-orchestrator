import AppKit

/// The sound of a turn that finished well: two soft bell notes, the second a fourth above the
/// first. Quiet on purpose, and made here rather than taken from the system's alert sounds, which
/// are meant to be noticed. It follows the Sound setting: with sounds off it is silent too.
@MainActor
enum FinishChime {
    private static let sampleRate = 44_100.0
    private static let volume: Float = 0.45
    /// When to sound after the line was asked for: as its mark is drawn, not before it is there.
    private static let delay: TimeInterval = 0.25

    private static let sound: NSSound? = {
        let sound = NSSound(data: wave(of: samples()))
        sound?.volume = volume
        return sound
    }()

    static func play() {
        guard InterruptionSound.current != nil, let sound else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            sound.stop()
            sound.play()
        }
    }

    /// G5, then C6 a moment later; each rings out by itself.
    private static func samples() -> [Int16] {
        let notes: [(frequency: Double, start: Double, level: Double)] = [(783.99, 0, 0.8), (1046.50, 0.11, 1)]
        let duration = 1.0
        return (0..<Int(duration * sampleRate)).map { index in
            let time = Double(index) / sampleRate
            var value = 0.0
            for note in notes where time >= note.start {
                let age = time - note.start
                // A short rise keeps the start from clicking; the fall is what makes it a bell.
                let envelope = min(1, age / 0.008) * exp(-age / 0.2)
                let phase = 2 * Double.pi * note.frequency * age
                value += note.level * envelope * (sin(phase) + 0.18 * sin(2 * phase) + 0.05 * sin(3 * phase))
            }
            // Out to nothing by the end, so that the cut is not heard.
            let tail = min(1, (duration - time) / 0.05)
            return Int16(max(-1, min(1, 0.3 * value * tail)) * Double(Int16.max))
        }
    }

    /// The samples as a mono 16-bit WAV file.
    private static func wave(of samples: [Int16]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let size = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + size)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(size)
        samples.forEach(append)
        return data
    }
}
