import AVFoundation

/// Short original tones synthesized in-process. If audio cannot start, the game stays silent.
final class TonePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    private var prepared = false
    private var available = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        self.format = format
        guard let format else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
    }

    func playTap() {
        play(frequency: 494, duration: 0.06, gain: 0.07)
    }

    func playScore() {
        play(frequency: 659, duration: 0.09, gain: 0.06)
    }

    func playFold() {
        play(frequency: 196, duration: 0.16, gain: 0.08)
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        guard format != nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            player.play()
            available = true
        } catch {
            available = false
        }
    }

    private func play(frequency: Double, duration: Double, gain: Float) {
        prepare()
        guard available, let format else { return }
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frameCount
        let attack = 0.012
        let sampleRate = format.sampleRate
        for index in 0..<Int(frameCount) {
            let time = Double(index) / sampleRate
            let attackGain = min(1, time / attack)
            let release = max(0, 1 - time / duration)
            let envelope = attackGain * release * release
            channel[index] = Float(sin(2 * Double.pi * frequency * time) * envelope) * gain
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }
}
