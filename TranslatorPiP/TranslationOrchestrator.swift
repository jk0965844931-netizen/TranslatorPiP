import AVFoundation
import Speech

protocol TranslationOrchestratorDelegate: AnyObject {
    func orchestrator(_ orchestrator: TranslationOrchestrator, didUpdateOriginal text: String)
    func orchestrator(_ orchestrator: TranslationOrchestrator, didUpdateTranslation text: String)
    func orchestratorDidStart(_ orchestrator: TranslationOrchestrator, strategy: ScreenAudioCapture.Strategy)
    func orchestratorDidStop(_ orchestrator: TranslationOrchestrator)
    func orchestrator(_ orchestrator: TranslationOrchestrator, didFailWithError error: Error)
}

final class TranslationOrchestrator: NSObject {
    weak var delegate: TranslationOrchestratorDelegate?

    var sourceLanguage: LanguageOption = .english
    var targetLanguage: LanguageOption = .thai
    var activeStrategy: ScreenAudioCapture.Strategy { audioCapture.activeStrategy }

    private let audioCapture = ScreenAudioCapture()
    private var speechRecognizer: SpeechRecognizer?
    private let translationService = TranslationService()
    private(set) var isRunning = false

    private var lastTranscribedText = ""
    private var translateDebounceTask: Task<Void, Never>?
    private var recognitionRestartTimer: Timer?

    override init() {
        super.init()
        audioCapture.delegate = self
    }

    func start() {
        guard !isRunning else { return }
        AudioSessionManager.shared.configure()
        speechRecognizer = SpeechRecognizer(sourceLocale: sourceLanguage.locale)
        speechRecognizer?.delegate = self
        speechRecognizer?.startRecognition()
        audioCapture.startCapture()
    }

    func stop() {
        guard isRunning else { return }
        translateDebounceTask?.cancel()
        recognitionRestartTimer?.invalidate()
        audioCapture.stopCapture()
        speechRecognizer?.stopRecognition()
        speechRecognizer = nil
        isRunning = false
        AudioSessionManager.shared.deactivate()
        delegate?.orchestratorDidStop(self)
    }

    private func translateText(_ text: String) {
        translateDebounceTask?.cancel()
        translateDebounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let result = try await translationService.translate(
                    text,
                    from: sourceLanguage.code,
                    to: targetLanguage.code
                )
                await MainActor.run {
                    self.delegate?.orchestrator(self, didUpdateTranslation: result)
                }
            } catch {
                await MainActor.run {
                    self.delegate?.orchestrator(self, didFailWithError: error)
                }
            }
        }
    }

    private func scheduleRecognitionRestart() {
        recognitionRestartTimer?.invalidate()
        recognitionRestartTimer = Timer.scheduledTimer(withTimeInterval: 55, repeats: false) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.speechRecognizer?.restartRecognition()
        }
    }
}

extension TranslationOrchestrator: ScreenAudioCaptureDelegate {
    func screenAudioCapture(_ capture: ScreenAudioCapture, didReceivePCMBuffer buffer: AVAudioPCMBuffer) {
        speechRecognizer?.appendAudioBuffer(buffer)
    }

    func screenAudioCaptureDidStart(_ capture: ScreenAudioCapture) {
        isRunning = true
        scheduleRecognitionRestart()
        delegate?.orchestratorDidStart(self, strategy: capture.activeStrategy)
    }

    func screenAudioCapture(_ capture: ScreenAudioCapture, didFailWithError error: Error) {
        delegate?.orchestrator(self, didFailWithError: error)
    }

    func screenAudioCaptureDidStop(_ capture: ScreenAudioCapture) {}
}

extension TranslationOrchestrator: SpeechRecognizerDelegate {
    func speechRecognizer(_ recognizer: SpeechRecognizer, didRecognize text: String, isFinal: Bool) {
        guard text != lastTranscribedText, !text.isEmpty else { return }
        lastTranscribedText = text
        delegate?.orchestrator(self, didUpdateOriginal: text)
        translateText(text)
        if isFinal {
            speechRecognizer?.restartRecognition()
            scheduleRecognitionRestart()
        }
    }

    func speechRecognizer(_ recognizer: SpeechRecognizer, didFailWithError error: Error) {
        let nsErr = error as NSError
        if nsErr.domain == "kAFAssistantErrorDomain" && nsErr.code == 1110 {
            speechRecognizer?.restartRecognition()
        } else {
            delegate?.orchestrator(self, didFailWithError: error)
        }
    }
}

enum LanguageOption: String, CaseIterable {
    case english = "English"
    case thai = "Thai"
    case japanese = "Japanese"
    case chinese = "Chinese (Simplified)"
    case korean = "Korean"
    case french = "French"
    case german = "German"
    case spanish = "Spanish"

    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en-US")
        case .thai: return Locale(identifier: "th-TH")
        case .japanese: return Locale(identifier: "ja-JP")
        case .chinese: return Locale(identifier: "zh-CN")
        case .korean: return Locale(identifier: "ko-KR")
        case .french: return Locale(identifier: "fr-FR")
        case .german: return Locale(identifier: "de-DE")
        case .spanish: return Locale(identifier: "es-ES")
        }
    }

    var code: String {
        switch self {
        case .english: return "en"
        case .thai: return "th"
        case .japanese: return "ja"
        case .chinese: return "zh"
        case .korean: return "ko"
        case .french: return "fr"
        case .german: return "de"
        case .spanish: return "es"
        }
    }
}
