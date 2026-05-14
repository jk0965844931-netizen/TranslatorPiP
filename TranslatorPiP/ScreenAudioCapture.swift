import AVFoundation
import Darwin   // POSIX sockets

protocol ScreenAudioCaptureDelegate: AnyObject {
    func screenAudioCapture(_ capture: ScreenAudioCapture, didReceivePCMBuffer buffer: AVAudioPCMBuffer)
    func screenAudioCaptureDidStart(_ capture: ScreenAudioCapture)
    func screenAudioCapture(_ capture: ScreenAudioCapture, didFailWithError error: Error)
    func screenAudioCaptureDidStop(_ capture: ScreenAudioCapture)
}

/// Receives internal-audio PCM packets from the Broadcast Upload Extension
/// via UDP on localhost:14731.
///
/// The user must start a broadcast from Control Center → long-press Screen
/// Record → choose "TranslatorPiP" → tap Start Broadcast.
final class ScreenAudioCapture: NSObject {

    weak var delegate: ScreenAudioCaptureDelegate?
    private(set) var isCapturing = false

    private var socketFd: Int32 = -1
    private let udpPort: UInt16 = 14731

    func startCapture() {
        guard !isCapturing else { return }
        openSocket()
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        if socketFd >= 0 { close(socketFd); socketFd = -1 }
        DispatchQueue.main.async { self.delegate?.screenAudioCaptureDidStop(self) }
    }

    // MARK: — POSIX UDP listener

    private func openSocket() {
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
            fail("bind() failed on port \(udpPort): \(errno)")
            return
        }

        socketFd = fd
        isCapturing = true
        DispatchQueue.main.async { self.delegate?.screenAudioCaptureDidStart(self) }

        // Read loop on background thread
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var buf = [UInt8](repeating: 0, count: 65536)
            while let self = self, self.isCapturing {
                let n = recv(fd, &buf, buf.count, 0)
                guard n > 12 else { continue }
                let data = Data(buf[0..<n])
                self.processPacket(data)
            }
        }
    }

    // MARK: — Packet decoding

    private func processPacket(_ data: Data) {
        guard data.count >= 12 else { return }

        let sampleRate = data.withUnsafeBytes { ptr -> UInt32 in
            UInt32(bigEndian: ptr.loadUnaligned(fromByteOffset: 0, as: UInt32.self))
        }
        let channelCount = data.withUnsafeBytes { ptr -> UInt32 in
            UInt32(bigEndian: ptr.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        }
        let frameCount = data.withUnsafeBytes { ptr -> UInt32 in
            UInt32(bigEndian: ptr.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
        }

        guard sampleRate > 0, channelCount > 0, frameCount > 0 else { return }
        let expectedBytes = 12 + Int(frameCount) * Int(channelCount) * 4
        guard data.count >= expectedBytes else { return }

        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else { return }

        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount) else { return }
        pcm.frameLength = frameCount

        if let dst = pcm.floatChannelData {
            data.withUnsafeBytes { raw in
                let src = raw.baseAddress!.advanced(by: 12)
                    .bindMemory(to: Float.self, capacity: Int(frameCount * channelCount))
                for ch in 0..<Int(channelCount) {
                    for f in 0..<Int(frameCount) {
                        dst[ch][f] = src[ch * Int(frameCount) + f]
                    }
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
