import AppKit

/// The sound of a turn that finished well: a short call on a wind instrument of the orchestra,
/// two notes rising a fifth. Quiet on purpose, and made here rather than taken from the system's
/// alert sounds, which are meant to be noticed.
@MainActor
enum FinishSound {
    /// The instrument that plays the call.
    enum Voice: String, CaseIterable {
        case flute = "Flute"
        case clarinet = "Clarinet"
        case horn = "Horn"

        /// The two notes, in hertz: each instrument in the register it sounds soft in.
        fileprivate var notes: (Double, Double) {
            switch self {
            case .flute: (587.33, 880.00)
            case .clarinet: (440.00, 659.26)
            case .horn: (349.23, 523.25)
            }
        }

        /// How strong each harmonic is, the fundamental first. A flute is nearly pure, a
        /// clarinet lacks the even ones, a horn has them all.
        fileprivate var harmonics: [Double] {
            switch self {
            case .flute: [1, 0.32, 0.10, 0.04]
            case .clarinet: [1, 0.03, 0.46, 0.02, 0.20, 0.02, 0.09]
            case .horn: [1, 0.62, 0.40, 0.24, 0.13, 0.07]
            }
        }

        /// How long a note takes to speak, in seconds.
        fileprivate var attack: Double {
            switch self {
            case .flute: 0.055
            case .clarinet: 0.04
            case .horn: 0.07
            }
        }

        /// How much air is heard beside the tone.
        fileprivate var breath: Double {
            switch self {
            case .flute: 0.05
            case .clarinet: 0.015
            case .horn: 0.01
            }
        }
    }

    private static let key = "finishSound"
    private static let sampleRate = 44_100.0
    private static let volume: Float = 0.45
    /// When to sound after the line was asked for: as its mark is drawn, not before it is there.
    private static let delay: TimeInterval = 0.25
    private static var sounds: [Voice: NSSound] = [:]

    /// Nil when a finished turn makes no sound.
    static var current: Voice? {
        get {
            guard let stored = UserDefaults.standard.string(forKey: key) else { return .flute }
            return Voice(rawValue: stored)
        }
        set { UserDefaults.standard.set(newValue?.rawValue ?? "", forKey: key) }
    }

    static func play(after delay: TimeInterval? = nil) {
        guard let voice = current else { return }
        let sound = sounds[voice] ?? NSSound(data: wave(of: samples(voice)))
        sound?.volume = volume
        sounds[voice] = sound
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay ?? Self.delay)) {
            sound?.stop()
            sound?.play()
        }
    }

    /// A short first note, then the fifth above it, held and let go. The second speaks before
    /// the first has gone, as when both are played in one breath.
    static func samples(_ voice: Voice) -> [Int16] {
        let notes = [
            (frequency: voice.notes.0, start: 0.0, length: 0.20, level: 0.8),
            (frequency: voice.notes.1, start: 0.17, length: 0.52, level: 1.0),
        ]
        let release = 0.22
        let duration = 0.17 + 0.52 + release + 0.02
        var noise = Noise()
        var values = (0..<Int(duration * sampleRate)).map { index -> Double in
            let time = Double(index) / sampleRate
            let air = noise.next()
            var value = 0.0
            for note in notes where time >= note.start && time < note.start + note.length + release {
                let age = time - note.start
                // Speaks and stops without an edge, and sinks a little while it is held.
                let rise = age < voice.attack ? 0.5 - 0.5 * cos(.pi * age / voice.attack) : 1
                let fall = age > note.length ? 0.5 + 0.5 * cos(.pi * (age - note.length) / release) : 1
                let envelope = rise * fall * (1 - 0.25 * min(1, age / note.length))
                // The player's vibrato comes in once the note stands.
                let vibrato = 0.004 * min(1, max(0, age - 0.12) / 0.2) * sin(2 * Double.pi * 5.2 * age)
                let phase = 2 * Double.pi * note.frequency * age + note.frequency / 5.2 * vibrato
                var tone = 0.0
                for (index, strength) in voice.harmonics.enumerated() {
                    tone += strength * sin(Double(index + 1) * phase)
                }
                // Most of the air is heard as the note speaks.
                let puff = voice.breath * (1 + 3 * exp(-age / 0.04))
                value += note.level * envelope * (tone + puff * air)
            }
            return value
        }
        let peak = values.map(abs).max() ?? 1
        values = values.map { $0 / max(peak, 0.001) * 0.32 }
        return values.map { Int16($0 * Double(Int16.max)) }
    }

    /// Air: noise with its hiss taken off. The same every time, so the sound is too.
    private struct Noise {
        private var state: UInt64 = 0x2545F4914F6CDD1D
        private var smoothed = 0.0

        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let white = Double(state >> 33) / Double(1 << 30) - 1
            smoothed += 0.25 * (white - smoothed)
            return smoothed
        }
    }

    /// The samples as a mono 16-bit WAV file.
    static func wave(of samples: [Int16]) -> Data {
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
