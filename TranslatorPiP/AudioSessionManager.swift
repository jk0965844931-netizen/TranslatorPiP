import AVFoundation

class AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {}

    func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            print("AudioSession configure error: \(error)")
        }
    }

    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("AudioSession deactivate error: \(error)")
        }
    }
}
