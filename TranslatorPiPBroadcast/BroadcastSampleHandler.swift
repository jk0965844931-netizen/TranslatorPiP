import ReplayKit
import AVFoundation
import Network

/// Broadcast Upload Extension — runs as its own process outside LiveContainer.
/// iOS loads this directly when the user picks "TranslatorPiP" from Control Center.
/// Captures internal app audio (.audioApp) and streams raw PCM via UDP to the
/// main app on localhost:14731.
///
/// Packet format:
///   [0..3]  sampleRate   : UInt32 big-endian  (Hz, e.g. 44100)
///   [4..7]  channelCount : UInt32 big-endian  (always 1 — mono mix-down)
///   [8..11] frameCount   : UInt32 big-endian
///   [12..]  Float32 PCM  samples (mono, native endian)
class BroadcastSampleHandler: RPBroadcastSampleHandler {

    private var connection: NWConnection?
    private let udpPort: NWEndpoint.Port = 14731

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: udpPort)
        connection = NWConnection(to: endpoint, using: .udp)
        connection?.start(queue: .global(qos: .userInteractive))
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .audioApp,
              let data = encodeAsMono(sampleBuffer) else { return }
        connection?.send(content: data, completion: .idempotent)
    }

    override func broadcastFinished() {
        connection?.cancel()
        connection = nil
    }

    // MARK: — Encoding

    private func encodeAsMono(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let fmt = AVAudioFormat(cmAudioFormatDescription: desc)
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0 else { return nil }

        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount) else { return nil }
        pcm.frameLength = frameCount
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount), into: pcm.mutableAudioBufferList
        ) == noErr else { return nil }

        // Mix down to mono Float32
        let channelCount = Int(fmt.channelCount)
        var mono = [Float](repeating: 0, count: Int(frameCount))

        if let floatData = pcm.floatChannelData {
            let scale = 1.0 / Float(channelCount)
            for ch in 0..<channelCount {
                for f in 0..<Int(frameCount) {
                    mono[f] += floatData[ch][f] * scale
                }
            }
        } else if let int16Data = pcm.int16ChannelData {
            let scale = 1.0 / (Float(Int16.max) * Float(channelCount))
            for ch in 0..<channelCount {
                for f in 0..<Int(frameCount) {
                    mono[f] += Float(int16Data[ch][f]) * scale
                }
            }
        } else {
            return nil
        }

        let sampleRate = UInt32(fmt.sampleRate)
        var header = Data(count: 12)
        header.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: sampleRate.bigEndian,  toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: UInt32(1).bigEndian,   toByteOffset: 4, as: UInt32.self) // mono
            ptr.storeBytes(of: frameCount.bigEndian,  toByteOffset: 8, as: UInt32.self)
        }
        let audioData = mono.withUnsafeBytes { Data($0) }
        return header + audioData
    }
}
