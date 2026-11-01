// Menu bar switch for the local Parakeet server (Neural Engine) and FreeFlow's speech-to-text mode.
// Every action shells out to ~/.local/bin/ffstt, which owns the real logic.

import AppKit

private let home = FileManager.default.homeDirectoryForCurrentUser.path
private let ffstt = "\(home)/.local/bin/ffstt"
private let serverLog = "\(home)/parakeet-server/server.log"
private let actionMarker = "\(home)/parakeet-server/menubar/last-action.txt"

struct Status {
    var mode = "groq"       // "ultra", "v3" or "groq"
    var running = false
    var loaded: [String] = []   // models currently held on the Neural Engine
}

private func shell(_ args: [String]) -> (code: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

private func readStatus() -> Status {
    var s = Status()
    let out = shell([ffstt, "status"]).out
    if out.contains("FreeFlow STT: ultra") { s.mode = "ultra" }
    else if out.contains("FreeFlow STT: v3") { s.mode = "v3" }
    s.running = out.contains("Parakeet server: running")
    if s.running,
       let data = shell(["-c", "curl -sf --max-time 2 http://127.0.0.1:5092/health"]).out.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        s.loaded = json["loaded"] as? [String] ?? []
    }
    return s
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let headerItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
    private let serverItem = NSMenuItem(title: "", action: #selector(toggleServer), keyEquivalent: "")
    private let ultraItem = NSMenuItem(title: "Parakeet Ultra · Neural Engine", action: #selector(useUltra), keyEquivalent: "")
    private let v3Item = NSMenuItem(title: "Parakeet v3 · Neural Engine", action: #selector(useV3), keyEquivalent: "")
    private let groqItem = NSMenuItem(title: "Groq Whisper · cloud", action: #selector(useGroq), keyEquivalent: "")
    private var status = Status()
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        headerItem.isEnabled = false
        for item in [serverItem, ultraItem, v3Item, groqItem] { item.target = self }

        let modeHeader = NSMenuItem(title: "FreeFlow dictation uses", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        let logItem = NSMenuItem(title: "Open Server Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        let quitItem = NSMenuItem(title: "Quit Parakeet Switch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.items = [headerItem, serverItem, .separator(), modeHeader, ultraItem, v3Item, groqItem,
                      .separator(), logItem, quitItem]
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

        render()
        refresh()
        // Catch changes made from the terminal or FreeFlow's own Settings.
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        guard !busy else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let s = readStatus()
            DispatchQueue.main.async {
                guard !self.busy else { return }
                self.status = s
                self.render()
            }
        }
    }

    private func render() {
        let button = statusItem.button
        let symbol = status.running ? "waveform" : "waveform.slash"
        button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Parakeet server")
        button?.image?.isTemplate = true
        button?.toolTip = status.running ? "Parakeet server on" : "Parakeet server off"

        if busy {
            headerItem.title = "Working…"
        } else if status.running {
            let names = ["parakeet-ultra": "Ultra", "parakeet-v3": "v3"]
            headerItem.title = status.loaded.isEmpty
                ? "Server on · nothing loaded"
                : "Server on · loaded: " + status.loaded.map { names[$0] ?? $0 }.joined(separator: ", ")
        } else {
            headerItem.title = "Server off"
        }
        serverItem.title = status.running ? "Turn Server Off (save memory)" : "Turn Server On"
        ultraItem.state = status.mode == "ultra" ? .on : .off
        v3Item.state = status.mode == "v3" ? .on : .off
        groqItem.state = status.mode == "groq" ? .on : .off
        for item in [serverItem, ultraItem, v3Item, groqItem] { item.isEnabled = !busy }
    }

    private func run(_ action: String) {
        guard !busy else { return }
        busy = true
        render()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = shell([ffstt, action])
            let s = readStatus()
            try? "\(action) exit=\(result.code) \(Date().timeIntervalSince1970)\n"
                .write(toFile: actionMarker, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                self.busy = false
                self.status = s
                self.render()
                if result.code != 0 { self.showError(action, result.out) }
            }
        }
    }

    private func showError(_ action: String, _ output: String) {
        let alert = NSAlert()
        alert.messageText = "ffstt \(action) failed"
        alert.informativeText = String(output.suffix(800))
        alert.runModal()
    }

    // ffstt off also moves FreeFlow to Groq so dictation keeps working.
    @objc private func toggleServer() { run(status.running ? "off" : "on") }
    // ffstt ultra / v3 start the server if it is off.
    @objc private func useUltra() { run("ultra") }
    @objc private func useV3() { run("v3") }
    @objc private func useGroq() { run("groq") }
    @objc private func openLog() { NSWorkspace.shared.open(URL(fileURLWithPath: serverLog)) }
    // parakeetswitch://on|off|ultra|v3|groq drives the same actions as the menu.
    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let action = URL(string: raw)?.host,
              ["on", "off", "ultra", "v3", "groq"].contains(action) else { return }
        run(action)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
