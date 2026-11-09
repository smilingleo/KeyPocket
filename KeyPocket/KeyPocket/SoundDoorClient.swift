import Foundation
import AVFoundation
import Combine
import KeyPocketCore

@MainActor
final class SoundDoorClient: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var status = "声波就绪"
    private var player: AVAudioPlayer?
    private var pending: CheckedContinuation<Void, Error>?
    private var active = false
    private var cancelled = false
    private var sessionID = UUID()
    private var observers: [NSObjectProtocol] = []
    private var interrupted = false
    private var timeout: Task<Void, Never>?

    func open(_ door: DoorKey, band: SoundBand, clock: @escaping () -> Int64) async throws {
        guard !active else { throw PocketError.invalid("已有声波请求正在进行") }
        try Task.checkCancellation()
        try SoundProtocol.validate(door, timestamp: clock())
        active = true; cancelled = false; interrupted = false; sessionID = UUID()
        let current = sessionID
        let audio = AVAudioSession.sharedInstance()
        let previousCategory = audio.category, previousMode = audio.mode, previousOptions = audio.categoryOptions
        defer {
            timeout?.cancel(); timeout = nil
            player?.stop(); player?.delegate = nil; player = nil
            observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
            try? audio.overrideOutputAudioPort(.none)
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
            try? audio.setCategory(previousCategory, mode: previousMode, options: previousOptions)
            active = false
        }
        do {
            try await withTaskCancellationHandler(operation: {
                self.status = "正在切换到手机扬声器…"
                // Only output is used: no recorder, input node, microphone capture,
                // Bluetooth A2DP/HFP, AirPlay, or voice-processing mode is enabled.
                // Apple's speaker override requires the playAndRecord category.
                try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try audio.setPreferredSampleRate(Double(SoundProtocol.sampleRate))
                try audio.setActive(true)
                try audio.overrideOutputAudioPort(.speaker)
                self.observeAudio(current: current)

                // A fixed sleep is insufficient when headphones are connected.
                // Require a stable, exclusively built-in-speaker route instead.
                let deadline = ProcessInfo.processInfo.systemUptime + 3
                var stableSince: TimeInterval?
                while true {
                    try Task.checkCancellation()
                    guard !self.cancelled else { throw CancellationError() }
                    guard !self.interrupted else { throw PocketError.invalid("音频被通话或其他系统操作中断，请结束后再试") }
                    let now = ProcessInfo.processInfo.systemUptime
                    if Self.isSpeaker(audio) {
                        if stableSince == nil { stableSince = now }
                        if now - stableSince! >= 0.2 { break }
                    } else { stableSince = nil }
                    guard now < deadline else { throw PocketError.invalid("声音仍未切换到手机扬声器，已停止发送。请检查耳机或音频输出设置") }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                guard audio.outputVolume >= 0.4 else { throw PocketError.invalid("手机扬声器音量偏低，请调高媒体音量至至少 40% 后再试") }
                // Generate the short-lived authorization after route setup so it
                // cannot age during an asynchronous Bluetooth audio transition.
                let hex = try SoundProtocol.authorization(door: door, timestamp: clock())
                let wave = try SoundProtocol.wave(hex: hex, band: band)
                let player = try AVAudioPlayer(data: wave, fileTypeHint: AVFileType.wav.rawValue)
                player.delegate = self; player.volume = 1
                guard player.prepareToPlay() else { throw PocketError.invalid("无法准备声波播放") }
                self.player = player
                try Task.checkCancellation()
                guard !self.cancelled, !self.interrupted, Self.isSpeaker(audio) else { throw PocketError.invalid("音频输出已改变，已停止发送") }
                self.status = "正在从手机扬声器发送（\(band.title)）…"
                try await withCheckedThrowingContinuation { continuation in
                    self.pending = continuation
                    if !player.play() { self.complete(.failure(PocketError.invalid("无法开始声波播放"))); return }
                    self.timeout = Task { [weak self] in
                        do { try await Task.sleep(nanoseconds: UInt64((player.duration + 2) * 1_000_000_000)) } catch { return }
                        guard let self, self.sessionID == current else { return }
                        self.complete(.failure(PocketError.invalid("声波播放超时；请先确认门的实际状态")))
                    }
                }
            }, onCancel: { [weak self] in Task { @MainActor in self?.cancel() } })
            status = "声波已发送，请确认门已打开"
        } catch {
            status = error is CancellationError ? "已取消声波发送" : error.localizedDescription
            throw error
        }
    }
    private static func isSpeaker(_ audio: AVAudioSession) -> Bool {
        !audio.currentRoute.outputs.isEmpty && audio.currentRoute.outputs.allSatisfy { $0.portType == .builtInSpeaker }
    }
    private func observeAudio(current: UUID) {
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active, self.sessionID == current, self.pending != nil else { return }
                if !Self.isSpeaker(.sharedInstance()) {
                    self.complete(.failure(PocketError.invalid("声音输出切换离开手机扬声器，已停止发送；请确认门的实际状态")))
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            guard began else { return }
            Task { @MainActor in
                guard let self, self.active, self.sessionID == current else { return }
                self.interrupted = true
                self.complete(.failure(PocketError.invalid("声波被音频中断，未自动重发；请确认门的实际状态")))
            }
        })
    }
    func cancel() { cancelled = true; complete(.failure(CancellationError())) }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player else { return }
        complete(flag ? .success(()) : .failure(PocketError.invalid("声波未完整播放，请确认门的实际状态")))
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player else { return }
        complete(.failure(error ?? PocketError.invalid("声波音频解码失败")))
    }
    private func complete(_ result: Result<Void, Error>) {
        guard let continuation = pending else { return }
        pending = nil; timeout?.cancel(); player?.stop()
        continuation.resume(with: result)
    }
}
