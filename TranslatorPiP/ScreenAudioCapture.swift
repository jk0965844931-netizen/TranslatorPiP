import ReplayKit
import AVFoundation

protocol ScreenAudioCaptureDelegate: AnyObject {
    func screenAudioCapture(_ capture: ScreenAudioCapture, didReceiveAudioBuffer buffer: CMSampleBuffer)
    func screenAudioCaptureDidStart(_ capture: ScreenAudioCapture)
    func screenAudioCapture(_ capture: ScreenAudioCapture, didFailWithError error: Error)
    func screenAudioCaptureDidStop(_ capture: ScreenAudioCapture)
}

final class ScreenAudioCapture: NSObject {
    weak var delegate: ScreenAudioCaptureDelegate?
    private let recorder = RPScreenRecorder.shared()
    private(set) var isCapturing = false

    func startCapture() {
        guard !isCapturing else { return }
        guard recorder.isAvailable else {
            let err = NSError(
                domain: "ScreenAudioCapture",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "RPScreenRecorder ไม่พร้อมใช้งาน"]
            )
            delegate?.screenAudioCapture(self, didFailWithError: err)
            return
        }

        recorder.isMicrophoneEnabled = false

        recorder.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.delegate?.screenAudioCapture(self, didFailWithError: error)
                }
                return
            }
            if bufferType == .audioApp {
                self.delegate?.screenAudioCapture(self, didReceiveAudioBuffer: sampleBuffer)
            }
        }, completionHandler: { [weak self] error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.delegate?.screenAudioCapture(self, didFailWithError: error)
                }
                return
            }
            self.isCapturing = true
            DispatchQueue.main.async {
                self.delegate?.screenAudioCaptureDidStart(self)
            }
        })
    }

    func stopCapture() {
        guard isCapturing else { return }
        recorder.stopCapture { [weak self] error in
            guard let self else { return }
            self.isCapturing = false
            DispatchQueue.main.async {
                if let error {
                    self.delegate?.screenAudioCapture(self, didFailWithError: error)
                } else {
                    self.delegate?.screenAudioCaptureDidStop(self)
                }
            }
        }
    }
}
