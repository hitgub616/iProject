import AVFoundation

/// A soft, low "tup" — a muted wood/marimba-like cue for each Cover Flow step.
/// Sine-based with a smooth raised-cosine attack (no hard transient) and a
/// gentle pitch glide. A small pool of voices lets rapid steps overlap and
/// ring out naturally instead of being cut off (which would click).
final class TickPlayer {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var voices: [AVAudioPlayerNode] = []
    private var buffer: AVAudioPCMBuffer?
    private var started = false
    private var next = 0

    var enabled: Bool = true

    init() {
        buffer = makeTick()
        for _ in 0..<6 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            voices.append(node)
        }
    }

    /// - Parameters:
    ///   - direction: -1 = moving left, +1 = moving right.
    ///   - velocity: 0…1-ish; a touch louder when flicked fast.
    func play(direction: Int, velocity: Double = 0.4) {
        guard enabled, let buffer, !voices.isEmpty else { return }
        ensureRunning()
        guard started else { return }

        let node = voices[next]
        next = (next + 1) % voices.count
        let v = Float(min(max(velocity, 0), 1))
        node.pan = Float(direction) * 0.45
        node.volume = 0.42 + v * 0.34
        node.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        node.play()
    }

    private func ensureRunning() {
        guard !started else { return }
        do { try engine.start(); started = true } catch { started = false }
    }

    private func makeTick() -> AVAudioPCMBuffer? {
        // v02: 1500 Hz, 8 ms, 1 ms attack, decay_k=400, 4% pitch drop — ultra-light tick.
        let sr = format.sampleRate
        let dur = 0.008
        let n = AVAudioFrameCount(sr * dur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n) else { return nil }
        buf.frameLength = n
        let ch = buf.floatChannelData![0]

        let twoPi = Float.pi * 2
        let f0: Float = 1500
        let attack: Float = 0.001
        let total = Float(dur)
        let count = Int(n)
        let fade = max(1, Int(sr * 0.001))

        for i in 0..<count {
            let t = Float(i) / Float(sr)
            let a: Float = t < attack ? 0.5 - 0.5 * cosf(.pi * t / attack) : 1
            var env = a * expf(-t * 400)
            if i > count - fade { env *= Float(count - i) / Float(fade) }
            let freq = f0 * (1.0 - 0.04 * t / total)
            ch[i] = sinf(twoPi * freq * t) * env * 0.35
        }
        return buf
    }
}
