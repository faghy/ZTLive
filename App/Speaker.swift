import AVFoundation

/// Avvisi vocali: abbassano per un attimo Google Maps o la musica, poi li ripristinano.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        synthesizer.delegate = self
        // Impostare la categoria non interrompe l'audio degli altri finché la sessione non è attiva.
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
    }

    func say(_ text: String) {
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "it-IT")
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
