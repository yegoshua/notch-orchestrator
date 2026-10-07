import AppKit

/// The sound of a turn that finished well. Quiet on purpose, and made here rather than taken from
/// the system's alert sounds, which are meant to be noticed: a fraction of a second that can be
/// missed, or a short call on a wind instrument of the orchestra.
@MainActor
enum FinishSound {
    /// What it sounds like. The first ones are over almost before they are heard; the
    /// instruments play a call of two notes rising a fifth.
    enum Voice: String, CaseIterable {
        /// A drop of water: one note that slides up as it dies away.
        case drop = "Drop"
        /// A muted knock, low and dull.
        case tap = "Tap"
        /// The click of two small things touching.
        case tick = "Tick"
        /// A puff of air and no note at all.
        case breath = "Breath"
        /// One soft note, as struck on wood.
        case pluck = "Pluck"
        /// One high note, very faint.
        case glint = "Glint"
        /// Two tiny notes, the second higher.
        case pips = "Pips"
        case flute = "Flute"
        case clarinet = "Clarinet"
        case horn = "Horn"

        /// The two notes, in hertz: each instrument in the register it sounds soft in.
        fileprivate var notes: (Double, Double) {
            switch self {
            case .flute: (587.33, 880.00)
            case .clarinet: (440.00, 659.26)
            case .horn: (349.23, 523.25)
            default: (0, 0)
            }
        }

        /// How strong each harmonic is, the fundamental first. A flute is nearly pure, a
        /// clarinet lacks the even ones, a horn has them all.
        fileprivate var harmonics: [Double] {
            switch self {
            case .flute: [1, 0.32, 0.10, 0.04]
            case .clarinet: [1, 0.03, 0.46, 0.02, 0.20, 0.02, 0.09]
            case .horn: [1, 0.62, 0.40, 0.24, 0.13, 0.07]
            default: []
            }
        }

        /// How long a note takes to speak, in seconds.
        fileprivate var attack: Double {
            switch self {
            case .flute: 0.055
            case .clarinet: 0.04
            default: 0.07
            }
        }

        /// How much air is heard beside the tone.
        fileprivate var breath: Double {
            switch self {
            case .flute: 0.05
            case .clarinet: 0.015
            default: 0.01
            }
        }

        /// How loud it is at its loudest, of what the format holds.
        fileprivate var level: Double {
            switch self {
            case .flute, .clarinet, .horn: 0.32
            case .glint, .tick: 0.16
            case .pips: 0.12
            case .drop, .tap, .breath, .pluck: 0.24
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
            guard let stored = UserDefaults.standard.string(forKey: key) else { return .pips }
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

    static func samples(_ voice: Voice) -> [Int16] {
        var noise = Noise()
        let tau = 2 * Double.pi
        /// A note that speaks within `attack` seconds and dies away at the pace of `decay`.
        func struck(_ age: Double, attack: Double, decay: Double) -> Double {
            age < 0 ? 0 : min(1, age / attack) * exp(-age / decay)
        }
        /// The phase of a note that slides from one pitch to another at the pace of `pace`.
        func slide(_ age: Double, from: Double, to: Double, pace: Double) -> Double {
            tau * (to * age - (to - from) * pace * (1 - exp(-age / pace)))
        }
        var values: [Double]
        switch voice {
        case .flute, .clarinet, .horn:
            values = call(voice)
        case .drop:
            values = render(0.18) { time in
                sin(slide(time, from: 520, to: 980, pace: 0.025)) * struck(time, attack: 0.004, decay: 0.045)
            }
        case .tap:
            values = render(0.14) { time in
                sin(slide(time, from: 230, to: 140, pace: 0.03)) * struck(time, attack: 0.002, decay: 0.035)
                    + 0.12 * noise.next() * exp(-time / 0.004)
            }
        case .tick:
            values = render(0.05) { time in
                sin(tau * 2100 * time) * struck(time, attack: 0.001, decay: 0.008)
                    + 0.4 * sin(tau * 3300 * time) * struck(time, attack: 0.001, decay: 0.005)
            }
        case .breath:
            values = render(0.16) { time in noise.next() * pow(sin(.pi * time / 0.16), 2) }
        case .pluck:
            values = render(0.26) { time in
                (sin(tau * 784 * time) + 0.25 * sin(tau * 3136 * time) * exp(-time / 0.02))
                    * struck(time, attack: 0.003, decay: 0.06)
            }
        case .glint:
            values = render(0.3) { time in
                (sin(tau * 1318.5 * time) + 0.1 * sin(tau * 2637 * time)) * struck(time, attack: 0.005, decay: 0.07)
            }
        case .pips:
            values = render(0.2) { time in
                sin(tau * 659.26 * time) * struck(time, attack: 0.004, decay: 0.03)
                    + sin(tau * 987.77 * (time - 0.075)) * struck(time - 0.075, attack: 0.004, decay: 0.03)
            }
        }
        let peak = values.map(abs).max() ?? 1
        return values.enumerated().map { index, value in
            // Out to nothing by the end, so that the cut is not heard.
            let tail = min(1, Double(values.count - index) / (0.01 * sampleRate))
            return Int16(value / max(peak, 0.001) * voice.level * tail * Double(Int16.max))
        }
    }

    private static func render(_ duration: Double, _ value: (Double) -> Double) -> [Double] {
        (0..<Int(duration * sampleRate)).map { value(Double($0) / sampleRate) }
    }

    /// A short first note, then the fifth above it, held and let go. The second speaks before
    /// the first has gone, as when both are played in one breath.
    private static func call(_ voice: Voice) -> [Double] {
        let notes = [
            (frequency: voice.notes.0, start: 0.0, length: 0.20, level: 0.8),
            (frequency: voice.notes.1, start: 0.17, length: 0.52, level: 1.0),
        ]
        let release = 0.22
        let duration = 0.17 + 0.52 + release + 0.02
        var noise = Noise()
        return render(duration) { time in
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
