import AVFoundation
import ReplayKit
import Darwin

protocol ScreenAudioCaptureDelegate: AnyObject {
    func screenAudioCapture(_ capture: ScreenAudioCapture, didReceivePCMBuffer buffer: AVAudioPCMBuffer)
    func screenAudioCaptureDidStart(_ capture: ScreenAudioCapture)
    func screenAudioCapture(_ capture: ScreenAudioCapture, didFailWithError error: Error)
    func screenAudioCaptureDidStop(_ capture: ScreenAudioCapture)
}

/// Captures internal app audio using one of two strategies:
///
/// **Strategy A — RPScreenRecorder (SideStore / AltStore)**
///   The app runs in its own process, so iOS grants screen-recording
///   permission normally. `startCapture` is tried first.
///
/// **Strategy B — UDP listener (LiveContainer)**
///   LiveContainer runs the app inside its own process, so RPScreenRecorder
///   is blocked. Instead the Broadcast Upload Extension (TranslatorPiPBroadcast)
///   captures audio and streams it to the main app on localhost:14731.
///   This mode activates automatically if Strategy A fails within 3 s.
final class ScreenAudioCapture: NSObject {

    weak var delegate: ScreenAudioCaptureDelegate?
    private(set) var isCapturing = false
    private(set) var activeStrategy: Strategy = .none

    enum Strategy { case none, replayKit, broadcastExtension }

    // ReplayKit
    private let recorder = RPScreenRecorder.shared()

    // UDP fallback
    private var socketFd: Int32 = -1
    private let udpPort: UInt16 = 14731
    private var fallbackTimer: DispatchWorkItem?

    // MARK: — Public API

    func startCapture() {
        guard !isCapturing else { return }
        tryReplayKit()
    }

    func stopCapture() {
        guard isCapturing else { return }
        fallbackTimer?.cancel()
        fallbackTimer = nil
        isCapturing = false
        activeStrategy = .none

        recorder.stopCapture { _ in }

        if socketFd >= 0 { Darwin.close(socketFd); socketFd = -1 }

        DispatchQueue.main.async { self.delegate?.screenAudioCaptureDidStop(self) }
    }

    // MARK: — Strategy A: RPScreenRecorder

    private func tryReplayKit() {
        guard RPScreenRecorder.shared().isAvailable else {
            // RPScreenRecorder not available at all — go straight to UDP
            startUDPListener()
            return
        }

        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false

        // Schedule fallback: if startCapture callback isn't called within 3 s,
        // RPScreenRecorder is probably blocked (LiveContainer) — switch to UDP.
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isCapturing else { return }
            self.recorder.stopCapture { _ in }
            self.startUDPListener()
        }
        fallbackTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)

        recorder.startCapture(
            handler: { [weak self] sampleBuffer, bufferType, error in
                guard let self else { return }
                if let error {
                    // RPScreenRecorder rejected — switch to UDP
                    self.fallbackTimer?.cancel()
                    if !self.isCapturing { self.startUDPListener() }
                    return
                }
                guard bufferType == .audioApp,
                      let pcm = sampleBuffer.asPCMBuffer() else { return }
                self.delegate?.screenAudioCapture(self, didReceivePCMBuffer: pcm)
            },
            completionHandler: { [weak self] error in
                guard let self else { return }
                self.fallbackTimer?.cancel()
                if let error {
                    // Completion called with error — switch to UDP
                    if !self.isCapturing { self.startUDPListener() }
                    return
                }
                // RPScreenRecorder started successfully
                self.isCapturing = true
                self.activeStrategy = .replayKit
                DispatchQueue.main.async {
                    self.delegate?.screenAudioCaptureDidStart(self)
                }
            }
        )
    }

    // MARK: — Strategy B: UDP listener (Broadcast Extension → main app)

    private func startUDPListener() {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { fail("socket() failed: \(errno)"); return }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = udpPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            Darwin.close(fd)
            fail("UDP bind failed on port \(udpPort): \(errno)")
            return
        }

        socketFd = fd
        isCapturing = true
        activeStrategy = .broadcastExtension
        DispatchQueue.main.async { self.delegate?.screenAudioCaptureDidStart(self) }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var buf = [UInt8](repeating: 0, count: 65536)
            while let self = self, self.isCapturing {
                let n = recv(fd, &buf, buf.count, 0)
                guard n > 12 else { continue }
                self.processPacket(Data(buf[0..<n]))
            }
        }
    }

    // MARK: — UDP packet decoding

    private func processPacket(_ data: Data) {
        guard data.count >= 12 else { return }
        let sr = data.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)) }
        let ch = data.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
        let fc = data.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self)) }
        guard sr > 0, ch > 0, fc > 0, data.count >= 12 + Int(fc * ch * 4) else { return }

        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: Double(sr),
                                      channels: AVAudioChannelCount(ch),
                                      interleaved: false),
              let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: fc) else { return }
        pcm.frameLength = fc

        if let dst = pcm.floatChannelData {
            data.withUnsafeBytes { raw in
                let src = raw.baseAddress!.advanced(by: 12).bindMemory(to: Float.self, capacity: Int(fc * ch))
                for c in 0..<Int(ch) {
                    for f in 0..<Int(fc) { dst[c][f] = src[c * Int(fc) + f] }
                }
            }
        }
        delegate?.screenAudioCapture(self, didReceivePCMBuffer: pcm)
    }

    private func fail(_ msg: String) {
        let err = NSError(domain: "ScreenAudioCapture", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        DispatchQueue.main.async { self.delegate?.screenAudioCapture(self, didFailWithError: err) }
    }
}

// MARK: — CMSampleBuffer → AVAudioPCMBuffer (used by ReplayKit path)

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
