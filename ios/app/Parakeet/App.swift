import SwiftUI

@main
struct ParakeetApp: App {
    init() { KeyboardLink.start() }

    var body: some Scene {
        WindowGroup {
            MainView()
                .onOpenURL { url in
                    // parakeet://start from the keyboard: turn the mic on for this session.
                    guard url.host == "start" else { return }
                    try? Dictation.shared.startMic()
                    Dictation.shared.keepReadyIfOff()
                }
        }
    }
}

struct MainView: View {
    @State private var dictation = Dictation.shared
    @State private var showGuide = false

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button { showGuide = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("How to set up Talkit")
                Spacer()
                ModelBadge(status: dictation.modelStatus) {
                    Task { _ = try? await dictation.loadModel() }
                }
            }
            .padding(.horizontal, 20)
            Spacer()
            Text(dictation.lastText.isEmpty ? "press and talk." : dictation.lastText)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(dictation.lastText.isEmpty ? Color.secondary : Color.primary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.horizontal, 24)
            Spacer()
            Button {
                Task { _ = await dictation.toggle() }
            } label: {
                Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(width: 112, height: 112)
                    .background(Circle().fill(Color.primary))
            }
            .disabled(dictation.state == .transcribing)
            Text(status).font(.footnote).foregroundStyle(.secondary)
            Picker("keep mic ready", selection: $dictation.keepReadyMinutes) {
                Text("off").tag(0)
                Text("5 min").tag(5)
                Text("15 min").tag(15)
                Text("60 min").tag(60)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            Text("how long the mic stays ready, so the keyboard works without opening this app.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
        }
        .padding(.top, 8)
        .padding(.bottom, 32)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $showGuide) { GuideView() }
        .onAppear { if CommandLine.arguments.contains("-guide") { showGuide = true } }
        .task {
            // Load straight away if the model is on the phone; a missing model waits for a tap.
            if dictation.modelStatus != .missing { _ = try? await dictation.loadModel() }
        }
    }

    private var status: String {
        switch dictation.state {
        case .loading:
            switch dictation.modelStatus {
            case .missing: return "tap the cloud to download the model (about 460 MB)"
            case .downloading(let f): return "downloading model · \(Int(f * 100))%"
            default: return "loading model"
            }
        case .ready:
            var s = dictation.micLive ? "mic ready" : "ready"
            if let t = dictation.lastTranscribeSeconds { s += String(format: " · last %.2fs", t) }
            if let l = dictation.loadSeconds { s += String(format: " · model %.2fs", l) }
            return s
        case .recording: return "listening"
        case .transcribing: return "transcribing"
        case .failed(let why): return why
        }
    }
}

/// Top-right model indicator: outlined cloud = not downloaded, animated while downloading
/// or loading, green cloud = in memory and ready.
struct ModelBadge: View {
    let status: Dictation.ModelStatus
    let download: () -> Void

    var body: some View {
        Button(action: download) {
            ZStack {
                if case .downloading(let fraction) = status {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    Circle().trim(from: 0, to: max(0.03, fraction))
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                }
                icon
            }
            .frame(width: 44, height: 44)
        }
        .disabled(status != .missing)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var icon: some View {
        switch status {
        case .missing:
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
        case .downloading:
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.primary)
                .symbolEffect(.bounce.down, options: .repeating)
        case .loading:
            Image(systemName: "icloud")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.green)
                .symbolEffect(.pulse, options: .repeating)
        case .loaded:
            Image(systemName: "checkmark.icloud.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.green)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var label: String {
        switch status {
        case .missing: return "Model not downloaded. Tap to download."
        case .downloading(let f): return "Downloading model, \(Int(f * 100)) percent"
        case .loading: return "Loading model"
        case .loaded: return "Model ready"
        }
    }
}

/// Setup and how-to, opened from the info button.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section("set up once") {
                    step(1, "open **Settings → General → Keyboard → Keyboards → Add New Keyboard** and pick **Talkit**.")
                    step(2, "tap **Talkit** in that list and turn on **Allow Full Access**. the keyboard needs it to talk to this app.")
                    step(3, "back here, tap the **cloud** in the top right to download the model (about 460 MB). wait for the green check.")
                    step(4, "set **keep mic ready** to 60 min so you rarely have to open this app.")
                    Button("open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section("use it in any app") {
                    step(1, "tap a text box, hold the \(Image(systemName: "globe")) **globe** key and pick **Talkit**.")
                    step(2, "**hold** the bar and talk.")
                    step(3, "**let go.** the text is typed where your cursor is.")
                }
                Section("once per session") {
                    Text("if the bar says **tap to turn on Talkit**, tap it. this app opens for a second; tap **◀** in the top left to go back. iOS only lets the mic start while this app is on screen. after that it stays ready for the time you picked.")
                }
                Section("good to know") {
                    Text("everything runs on this phone. no audio leaves it.")
                    Text("the orange dot means the mic is ready. it turns off after the time you picked.")
                    Text("built with a free Apple account, so it needs reinstalling from the Mac every 7 days.")
                }
            }
            .font(.system(size: 15))
            .navigationTitle("how to use talkit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("done") { dismiss() } }
            }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.secondary)
            Text(text)
        }
    }
}
