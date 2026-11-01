import AppIntents

/// One button: first press starts listening, second press stops and copies the text.
/// If the mic is already live it runs in the background; otherwise iOS opens the app once.
struct DictateIntent: AppIntent {
    static let title: LocalizedStringResource = "Dictate"
    static let description = IntentDescription("Start or stop Talkit dictation. The text is copied to the clipboard.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let dictation = Dictation.shared
        if dictation.isRecording {
            let text = await dictation.stop()
            return .result(value: text, dialog: text.isEmpty ? "Nothing heard" : "Copied")
        }
        if !dictation.micLive {
            // iOS only lets the mic start while the app is on screen.
            try await continueInForeground(alwaysConfirm: false)
        }
        try dictation.start()
        return .result(value: "", dialog: "Listening")
    }
}

struct ParakeetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DictateIntent(),
            phrases: ["Dictate with \(.applicationName)"],
            shortTitle: "Dictate",
            systemImageName: "mic.fill")
    }
}
