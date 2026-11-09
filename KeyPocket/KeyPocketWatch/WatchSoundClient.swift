import AVFoundation
import KeyPocketCore

@MainActor
final class WatchSoundClient: NSObject, AVAudioPlayerDelegate {
    private var completed: Bool?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { completed = flag }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { completed = false }
    private var activation: CheckedContinuation<Void, Error>?
    private var activationTimeout: Task<Void, Never>?
    private var activationID = UUID()
    private func completeActivation(_ result: Result<Void, Error>) {
        let pending = activation; activation = nil
        activationTimeout?.cancel(); activationTimeout = nil
        pending?.resume(with: result)
    }
    private func activate(_ audio: AVAudioSession) async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                activation = continuation
                activationID = UUID(); let current = activationID
                activationTimeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                    self?.completeActivation(.failure(PocketError.invalid("音频输出准备超时，请检查手表扬声器设置")))
                }
                audio.activate(options: []) { [weak self] activated, error in
                    Task { @MainActor in
                        guard let self, self.activationID == current else { return }
                        guard self.activation != nil else {
                            if activated { try? audio.setActive(false) }; return
                        }
                        if activated { self.completeActivation(.success(())) }
                        else { self.completeActivation(.failure(error ?? PocketError.invalid("无法准备手表扬声器"))) }
                    }
                }
            }
        }, onCancel: { [weak self] in Task { @MainActor in self?.completeActivation(.failure(CancellationError())) } })
        try Task.checkCancellation()
    }
    private var player: AVAudioPlayer?
    func cancel() { player?.stop(); completeActivation(.failure(CancellationError())) }
    func open(_ door: DoorKey, band: SoundBand, clock: () throws -> Int64) async throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default, policy: .longFormAudio)
        defer { player?.stop(); player = nil; try? audio.setActive(false) }
        try await activate(audio)
        // Never silently transmit to headphones instead of the receiver.
        guard !audio.currentRoute.outputs.isEmpty,
              audio.currentRoute.outputs.allSatisfy({ $0.portType == .builtInSpeaker }) else {
            throw PocketError.invalid("请将手表音频输出切换为内置扬声器后重试")
        }
        guard audio.outputVolume >= 0.4 else { throw PocketError.invalid("请将手表媒体音量调至至少 40%") }
        let hex = try SoundProtocol.authorization(door: door, timestamp: clock())
        let data = try SoundProtocol.wave(hex: hex, band: band)
        let p = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
        player = p
        completed = nil; p.delegate = self
        p.volume = 1
        guard p.prepareToPlay(), p.play() else { throw PocketError.invalid("无法从手表播放声波") }
        let deadline = ProcessInfo.processInfo.systemUptime + p.duration + 2
        while completed == nil {
            try Task.checkCancellation()
            guard audio.currentRoute.outputs.allSatisfy({ $0.portType == .builtInSpeaker }), ProcessInfo.processInfo.systemUptime < deadline else { throw PocketError.invalid("音频输出改变或播放超时，已停止") }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        try Task.checkCancellation()
        guard completed == true else { throw PocketError.invalid("声波播放被中断，请重试") }
    }
}
