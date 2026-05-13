import ReplayKit
import AVFoundation

protocol ScreenAudioCaptureDelegate: AnyObject {
    func screenAudioCapture(_ capture: ScreenAudioCapture, didReceivePCMBuffer buffer: AVAudioPCMBuffer)
    func screenAudioCaptureDidStart(_ capture: ScreenAudioCapture)
    func screenAudioCapture(_ capture: ScreenAudioCapture, didFailWithError error: Error)
    func screenAudioCaptureDidStop(_ capture: ScreenAudioCapture)
}

final class ScreenAudioCapture: NSObject {
    weak var delegate: ScreenAudioCaptureDelegate?
    private let recorder = RPScreenRecorder.shared()
    private let audioEngine = AVAudioEngine()
    private(set) var isCapturing = false
    private var usingMic = false

    func startCapture() {
        guard !isCapturing else { return }
        if recorder.isAvailable {
            tryReplayKit()
        } else {
            startMicCapture()
        }
    }

    private func tryReplayKit() {
        recorder.isMicrophoneEnabled = false
        recorder.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard let self else { return }
            if error != nil {
                if !self.isCapturing {
                    DispatchQueue.main.async { self.startMicCapture() }
                }
                return
            }
            if bufferType == .audioApp, let pcm = sampleBuffer.asPCMBuffer() {
                self.delegate?.screenAudioCapture(self, didReceivePCMBuffer: pcm)
            }
        }, completionHandler: { [weak self] error in
            guard let self else { return }
            if let error {
                _ = error
                DispatchQueue.main.async { self.startMicCapture() }
                return
            }
            self.isCapturing = true
            self.usingMic = false
            DispatchQueue.main.async {
                self.delegate?.screenAudioCaptureDidStart(self)
            }
        })
    }

    func startMicCapture() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                self?.handleMicPermission(granted: granted)
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                self?.handleMicPermission(granted: granted)
            }
        }
    }

    private func handleMicPermission(granted: Bool) {
        guard granted else {
            let err = NSError(
                domain: "ScreenAudioCapture", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "ไม่ได้รับอนุญาตให้ใช้ไมโครโฟน กรุณาเปิดใน ตั้งค่า > TranslatorPiP"]
            )
            DispatchQueue.main.async {
                self.delegate?.screenAudioCapture(self, didFailWithError: err)
            }
            return
        }
        do {
            let input = audioEngine.inputNode
            let fmt = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] pcm, _ in
                guard let self else { return }
                self.delegate?.screenAudioCapture(self, didReceivePCMBuffer: pcm)
            }
            try audioEngine.start()
            isCapturing = true
            usingMic = true
            DispatchQueue.main.async {
                self.delegate?.screenAudioCaptureDidStart(self)
            }
        } catch {
            DispatchQueue.main.async {
                self.delegate?.screenAudioCapture(self, didFailWithError: error)
            }
        }
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        if usingMic {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            DispatchQueue.main.async {
                self.delegate?.screenAudioCaptureDidStop(self)
            }
        } else {
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
    }
}

private extension CMSampleBuffer {
    func asPCMBuffer() -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(self) else { return nil }
        // AVAudioFormat(cmAudioFormatDescription:) is non-failable in iOS 17+ SDK
        let fmt = AVAudioFormat(cmAudioFormatDescription: desc)
        let count = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: count) else { return nil }
        pcm.frameLength = count
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList
        ) == noErr else { return nil }
        return pcm
    }
}
