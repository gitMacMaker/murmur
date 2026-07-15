import Foundation
import AVFoundation
import Speech

/// Streams microphone audio into Apple's on-device speech recognizer and
/// reports live partial transcripts plus a mic level for the waveform.
final class Transcriber: NSObject {
    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestText = ""
    private var finishCompletion: ((String) -> Void)?
    private var finished = false

    var isRunning: Bool { engine.isRunning }

    func start() throws {
        latestText = ""
        finished = false
        finishCompletion = nil

        let locale = Locale(identifier: AppSettings.shared.localeID)
        recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "Murmur", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = AppSettings.shared.autoPunctuation
        if recognizer?.supportsOnDeviceRecognition == true {
            req.requiresOnDeviceRecognition = true
        }
        // Boost recognition of the user's dictionary phrases.
        let hints = AppSettings.shared.replacements
            .map(\.phrase)
            .filter { !$0.isEmpty }
        if !hints.isEmpty {
            req.contextualStrings = Array(hints.prefix(100))
        }
        request = req

        task = recognizer?.recognitionTask(with: req) { [weak self] result, _ in
            guard let self else { return }
            if let result {
                self.latestText = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.onPartial?(self.latestText) }
                if result.isFinal { self.deliverFinal() }
            }
        }

        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            self.onLevel?(Self.rmsLevel(of: buffer))
        }

        engine.prepare()
        try engine.start()
    }

    /// Stops capture and calls `completion` once with the best transcript.
    func stop(completion: @escaping (String) -> Void) {
        finishCompletion = completion
        tearDownAudio()
        request?.endAudio()
        // The recognizer usually flushes a final result quickly; don't wait forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.deliverFinal()
        }
    }

    func cancel() {
        finishCompletion = nil
        finished = true
        tearDownAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func tearDownAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func deliverFinal() {
        DispatchQueue.main.async {
            guard !self.finished, let completion = self.finishCompletion else { return }
            self.finished = true
            self.finishCompletion = nil
            self.task?.cancel()
            self.task = nil
            self.request = nil
            completion(self.latestText)
        }
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(n))
        // Map typical speech RMS (~0.005–0.2) onto 0…1 with a soft curve.
        let db = 20 * log10(max(rms, 0.0001))
        return max(0, min(1, (db + 50) / 40))
    }
}
