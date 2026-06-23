import AVFoundation

/// Captures microphone audio while held and produces 16-bit PCM WAV data for
/// transcription. Uses AVAudioEngine with a tap that writes to a temp WAV file.
///
/// `@unchecked Sendable`: the render-thread tap and the main-thread `start`/`stop`
/// touch `file`/`isRecording`, a boundary AVAudioEngine itself defines. Tearing
/// the tap down on `stop()` is what bounds it; we own that contract here.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var fileURL: URL?
    private(set) var isRecording = false

    /// Live input level (0…1), delivered on the main actor for the waveform HUD.
    var onLevel: (@MainActor (Float) -> Void)?

    enum RecorderError: LocalizedError {
        case micPermissionDenied
        case startFailed(String)
        var errorDescription: String? {
            switch self {
            case .micPermissionDenied: return "Microphone access was denied. Enable it in System Settings → Privacy → Microphone."
            case .startFailed(let d): return "Couldn't start recording: \(d)"
            }
        }
    }

    /// Request microphone access. Only invokes the system request when the status
    /// is genuinely undetermined — once granted (or denied) we never re-ask, so a
    /// granted mic shouldn't re-prompt on each dictation.
    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in cont.resume(returning: granted) }
            }
        default:   // .denied / .restricted — caller surfaces guidance to Settings
            return false
        }
    }

    func start() throws {
        guard !isRecording else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Write 16-bit PCM WAV at the hardware sample rate / channel count. The
        // tap delivers float buffers; AVAudioFile converts to PCM on write.
        var settings = format.settings
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMBitDepthKey] = 16
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMIsBigEndianKey] = false

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("koifish-dictation-\(UUID().uuidString).wav")
        do {
            let audioFile = try AVAudioFile(forWriting: url, settings: settings)
            self.file = audioFile
            self.fileURL = url

            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                try? self.file?.write(from: buffer)
                if let level = Self.level(of: buffer), let onLevel = self.onLevel {
                    // Hop to the main actor: the HUD callback touches UI state.
                    DispatchQueue.main.async { MainActor.assumeIsolated { onLevel(level) } }
                }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            // Tear down so a failed start doesn't leak the temp file or leave stale
            // handles that a later stop() (which early-returns) would never clean.
            input.removeTap(onBus: 0)
            file = nil
            if let url = fileURL { try? FileManager.default.removeItem(at: url) }
            fileURL = nil
            throw RecorderError.startFailed(error.localizedDescription)
        }
    }

    /// Stop recording and return the captured WAV data (nil if nothing recorded).
    func stop() -> Data? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        file = nil // closes the file

        defer {
            if let url = fileURL { try? FileManager.default.removeItem(at: url) }
            fileURL = nil
        }
        guard let url = fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// RMS level of a buffer, mapped to a clamped 0…1 for display.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }
        var sumSquares: Float = 0
        for i in 0..<count { let sample = channel[i]; sumSquares += sample * sample }
        let rms = (sumSquares / Float(count)).squareRoot()
        // Speech RMS is tiny (~0.01–0.1); a linear gain leaves quiet talk flat.
        // A perceptual square-root curve lifts low levels hard so the meter
        // reacts to ordinary, even soft, speech — then clamp and gate hiss.
        guard rms > 0.0007 else { return 0 }
        return min(1, rms.squareRoot() * 3.5)
    }
}
