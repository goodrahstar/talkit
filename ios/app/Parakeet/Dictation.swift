import AVFoundation
import AudioToolbox
import FluidAudio
import Observation
import UIKit
import os

let log = Logger(subsystem: "app.parakeet", category: "dictation")

/// Owns the model, the mic and the clipboard. One instance for the whole app.
@MainActor @Observable
final class Dictation {
    static let shared = Dictation()

    enum State: Equatable { case loading(String), ready, recording, transcribing, failed(String) }

    private(set) var state: State = .loading("starting")
    private(set) var lastText = ""
    private(set) var micLive = false
    private(set) var loadSeconds: Double?
    private(set) var lastTranscribeSeconds: Double?

    enum ModelStatus: Equatable { case missing, downloading(Double), loading, loaded }
    private(set) var modelStatus: ModelStatus =
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3) ? .loading : .missing

    /// Minutes the mic stays ready in the background after a dictation. 0 = mic off right away.
    var keepReadyMinutes: Int = UserDefaults.standard.object(forKey: "keepReadyMinutes") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(keepReadyMinutes, forKey: "keepReadyMinutes"); scheduleIdleStop() }
    }

    private var manager: AsrManager?
    private var loadTask: Task<AsrManager, Error>?
    private let engine = AVAudioEngine()
    private let capture = SampleSink()
    private var idleTimer: Timer?

    // MARK: Model

    /// Loads Parakeet v3 once and keeps it in memory. Safe to call many times.
    @discardableResult
    func loadModel() async throws -> AsrManager {
        if let manager { return manager }
        if let loadTask { return try await loadTask.value }
        let task = Task<AsrManager, Error> {
            let started = Date()
            await MainActor.run {
                self.state = .loading(self.modelStatus == .missing ? "downloading model" : "loading model")
                if self.modelStatus == .missing { self.modelStatus = .downloading(0) }
            }
            let models = try await AsrModels.downloadAndLoad(version: .v3) { progress in
                Task { @MainActor in
                    switch progress.phase {
                    case .compiling: Dictation.shared.modelStatus = .loading
                    default:
                        if case .downloading = Dictation.shared.modelStatus {
                            Dictation.shared.modelStatus = .downloading(progress.fractionCompleted)
                        }
                    }
                }
            }
            let config = ASRConfig(
                tdtConfig: TdtConfig(blankId: AsrModelVersion.v3.blankId),
                encoderHiddenSize: AsrModelVersion.v3.encoderHiddenSize)
            let manager = AsrManager(config: config)
            try await manager.loadModels(models)
            let seconds = Date().timeIntervalSince(started)
            log.notice("model loaded in \(seconds, format: .fixed(precision: 3))s")
            await MainActor.run { self.loadSeconds = seconds }
            return manager
        }
        loadTask = task
        do {
            let manager = try await task.value
            self.manager = manager
            modelStatus = .loaded
            if state != .recording { state = .ready }
            return manager
        } catch {
            loadTask = nil
            modelStatus = .missing  // tap the cloud to retry
            state = .failed("model: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: Mic

    /// Starts the audio session and engine. Must first happen while the app is on screen.
    func startMic() throws {
        if engine.isRunning { micLive = true; return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        capture.configure(from: format)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [capture] buffer, _ in
            capture.append(buffer)
        }
        engine.prepare()
        try engine.start()
        micLive = true
        Bridge.post(.pong)
        log.notice("mic live")
    }

    func stopMic() {
        idleTimer?.invalidate()
        guard engine.isRunning else { micLive = false; return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        micLive = false
        log.notice("mic off")
    }

    /// The keyboard needs the mic to stay on; "off" would end the session at once.
    func keepReadyIfOff() {
        if keepReadyMinutes == 0 { keepReadyMinutes = 60 } else { scheduleIdleStop() }
    }

    private func scheduleIdleStop() {
        idleTimer?.invalidate()
        guard micLive, state != .recording else { return }
        if keepReadyMinutes == 0 { stopMic(); return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: Double(keepReadyMinutes) * 60, repeats: false) { _ in
            Task { @MainActor in Dictation.shared.stopMic() }
        }
    }

    // MARK: Dictation

    var isRecording: Bool { state == .recording }

    /// True only while the audio engine really runs (a phone call can stop it behind our back).
    var micRunning: Bool {
        if micLive && !engine.isRunning { micLive = false }
        return micLive
    }

    func start(chime: Bool = true) throws {
        guard state != .recording, state != .transcribing else { return }
        idleTimer?.invalidate()
        try startMic()
        capture.begin()
        state = .recording
        if chime { AudioServicesPlaySystemSound(1113) }
        // Load in parallel with speaking, in case iOS dropped the model.
        if manager == nil { Task { try? await loadModel() } }
    }

    /// Stops recording and transcribes. Copies to the clipboard unless the keyboard asked
    /// (the keyboard types the text itself). Returns the text.
    @discardableResult
    func stop(copy: Bool = true) async -> String {
        guard state == .recording else { return "" }
        let samples = capture.end()
        if copy { AudioServicesPlaySystemSound(1114) }
        state = .transcribing
        defer { scheduleIdleStop() }
        guard samples.count > 16_000 / 4 else { state = .ready; return "" }
        do {
            let manager = try await loadModel()
            var decoder = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
            let started = Date()
            let result = try await manager.transcribe(samples, decoderState: &decoder)
            lastTranscribeSeconds = Date().timeIntervalSince(started)
            let text = clean(result.text)
            log.notice("transcribed \(Double(samples.count) / 16_000, format: .fixed(precision: 1))s audio in \(self.lastTranscribeSeconds ?? 0, format: .fixed(precision: 3))s")
            if !text.isEmpty {
                if copy { UIPasteboard.general.string = text }
                lastText = text
            }
            state = .ready
            return text
        } catch {
            state = .failed("transcribe: \(error.localizedDescription)")
            return ""
        }
    }

    func cancel() {
        guard state == .recording else { return }
        _ = capture.end()
        state = .ready
        scheduleIdleStop()
    }

    func toggle() async -> String? {
        if isRecording { return await stop() }
        try? start()
        return nil
    }

    private func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<unk>", with: "")
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Collects mic audio as 16 kHz mono floats, off the main thread.
final class SampleSink: @unchecked Sendable {
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var active = false
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    func configure(from format: AVAudioFormat) {
        lock.withLock { converter = AVAudioConverter(from: format, to: target) }
    }

    func begin() { lock.withLock { samples.removeAll(keepingCapacity: true); active = true } }

    func end() -> [Float] { lock.withLock { active = false; return samples } }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard active, let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let data = out.floatChannelData?[0] {
            samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
        }
    }
}
