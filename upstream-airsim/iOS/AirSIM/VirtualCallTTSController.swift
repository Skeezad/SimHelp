import AVFoundation
import CallKit
import Foundation

enum VirtualCallTTSError: LocalizedError {
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "The fake call has nothing to report"
        }
    }
}

/// Dashboard 虚拟来电的本地媒体源。CallKit Still responsible for system incoming call lifecycle and audio routing，
/// but answer/Hang up will not send to the module AT，Nor will a public network be established PCM session。
@MainActor
final class VirtualCallTTSController: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VirtualCallTTSController()

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var call: IncomingVoIPCall?
    private var started = false

    var isPrepared: Bool { call?.isVirtual == true }

    private override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func prepare(_ incoming: IncomingVoIPCall) throws {
        guard incoming.isVirtual, incoming.ttsText?.isEmpty == false else {
            throw VirtualCallTTSError.invalidPayload
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
        call = incoming
        started = false
    }

    /// can only be CXProvider activation CallKit 的 AVAudioSession Start broadcasting later。
    func start() {
        guard !started, let text = call?.ttsText else { return }
        started = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.preUtteranceDelay = 0.18
        synthesizer.speak(utterance)
    }

    func setMuted(_ muted: Bool) {
        if muted {
            _ = synthesizer.pauseSpeaking(at: .immediate)
        } else if synthesizer.isPaused {
            _ = synthesizer.continueSpeaking()
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        call = nil
        started = false
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard VirtualCallTTSController.shared.isPrepared else { return }
            // The completion of the broadcast is equivalent to the end of the remote end.；CallKit Collapse later by didDeactivate Clear media status。
            CallKitController.shared.reportCurrentCallEnded(reason: .remoteEnded)
        }
    }
}
