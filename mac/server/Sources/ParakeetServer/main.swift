// OpenAI-compatible speech-to-text server running NVIDIA Parakeet on the Apple Neural Engine.
//
// FreeFlow posts multipart audio to /v1/audio/transcriptions with a `model` field and reads
// {"text": ...}. Only one model ("parakeet-ultra" or "parakeet-v3") is loaded at a time: asking
// for the other one unloads the current one first. POST /activate/<model> preloads the chosen
// model (unloading the rest), POST /unload frees everything, and an idle model unloads after
// IDLE_UNLOAD_SECONDS.

import FluidAudio
import Foundation
import Network

let env = ProcessInfo.processInfo.environment
let port = UInt16(env["PARAKEET_PORT"] ?? "") ?? 5092
let idleUnloadSeconds = Double(env["PARAKEET_IDLE_UNLOAD_SECONDS"] ?? "") ?? 300

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("\(stamp) \(message)")
    fflush(stdout)
}

enum Model: String, CaseIterable {
    case ultra = "parakeet-ultra"
    case v3 = "parakeet-v3"

    var version: AsrModelVersion { self == .ultra ? .ultra : .v3 }

    // Unknown names fall back to Ultra; the old MLX name maps to v3.
    init(requested: String) {
        let name = requested.lowercased()
        self = name.contains("v3") ? .v3 : .ultra
    }
}

/// Fixes decoder artifacts: `<unk>` (Ultra emits it for "&") and doubled full stops.
func cleanTranscript(_ text: String) -> String {
    var s = text
    s = s.replacingOccurrences(of: #"(?<=\w)<unk>(?=\w)"#, with: "&", options: .regularExpression)
    s = s.replacingOccurrences(of: "<unk>", with: "")
    s = s.replacingOccurrences(of: #"(?<!\.)\.\.(?!\.)"#, with: ".", options: .regularExpression)
    s = s.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

actor Engine {
    private var current: (model: Model, manager: AsrManager)?
    private var loading: (model: Model, task: Task<AsrManager, Error>)?
    private var lastUsed = Date()

    func transcribe(_ model: Model, file: URL) async throws -> (text: String, seconds: Double) {
        let manager = try await activate(model)
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let started = Date()
        let result = try await manager.transcribe(file, decoderState: &state)
        lastUsed = Date()
        return (cleanTranscript(result.text), lastUsed.timeIntervalSince(started))
    }

    func loadedModels() -> [String] { current.map { [$0.model.rawValue] } ?? [] }

    func unload(reason: String) {
        guard let current else { return }
        self.current = nil
        log("unloaded \(current.model.rawValue) (\(reason))")
    }

    func unloadIfIdle() {
        guard current != nil, Date().timeIntervalSince(lastUsed) > idleUnloadSeconds else { return }
        unload(reason: "\(Int(idleUnloadSeconds))s idle")
    }

    /// Makes `model` the only loaded model. Concurrent callers share one in-flight load.
    @discardableResult
    func activate(_ model: Model) async throws -> AsrManager {
        lastUsed = Date()
        if let current, current.model == model { return current.manager }
        if let loading, loading.model == model { return try await loading.task.value }
        if let current { unload(reason: "switched to \(model.rawValue)") }
        let task = Task { try await Self.makeManager(model) }
        loading = (model, task)
        defer { if loading?.model == model { loading = nil } }
        let manager = try await task.value
        current = (model, manager)
        return manager
    }

    private static func makeManager(_ model: Model) async throws -> AsrManager {
        let started = Date()
        let models = try await AsrModels.downloadAndLoad(version: model.version)
        let config = ASRConfig(
            tdtConfig: TdtConfig(blankId: model.version.blankId),
            encoderHiddenSize: model.version.encoderHiddenSize)
        let manager = AsrManager(config: config)
        try await manager.loadModels(models)
        log("loaded \(model.rawValue) in \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
        return manager
    }
}

let engine = Engine()

// MARK: - HTTP

struct Request {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct Response {
    var status: Int
    var json: Any

    func serialized() -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 500: "Internal Server Error"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

let headerTerminator = Data("\r\n\r\n".utf8)

func parseHead(_ data: Data) -> (method: String, path: String, headers: [String: String])? {
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    var lines = text.components(separatedBy: "\r\n")
    let requestLine = lines.removeFirst().split(separator: " ")
    guard requestLine.count >= 2 else { return nil }
    var headers: [String: String] = [:]
    for line in lines {
        guard let colon = line.firstIndex(of: ":") else { continue }
        headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    let path = String(requestLine[1]).split(separator: "?").first.map(String.init) ?? "/"
    return (String(requestLine[0]), path, headers)
}

struct Part {
    let name: String
    let filename: String?
    let data: Data
}

func parseMultipart(_ body: Data, contentType: String) -> [Part] {
    guard let boundaryRange = contentType.range(of: "boundary=") else { return [] }
    var boundary = String(contentType[boundaryRange.upperBound...])
    if let semicolon = boundary.firstIndex(of: ";") { boundary = String(boundary[..<semicolon]) }
    boundary = boundary.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    let delimiter = Data("--\(boundary)".utf8)

    var parts: [Part] = []
    var cursor = body.startIndex
    while let start = body.range(of: delimiter, in: cursor..<body.endIndex) {
        let partStart = start.upperBound
        guard let next = body.range(of: delimiter, in: partStart..<body.endIndex) else { break }
        var chunk = body[partStart..<next.lowerBound]
        cursor = next.lowerBound
        if chunk.starts(with: Data("\r\n".utf8)) { chunk = chunk.dropFirst(2) }
        if chunk.suffix(2) == Data("\r\n".utf8) { chunk = chunk.dropLast(2) }
        guard let split = chunk.range(of: headerTerminator),
              let headerText = String(data: chunk[chunk.startIndex..<split.lowerBound], encoding: .utf8)
        else { continue }
        func attribute(_ key: String) -> String? {
            guard let r = headerText.range(of: "\(key)=\"") else { return nil }
            let rest = headerText[r.upperBound...]
            return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
        }
        guard let name = attribute("name") else { continue }
        parts.append(Part(name: name, filename: attribute("filename"), data: Data(chunk[split.upperBound...])))
    }
    return parts
}

func handle(_ request: Request) async -> Response {
    switch (request.method, request.path) {
    case ("GET", "/health"):
        return Response(status: 200, json: [
            "status": "ok", "engine": "neural-engine",
            "models": Model.allCases.map(\.rawValue), "loaded": await engine.loadedModels(),
        ])
    case ("GET", "/v1/models"):
        return Response(status: 200, json: [
            "object": "list",
            "data": Model.allCases.map { ["id": $0.rawValue, "object": "model", "owned_by": "local"] },
        ])
    case ("POST", "/v1/audio/transcriptions"):
        return await transcribe(request)
    case ("POST", "/unload"):
        await engine.unload(reason: "requested")
        return Response(status: 200, json: ["loaded": [String]()])
    case ("POST", let path) where path.hasPrefix("/activate/"):
        let name = String(path.dropFirst("/activate/".count))
        guard let model = Model(rawValue: name) else {
            return Response(status: 400, json: ["error": "unknown model \(name)"])
        }
        do {
            try await engine.activate(model)
            return Response(status: 200, json: ["loaded": await engine.loadedModels()])
        } catch {
            return Response(status: 500, json: ["error": "\(error)"])
        }
    default:
        return Response(status: 404, json: ["error": "not found"])
    }
}

func transcribe(_ request: Request) async -> Response {
    let parts = parseMultipart(request.body, contentType: request.headers["content-type"] ?? "")
    guard let file = parts.first(where: { $0.name == "file" }), !file.data.isEmpty else {
        return Response(status: 400, json: ["error": "missing audio file"])
    }
    let requested = parts.first(where: { $0.name == "model" }).flatMap { String(data: $0.data, encoding: .utf8) } ?? ""
    let format = parts.first(where: { $0.name == "response_format" }).flatMap { String(data: $0.data, encoding: .utf8) } ?? "json"
    let model = Model(requested: requested)

    let ext = (file.filename as NSString?)?.pathExtension ?? ""
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("parakeet-\(UUID().uuidString).\(ext.isEmpty ? "wav" : ext)")
    do {
        try file.data.write(to: url)
        let result = try await engine.transcribe(model, file: url)
        log("\(model.rawValue) transcribed \(file.data.count) bytes in \(String(format: "%.2f", result.seconds))s: \(result.text.prefix(80))")

        try? FileManager.default.removeItem(at: url)

        if format == "verbose_json" {
            return Response(status: 200, json: ["task": "transcribe", "text": result.text, "segments": []])
        }
        return Response(status: 200, json: ["text": result.text])
    } catch {
        try? FileManager.default.removeItem(at: url)
        log("transcription failed: \(error)")
        return Response(status: 500, json: ["error": "\(error)"])
    }
}

final class Connection: @unchecked Sendable {
    private let connection: NWConnection
    private var buffer = Data()

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        connection.start(queue: .global(qos: .userInitiated))
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] data, _, complete, error in
            if let data { buffer.append(data) }
            if let request = completeRequest() {
                Task {
                    let response = await handle(request)
                    connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                        self.connection.cancel()
                    })
                }
            } else if complete || error != nil {
                connection.cancel()
            } else {
                receive()
            }
        }
    }

    private func completeRequest() -> Request? {
        guard let split = buffer.range(of: headerTerminator),
              let head = parseHead(buffer[buffer.startIndex..<split.lowerBound]) else { return nil }
        let length = Int(head.headers["content-length"] ?? "0") ?? 0
        let bodyStart = split.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return nil }
        return Request(method: head.method, path: head.path, headers: head.headers,
                       body: Data(buffer[bodyStart..<(bodyStart + length)]))
    }
}

// MARK: - Main

// `ParakeetServer --clean "<text>"` prints the cleaned transcript, for testing the artifact fixes.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--clean" {
    print(cleanTranscript(CommandLine.arguments[2]))
    exit(0)
}

let parameters = NWParameters.tcp
parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
parameters.allowLocalEndpointReuse = true
let listener = try NWListener(using: parameters)
listener.newConnectionHandler = { Connection($0).start() }
listener.stateUpdateHandler = { state in
    switch state {
    case .ready: log("listening on http://127.0.0.1:\(port)/v1 (Neural Engine: \(Model.allCases.map(\.rawValue).joined(separator: ", ")))")
    case .failed(let error): log("listener failed: \(error)"); exit(1)
    default: break
    }
}
listener.start(queue: .global(qos: .userInitiated))

Task.detached {
    while true {
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        await engine.unloadIfIdle()
    }
}

dispatchMain()
