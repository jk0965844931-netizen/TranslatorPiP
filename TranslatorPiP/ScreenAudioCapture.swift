import AVFoundation
import Darwin

protocol ScreenAudioCaptureDelegate: AnyObject {
    func screenAudioCapture(_ capture: ScreenAudioCapture, didReceivePCMBuffer buffer: AVAudioPCMBuffer)
    func screenAudioCaptureDidStart(_ capture: ScreenAudioCapture)
    func screenAudioCapture(_ capture: ScreenAudioCapture, didFailWithError error: Error)
    func screenAudioCaptureDidStop(_ capture: ScreenAudioCapture)
}

/// Receives internal-device audio sent by the TranslatorPiPBroadcast extension
/// over a local UDP socket (port 14731).
///
/// Why UDP (not RPScreenRecorder directly):
///   RPScreenRecorder.startCapture with .audioApp only captures the CURRENT
///   app's own audio output.  To capture audio from YouTube, Spotify, etc.,
///   a Broadcast Upload Extension is required — iOS routes all app audio to
///   the extension's RPBroadcastSampleHandler, which we relay over UDP.
final class ScreenAudioCapture: NSObject {

    weak var delegate: ScreenAudioCaptureDelegate?
    private(set) var isCapturing = false
    private(set) var activeStrategy: Strategy = .none

    enum Strategy { case none, replayKit, broadcastExtension }

    private var socketFd: Int32 = -1
    private let udpPort: UInt16 = 14731

    // MARK: — Public API

    func startCapture() {
        guard !isCapturing else { return }
        startUDPListener()
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        activeStrategy = .none
        if socketFd >= 0 { Darwin.close(socketFd); socketFd = -1 }
        DispatchQueue.main.async { self.delegate?.screenAudioCaptureDidStop(self) }
    }

    // MARK: — UDP listener (receives audio from Broadcast Extension)

    private func startUDPListener() {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { fail("socket() ล้มเหลว: errno \(errno)"); return }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse,
                   socklen_t(MemoryLayout<Int32>.size))

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
            fail("UDP bind ล้มเหลวบนพอร์ต \(udpPort): errno \(errno)")
            return
        }

        socketFd = fd
        isCapturing = true
        activeStrategy = .broadcastExtension
        DispatchQueue.main.async { self.delegate?.screenAudioCaptureDidStart(self) }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var buf = [UInt8](repeating: 0, count: 65536)
            while let self, self.isCapturing {
                let n = recv(fd, &buf, buf.count, 0)
                guard n > 12 else { continue }
                self.processPacket(Data(buf[0..<n]))
            }
        }
    }

    // MARK: — Packet decoding (header: sampleRate UInt32 | channels UInt32 | frameCount UInt32)

    private func processPacket(_ data: Data) {
        guard data.count >= 12 else { return }
        let sr = data.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)) }
        let ch = data.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
        let fc = data.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self)) }
        let expectedBytes = 12 + Int(fc * ch * 4)
        guard sr > 0, ch > 0, fc > 0, data.count >= expectedBytes else { return }

        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: Double(sr),
                                      channels: AVAudioChannelCount(ch),
                                      interleaved: false),
              let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: fc) else { return }
        pcm.frameLength = fc

        if let dst = pcm.floatChannelData {
            data.withUnsafeBytes { raw in
                let src = raw.baseAddress!.advanced(by: 12)
                    .bindMemory(to: Float.self, capacity: Int(fc * ch))
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
