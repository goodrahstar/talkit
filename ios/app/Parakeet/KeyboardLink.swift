import Foundation

/// App side of the keyboard bridge. Only answers while the app is running,
/// which is exactly when the mic can be used, so a reply means "ready".
@MainActor
enum KeyboardLink {
    static func start() {
        Bridge.observe(.ping) { reply() }
        Bridge.observe(.start) {
            let dictation = Dictation.shared
            guard dictation.micRunning else { Bridge.post(.failed); return }
            do { try dictation.start(chime: false) } catch { Bridge.post(.failed) }
        }
        Bridge.observe(.stop) {
            Task { @MainActor in
                let text = await Dictation.shared.stop(copy: false)
                Bridge.resultText = text
                Bridge.post(.result)
            }
        }
        Bridge.observe(.cancel) { Dictation.shared.cancel() }
    }

    static func reply() {
        if Dictation.shared.micRunning { Bridge.post(.pong) }
    }
}
