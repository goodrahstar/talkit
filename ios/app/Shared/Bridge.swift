import Foundation

/// Talk between the keyboard and the app: Darwin notifications carry the signal,
/// the shared App Group defaults carry the text.
enum Bridge {
    static let group = "group.app.parakeet.dictate.rk"
    static let shared = UserDefaults(suiteName: group)

    enum Signal: String, CaseIterable {
        case ping, pong, start, stop, cancel, result, failed
        var name: String { "app.parakeet.dictate.rk.\(rawValue)" }
    }

    static func post(_ signal: Signal) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(signal.name as CFString), nil, nil, true)
    }

    private static var handlers: [String: () -> Void] = [:]
    private static let lock = NSLock()

    /// Handlers run on the main queue.
    static func observe(_ signal: Signal, _ handler: @escaping () -> Void) {
        lock.withLock { handlers[signal.name] = handler }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
            guard let name = name?.rawValue as String? else { return }
            let handler = Bridge.lock.withLock { Bridge.handlers[name] }
            DispatchQueue.main.async { handler?() }
        }, signal.name as CFString, nil, .deliverImmediately)
    }

    // Shared values
    static var resultText: String {
        get { shared?.string(forKey: "resultText") ?? "" }
        set { shared?.set(newValue, forKey: "resultText") }
    }
}
