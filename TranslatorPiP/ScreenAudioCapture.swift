import ReplayKit
import AVFoundation

protocol ScreenAudioCaptureDelegate: AnyObject {
    func screenAudioCapture(_ capture: ScreenAudioCapture, didReceivePCMBuffer buffer: AVAudioPCMBuffer)
    func screenAudioCaptureDidStart(_ capture: ScreenAudioCapture)
    func screenAudioCapture(_ capture: ScreenAudioCapture, didFailWithError error: Error)
    func screenAudioCaptureDidStop(_ capture: ScreenAudioCapture)
}

/// Captures internal app audio (not microphone) via ReplayKit screen recording.
/// The user will see the red iOS "recording" indicator at the top of the screen.
final class ScreenAudioCapture: NSObject {
    weak var delegate: ScreenAudioCaptureDelegate?
    private let recorder = RPScreenRecorder.shared()
    private(set) var isCapturing = false

    func startCapture() {
        guard !isCapturing else { return }

        guard recorder.isAvailable else {
            fail("Screen Recording ไม่พร้อมใช้งานบนอุปกรณ์นี้ (RPScreenRecorder.isAvailable = false)")
            return
        }

        // Capture internal app audio only — no microphone
        recorder.isMicrophoneEnabled = false
        recorder.cameraEnabled = false

        recorder.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.delegate?.screenAudioCapture(self, didFailWithError: error)
                }
                return
            }
            // Only pass internal app audio (not mic, not video)
            guard bufferType == .audioApp else { return }
            guard let pcm = sampleBuffer.asPCMBuffer() else { return }
            self.delegate?.screenAudioCapture(self, didReceivePCMBuffer: pcm)

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
        isCapturing = false
        recorder.stopCapture { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    self.delegate?.screenAudioCapture(self, didFailWithError: error)
                } else {
                    self.delegate?.screenAudioCaptureDidStop(self)
                }
            }
        }
    }

    private func fail(_ message: String) {
        let err = NSError(
            domain: "ScreenAudioCapture", code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        DispatchQueue.main.async {
            self.delegate?.screenAudioCapture(self, didFailWithError: err)
        }
    }
}

private extension CMSampleBuffer {
    func asPCMBuffer() -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(self) else { return nil }
        let fmt = AVAudioFormat(cmAudioFormatDescription: desc)
        let count = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard count > 0, let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: count) else { return nil }
        pcm.frameLength = count
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList
        ) == noErr else { return nil }
        return pcm
    }
}
