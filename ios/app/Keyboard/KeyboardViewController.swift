import SwiftUI
import UIKit

/// Hold the bar to talk, let go to type. The Talkit app does the listening;
/// this keyboard only sends start/stop and types the text it gets back.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.controller = self
        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.heightAnchor.constraint(equalToConstant: 236),
        ])
        host.didMove(toParent: self)
        model.hasFullAccess = hasFullAccess
        model.showsGlobe = needsInputModeSwitchKey
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.checkApp()
    }

    func type(_ text: String) {
        guard !text.isEmpty else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = !(before.isEmpty || before.last!.isWhitespace)
        textDocumentProxy.insertText((needsSpace ? " " : "") + text)
    }
}

@MainActor @Observable
final class KeyboardModel {
    enum Phase: Equatable { case checking, offline, ready, listening, writing }

    weak var controller: KeyboardViewController?
    var phase: Phase = .checking
    var hasFullAccess = true
    var showsGlobe = true
    private var timeout: DispatchWorkItem?
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    init() {
        Bridge.observe(.pong) { [weak self] in
            guard let self, self.phase == .checking || self.phase == .offline else { return }
            self.cancelTimeout(); self.phase = .ready
        }
        Bridge.observe(.failed) { [weak self] in
            self?.cancelTimeout(); self?.phase = .offline
        }
        Bridge.observe(.result) { [weak self] in
            guard let self, self.phase == .writing else { return }
            self.cancelTimeout()
            self.controller?.type(Bridge.resultText)
            self.phase = .ready
        }
    }

    /// Ask the app if its mic is on. No answer within half a second means it is not running.
    func checkApp() {
        phase = .checking
        Bridge.post(.ping)
        after(0.5) { [weak self] in if self?.phase == .checking { self?.phase = .offline } }
    }

    func press() {
        guard phase == .ready else { return }
        haptic.impactOccurred()
        phase = .listening
        Bridge.post(.start)
    }

    func release() {
        guard phase == .listening else { return }
        haptic.impactOccurred(intensity: 0.6)
        phase = .writing
        Bridge.post(.stop)
        after(15) { [weak self] in if self?.phase == .writing { self?.checkApp() } }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        cancelTimeout()
        let item = DispatchWorkItem(block: work)
        timeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelTimeout() { timeout?.cancel(); timeout = nil }
}

struct KeyboardView: View {
    @Bindable var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            if !model.hasFullAccess {
                notice("turn on Allow Full Access: Settings → General → Keyboard → Keyboards → Talkit")
            } else if model.phase == .offline {
                Link(destination: URL(string: "parakeet://start")!) {
                    bar(title: "tap to turn on Talkit", subtitle: "once per session, then tap ◀ to come back", filled: false)
                }
            } else {
                bar(title: title, subtitle: subtitle, filled: model.phase == .listening)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in if model.phase == .ready { model.press() } }
                        .onEnded { _ in model.release() })
            }
            HStack(spacing: 8) {
                if model.showsGlobe {
                    key(Image(systemName: "globe")) { model.controller?.advanceToNextInputMode() }
                }
                key(Text("space").font(.system(size: 15)), wide: true) { model.controller?.textDocumentProxy.insertText(" ") }
                key(Image(systemName: "delete.left")) { model.controller?.textDocumentProxy.deleteBackward() }
                key(Image(systemName: "return")) { model.controller?.textDocumentProxy.insertText("\n") }
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var title: String {
        switch model.phase {
        case .checking: return "connecting"
        case .listening: return "listening · let go to type"
        case .writing: return "writing"
        default: return "hold to talk"
        }
    }

    private var subtitle: String {
        model.phase == .ready ? "talkit · runs on this phone" : " "
    }

    private func bar(title: String, subtitle: String, filled: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: model.phase == .writing ? "ellipsis" : "mic.fill")
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: model.phase == .listening || model.phase == .writing)
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            Text(subtitle).font(.system(size: 12)).opacity(0.6)
        }
        .foregroundStyle(filled ? Color(uiColor: .systemBackground) : Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(filled ? Color.primary : Color(uiColor: scheme == .dark ? .systemGray4 : .white))
        )
        .scaleEffect(filled ? 0.98 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: filled)
        .contentShape(Rectangle())
    }

    private func notice(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func key(_ label: some View, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .foregroundStyle(Color.primary)
                .frame(maxWidth: wide ? .infinity : 52, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: scheme == .dark ? .systemGray3 : .systemGray4)))
        }
        .buttonStyle(.plain)
    }
}
