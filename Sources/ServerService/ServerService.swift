import Foundation
import Network
import Synchronization
import XdigestCore

/// Handle to a running server. Opaque to callers.
public final class ServerHandle: Sendable {
    let listener: NWListener
    let state: DigestState

    init(listener: NWListener, state: DigestState) {
        self.listener = listener
        self.state = state
    }
}

/// Callback for the generate endpoint. Returns the number of new posts, or an error message.
/// Blocks until generation completes.
public typealias GenerateHandler = @Sendable () -> GenerateResult

public struct GenerateResult: Sendable {
    public let picks: Int
    public let error: String?

    public init(picks: Int, error: String? = nil) {
        self.picks = picks
        self.error = error
    }
}

/// Called when position changes, so the app can persist it.
public typealias PositionHandler = @Sendable (String) -> Void

/// Called when the digest changes, so the app can persist it.
public typealias DigestChangeHandler = @Sendable (Digest) -> Void

/// Thread-safe mutable digest state.
///
/// Uses a monotonic `version` number that increments on every mutation.
/// Clients apply updates strictly in version order, which makes the server
/// the single writer and eliminates echo-loop workarounds on the client.
public final class DigestState: @unchecked Sendable {
    private struct State {
        var digest: Digest
        var mtime: TimeInterval
        var lastSeenPostId: String
        /// Fraction (0.0 .. 1.0) from the top of lastSeenPostId where the
        /// reading anchor sits. Lets the receiver place the same scroll
        /// offset within the same post even though the post has different
        /// height on different devices.
        var lastSeenFraction: Double
        var version: Int
    }

    private let state: Mutex<State>
    private let sseClients = Mutex<[NWConnection]>([])
    /// Random ID for this server instance. Browsers compare it to the one
    /// they loaded and reload themselves if it changes -- no manual refresh
    /// after restart.
    public let instanceId: String = UUID().uuidString
    /// All mutations + broadcasts run on this serial queue. This makes
    /// "commit + broadcast" atomic with respect to other writers: no two
    /// broadcasts can interleave on the wire, so SSE clients always see
    /// versions in strictly monotonic order. tmux gets this for free by
    /// having a single libevent loop; we emulate it with a serial queue.
    private let writeQueue = DispatchQueue(label: "com.xdigest.digest-state-writes")
    let onGenerate: GenerateHandler?
    let onPositionChange: PositionHandler?
    let onDigestChange: DigestChangeHandler?

    init(
        digest: Digest,
        lastSeenPostId: String = "",
        lastSeenFraction: Double = 0,
        onGenerate: GenerateHandler? = nil,
        onPositionChange: PositionHandler? = nil,
        onDigestChange: DigestChangeHandler? = nil
    ) {
        self.state = Mutex(State(
            digest: digest,
            mtime: Date().timeIntervalSince1970,
            lastSeenPostId: lastSeenPostId,
            lastSeenFraction: lastSeenFraction,
            version: 0
        ))
        self.onGenerate = onGenerate
        self.onPositionChange = onPositionChange
        self.onDigestChange = onDigestChange
    }

    var digest: Digest {
        state.withLock { $0.digest }
    }

    var mtime: TimeInterval {
        state.withLock { $0.mtime }
    }

    var lastSeenPostId: String {
        state.withLock { $0.lastSeenPostId }
    }

    var lastSeenFraction: Double {
        state.withLock { $0.lastSeenFraction }
    }

    var version: Int {
        state.withLock { $0.version }
    }

    /// Atomic snapshot of the publicly observable state.
    /// Use this for anything that needs multiple fields at once -- reading
    /// `digest`, `mtime`, `version`, `lastSeenPostId` via separate accessors
    /// can interleave with a concurrent update and return inconsistent data.
    public struct Snapshot: Sendable {
        public let digest: Digest
        public let mtime: TimeInterval
        public let lastSeenPostId: String
        public let lastSeenFraction: Double
        public let version: Int
    }

    func snapshot() -> Snapshot {
        state.withLock {
            Snapshot(
                digest: $0.digest,
                mtime: $0.mtime,
                lastSeenPostId: $0.lastSeenPostId,
                lastSeenFraction: $0.lastSeenFraction,
                version: $0.version
            )
        }
    }

    func addSseClient(_ connection: NWConnection) {
        sseClients.withLock { $0.append(connection) }
    }

    func removeSseClient(_ connection: NWConnection) {
        sseClients.withLock { clients in
            clients.removeAll { $0 === connection }
        }
    }

    /// Sends an SSE event to all connected clients.
    func broadcast(event: String) {
        let data = Data("data: \(event)\n\n".utf8)
        let snapshot = sseClients.withLock { Array($0) }
        for client in snapshot {
            client.send(content: data, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.removeSseClient(client)
                    client.cancel()
                }
            })
        }
    }

    func updatePosition(_ postId: String, fraction: Double) {
        writeQueue.sync {
            var changed = false
            state.withLock {
                // Coalesce tiny fraction changes (browser fires many scroll events).
                let isSamePost = $0.lastSeenPostId == postId
                let isSameFraction = abs($0.lastSeenFraction - fraction) < 0.005
                guard !(isSamePost && isSameFraction) else { return }
                $0.lastSeenPostId = postId
                $0.lastSeenFraction = fraction
                $0.version += 1
                changed = true
            }
            guard changed else { return }
            onPositionChange?(postId)
            broadcastState()
        }
    }

    func broadcastState() {
        let snapshot = state.withLock { $0 }
        let postCount = snapshot.digest.sections.reduce(0) { $0 + $1.posts.count }
        let json = "{\"instanceId\":\"\(instanceId)\",\"version\":\(snapshot.version),\"mtime\":\(snapshot.mtime),\"postCount\":\(postCount),\"lastSeenPostId\":\"\(snapshot.lastSeenPostId)\",\"lastSeenFraction\":\(snapshot.lastSeenFraction)}"
        broadcast(event: json)
    }

    func update(_ digest: Digest) {
        writeQueue.sync {
            state.withLock {
                $0.digest = digest
                $0.mtime = Date().timeIntervalSince1970
                $0.version += 1
            }
            onDigestChange?(digest)
            broadcastState()
        }
    }
}

// MARK: - Public API

/// Starts an HTTP server on the given port, serving the provided digest.
/// Returns a handle used to stop the server or update its digest.
public func startServer(
    port: Int,
    digest: Digest,
    lastSeenPostId: String = "",
    onGenerate: GenerateHandler? = nil,
    onPositionChange: PositionHandler? = nil,
    onDigestChange: DigestChangeHandler? = nil
) async throws -> ServerHandle {
    guard port > 0, port <= 65535, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
        throw XdigestError.serverStartFailed(port: port, reason: "port must be 1-65535")
    }

    let state = DigestState(
        digest: digest,
        lastSeenPostId: lastSeenPostId,
        onGenerate: onGenerate,
        onPositionChange: onPositionChange,
        onDigestChange: onDigestChange
    )
    // Force IPv4 binding. Without this override, Network framework on
    // macOS creates an IPv6-only socket (IPV6_V6ONLY=1 by default), so
    // IPv4 clients like Tailscale (100.x.x.x CGNAT) get stuck in
    // SYN_SENT and time out. localhost (::1) and mDNS over IPv6 still
    // work in that degenerate state, which is why the bug hides on the
    // local machine until you try to reach the reader from another
    // device over IPv4.
    //
    // IPv4-only is fine for every access path the app actually uses:
    // - localhost: curl/Safari happy-eyeballs 127.0.0.1 when ::1 fails
    // - mDNS (`<host>.local`): resolves to BOTH IPv4 and IPv6, client
    //   picks IPv4 when the server is IPv4-only
    // - LAN IP (e.g. 10.0.x.x): native IPv4
    // - Tailscale (100.x.x.x): native IPv4 CGNAT
    //
    // We'd prefer dual-stack, but Network framework doesn't expose
    // `IPV6_V6ONLY=0` on listeners, and running two parallel listeners
    // (one per family) fails because setting `requiredLocalEndpoint`
    // in either configuration causes the second bind to fail with
    // "already in use". IPv4-only is the only knob that produces a
    // working Tailscale path.
    let params = NWParameters.tcp
    if let ipOpts = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
        ipOpts.version = .v4
    }
    let listener: NWListener
    do {
        listener = try NWListener(using: params, on: nwPort)
    } catch {
        throw XdigestError.serverStartFailed(port: port, reason: error.localizedDescription)
    }

    let handle = ServerHandle(listener: listener, state: state)

    listener.newConnectionHandler = { connection in
        handleConnection(connection, state: state)
    }

    let once = OnceFlag()

    return try await withCheckedThrowingContinuation { continuation in
        listener.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                guard once.tryFire() else { return }
                continuation.resume(returning: handle)
            case .failed(let error):
                guard once.tryFire() else { return }
                let reason = error.localizedDescription
                if reason.contains("Address already in use") || reason.contains("EADDRINUSE") {
                    continuation.resume(throwing: XdigestError.serverPortInUse(port: port))
                } else {
                    continuation.resume(throwing: XdigestError.serverStartFailed(port: port, reason: reason))
                }
            default:
                break
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }
}

/// Stops the server.
public func stopServer(_ handle: ServerHandle) {
    handle.listener.cancel()
}

/// Updates the digest served by the running server.
public func updateDigest(_ handle: ServerHandle, digest: Digest) {
    handle.state.update(digest)
}

/// Returns the current digest from the running server (atomic snapshot).
public func currentDigest(_ handle: ServerHandle) -> Digest {
    handle.state.snapshot().digest
}

// MARK: - Connection Handling

private func handleConnection(_ connection: NWConnection, state: DigestState) {
    connection.start(queue: .global(qos: .userInitiated))

    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
        guard let data = data, error == nil else {
            connection.cancel()
            return
        }

        let request = String(data: data, encoding: .utf8) ?? ""
        let path = parseRequestPath(request)

        // SSE: keep the connection open and stream events
        if path == "/api/events" {
            startSseStream(connection: connection, state: state)
            return
        }

        let responseData = routeRequest(request, state: state)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// Sends SSE response headers and registers the connection for broadcasts.
private func startSseStream(connection: NWConnection, state: DigestState) {
    let headers = "HTTP/1.1 200 OK\r\n"
        + "Content-Type: text/event-stream\r\n"
        + "Cache-Control: no-cache\r\n"
        + "Connection: keep-alive\r\n"
        + "Access-Control-Allow-Origin: *\r\n"
        + "\r\n"

    let snap = state.snapshot()
    let postCount = snap.digest.sections.reduce(0) { $0 + $1.posts.count }
    let initialEvent = "data: {\"instanceId\":\"\(state.instanceId)\",\"version\":\(snap.version),\"mtime\":\(snap.mtime),\"postCount\":\(postCount),\"lastSeenPostId\":\"\(snap.lastSeenPostId)\",\"lastSeenFraction\":\(snap.lastSeenFraction)}\n\n"

    connection.send(content: Data((headers + initialEvent).utf8), completion: .contentProcessed { error in
        if error != nil {
            connection.cancel()
            return
        }
        state.addSseClient(connection)

        // Detect disconnect
        connection.stateUpdateHandler = { newState in
            switch newState {
            case .failed, .cancelled:
                state.removeSseClient(connection)
            default:
                break
            }
        }
    })
}

// MARK: - Routing

/// Parses the HTTP request line and routes to the appropriate handler.
func routeRequest(_ rawRequest: String, state: DigestState) -> Data {
    let path = parseRequestPath(rawRequest)
    let rangeHeader = parseRangeHeader(rawRequest)

    if path.hasPrefix("/proxy?url=") {
        let encoded = String(path.dropFirst("/proxy?url=".count))
        let videoUrl = encoded.removingPercentEncoding ?? encoded
        return handleProxy(url: videoUrl, range: rangeHeader)
    }

    if path == "/icon-180.png" {
        return httpBinaryResponse(status: 200, contentType: "image/png", body: touchIconData)
    }
    if path == "/xd-icon.png" {
        return httpBinaryResponse(status: 200, contentType: "image/png", body: faviconData)
    }

    let method = parseRequestMethod(rawRequest)
    let response: String
    switch (method, path) {
    case (_, "/"), (_, "/index.html"):
        response = handleRoot(state: state)
    case (_, "/manifest.json"):
        response = handleManifest()
    case (_, "/api/digest"):
        response = handleApiDigest(state: state)
    case (_, "/api/mtime"):
        response = handleApiMtime(state: state)
    case (_, "/api/generate"):
        response = handleApiGenerate(state: state)
    case ("GET", "/api/position"):
        response = handleGetPosition(state: state)
    case ("POST", "/api/position"):
        response = handlePostPosition(rawRequest: rawRequest, state: state)
    default:
        response = httpResponse(status: 404, contentType: "text/plain", body: "Not Found")
    }
    return Data(response.utf8)
}

/// Extracts the HTTP method from the first line of a request.
func parseRequestMethod(_ rawRequest: String) -> String {
    let firstLine = rawRequest.prefix(while: { $0 != "\r" && $0 != "\n" })
    let parts = firstLine.split(separator: " ")
    guard parts.count >= 1 else { return "GET" }
    return String(parts[0])
}

/// Extracts the body from an HTTP request (everything after the blank line).
private func parseRequestBody(_ rawRequest: String) -> String {
    guard let bodyRange = rawRequest.range(of: "\r\n\r\n") else { return "" }
    return String(rawRequest[bodyRange.upperBound...])
}

/// Extracts the path from the first line of an HTTP request.
/// Example: "GET /api/mtime HTTP/1.1\r\n..." -> "/api/mtime"
func parseRequestPath(_ rawRequest: String) -> String {
    let firstLine = rawRequest.prefix(while: { $0 != "\r" && $0 != "\n" })
    let parts = firstLine.split(separator: " ")
    guard parts.count >= 2 else { return "/" }
    return String(parts[1])
}

// MARK: - Route Handlers

private func handleRoot(state: DigestState) -> String {
    let snap = state.snapshot()
    let digestHTML = renderDigest(snap.digest)
    let page = readerPage(
        digestHTML: digestHTML,
        initialPosition: snap.lastSeenPostId,
        initialFraction: snap.lastSeenFraction,
        initialVersion: snap.version,
        instanceId: state.instanceId
    )
    return httpResponse(status: 200, contentType: "text/html; charset=utf-8", body: page)
}

private func handleApiDigest(state: DigestState) -> String {
    let digest = state.snapshot().digest
    let html = renderDigest(digest)
    return httpResponse(status: 200, contentType: "text/html; charset=utf-8", body: html)
}

private func handleApiMtime(state: DigestState) -> String {
    let snap = state.snapshot()
    let postCount = snap.digest.sections.reduce(0) { $0 + $1.posts.count }
    let json = """
    {"instanceId":"\(state.instanceId)","version":\(snap.version),"mtime":\(snap.mtime),"postCount":\(postCount),"lastSeenPostId":"\(escapeJSON(snap.lastSeenPostId))","lastSeenFraction":\(snap.lastSeenFraction)}
    """
    return httpResponse(status: 200, contentType: "application/json", body: json)
}

private func handleGetPosition(state: DigestState) -> String {
    let position = state.lastSeenPostId
    let json = "{\"lastSeenPostId\":\"\(escapeJSON(position))\"}"
    return httpResponse(status: 200, contentType: "application/json", body: json)
}

private func handlePostPosition(rawRequest: String, state: DigestState) -> String {
    let body = parseRequestBody(rawRequest)
    guard let data = body.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let postId = obj["lastSeenPostId"] as? String
    else {
        return httpResponse(status: 400, contentType: "application/json",
                            body: "{\"error\":\"missing lastSeenPostId\"}")
    }
    let fraction = (obj["lastSeenFraction"] as? Double) ?? 0
    state.updatePosition(postId, fraction: fraction)
    return httpResponse(status: 200, contentType: "application/json", body: "{\"ok\":true}")
}

private func handleApiGenerate(state: DigestState) -> String {
    guard let onGenerate = state.onGenerate else {
        return httpResponse(status: 501, contentType: "application/json",
                          body: "{\"error\":\"generate not configured\"}")
    }
    let result = onGenerate()
    if let error = result.error {
        return httpResponse(status: 500, contentType: "application/json",
                          body: "{\"error\":\"\(escapeJSON(error))\"}")
    }
    return httpResponse(status: 200, contentType: "application/json",
                       body: "{\"picks\":\(result.picks)}")
}

private func escapeJSON(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
}

// MARK: - Video Proxy

/// Proxies a video URL from twimg.com, supporting Range requests.
private func handleProxy(url: String, range: String?) -> Data {
    guard url.contains("twimg.com") else {
        return Data(httpResponse(status: 403, contentType: "text/plain", body: "Forbidden: only twimg.com allowed").utf8)
    }

    guard let videoUrl = URL(string: url) else {
        return Data(httpResponse(status: 400, contentType: "text/plain", body: "Bad URL").utf8)
    }

    var request = URLRequest(url: videoUrl)
    request.timeoutInterval = 30
    if let range {
        request.setValue(range, forHTTPHeaderField: "Range")
    }

    var responseData = Data()
    let semaphore = DispatchSemaphore(value: 0)
    var statusCode = 200
    var contentType = "video/mp4"
    var contentLength = 0
    var contentRange: String?

    let task = URLSession.shared.dataTask(with: request) { data, response, _ in
        if let http = response as? HTTPURLResponse {
            statusCode = http.statusCode
            contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "video/mp4"
            contentLength = Int(http.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
            contentRange = http.value(forHTTPHeaderField: "Content-Range")
        }
        if let data { responseData = data }
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()

    var headers = "HTTP/1.1 \(statusCode) \(httpStatusText(statusCode))\r\n"
        + "Content-Type: \(contentType)\r\n"
        + "Content-Length: \(responseData.count)\r\n"
        + "Access-Control-Allow-Origin: *\r\n"
        + "Accept-Ranges: bytes\r\n"
    if let contentRange {
        headers += "Content-Range: \(contentRange)\r\n"
    }
    headers += "Connection: close\r\n\r\n"

    return Data(headers.utf8) + responseData
}

/// Extracts the Range header value from a raw HTTP request.
func parseRangeHeader(_ rawRequest: String) -> String? {
    for line in rawRequest.split(separator: "\r\n") {
        let lower = line.lowercased()
        if lower.hasPrefix("range:") {
            return String(line.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces)
        }
    }
    return nil
}

// MARK: - HTTP Response Builder

/// Builds a raw HTTP/1.1 response string with headers and body.
private func handleManifest() -> String {
    let json = """
    {
      "id": "/",
      "name": "Xdigest",
      "short_name": "Xdigest",
      "start_url": "/",
      "scope": "/",
      "display": "standalone",
      "background_color": "#1a1a1a",
      "theme_color": "#1a1a1a",
      "icons": [
        {
          "src": "/icon-180.png",
          "sizes": "180x180",
          "type": "image/png"
        }
      ]
    }
    """
    return httpResponse(status: 200, contentType: "application/json", body: json)
}

func httpBinaryResponse(status: Int, contentType: String, body: Data) -> Data {
    let statusText = httpStatusText(status)
    let header = "HTTP/1.1 \(status) \(statusText)\r\n"
        + "Content-Type: \(contentType)\r\n"
        + "Content-Length: \(body.count)\r\n"
        + "Cache-Control: public, max-age=86400\r\n"
        + "Connection: close\r\n"
        + "\r\n"
    return Data(header.utf8) + body
}

func httpResponse(status: Int, contentType: String, body: String) -> String {
    let statusText = httpStatusText(status)
    let bodyData = Data(body.utf8)
    return "HTTP/1.1 \(status) \(statusText)\r\n"
        + "Content-Type: \(contentType)\r\n"
        + "Content-Length: \(bodyData.count)\r\n"
        + "Access-Control-Allow-Origin: *\r\n"
        + "Cache-Control: no-cache\r\n"
        + "Connection: close\r\n"
        + "\r\n"
        + body
}

private func httpStatusText(_ code: Int) -> String {
    switch code {
    case 200: "OK"
    case 404: "Not Found"
    case 500: "Internal Server Error"
    default: "Unknown"
    }
}
