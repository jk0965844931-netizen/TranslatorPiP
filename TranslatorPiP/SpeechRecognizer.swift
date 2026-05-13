import Speech
import AVFoundation

protocol SpeechRecognizerDelegate: AnyObject {
    func speechRecognizer(_ recognizer: SpeechRecognizer, didRecognize text: String, isFinal: Bool)
    func speechRecognizer(_ recognizer: SpeechRecognizer, didFailWithError error: Error)
}

final class SpeechRecognizer: NSObject {
    weak var delegate: SpeechRecognizerDelegate?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sourceLocale: Locale

    init(sourceLocale: Locale = Locale(identifier: "en-US")) {
        self.sourceLocale = sourceLocale
        super.init()
        setupRecognizer(locale: sourceLocale)
    }

    func updateSourceLocale(_ locale: Locale) {
        sourceLocale = locale
        setupRecognizer(locale: locale)
    }

    private func setupRecognizer(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
        recognizer?.defaultTaskHint = .dictation
    }

    func startRecognition() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            guard status == .authorized else {
                let err = NSError(
                    domain: "SpeechRecognizer",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "ไม่ได้รับอนุญาตให้ใช้ Speech Recognition"]
                )
                DispatchQueue.main.async {
                    self.delegate?.speechRecognizer(self, didFailWithError: err)
                }
                return
            }
            DispatchQueue.main.async {
                self.beginRecognition()
            }
        }
    }

    private func beginRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.delegate?.speechRecognizer(self, didFailWithError: error)
                }
                return
            }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                DispatchQueue.main.async {
                    self.delegate?.speechRecognizer(self, didRecognize: text, isFinal: isFinal)
                }
            }
        }
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stopRecognition() {
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    func restartRecognition() {
        stopRecognition()
        beginRecognition()
    }
}
