import AVFoundation

class AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {}

    /// Configure audio session for ReplayKit internal audio capture.
    /// Use .playback (not .playAndRecord) — ReplayKit manages its own recording session
    /// internally for .audioApp buffers. Using .playAndRecord would conflict.
    func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            print("AudioSession configure error: \(error)")
        }
    }

    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
        } catch {
            print("AudioSession deactivate error: \(error)")
        }
    }
}
