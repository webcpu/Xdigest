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

/// Thread-safe mutable digest state.
public final class DigestState: Sendable {
    private struct State {
        var digest: Digest
        var mtime: TimeInterval
        var lastSeenPostId: String
    }

    private let state: Mutex<State>
    let onGenerate: GenerateHandler?
    let onPositionChange: PositionHandler?

    init(
        digest: Digest,
        lastSeenPostId: String = "",
        onGenerate: GenerateHandler? = nil,
        onPositionChange: PositionHandler? = nil
    ) {
        self.state = Mutex(State(
            digest: digest,
            mtime: Date().timeIntervalSince1970,
            lastSeenPostId: lastSeenPostId
        ))
        self.onGenerate = onGenerate
        self.onPositionChange = onPositionChange
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

    func updatePosition(_ postId: String) {
        state.withLock { $0.lastSeenPostId = postId }
        onPositionChange?(postId)
    }

    func update(_ digest: Digest) {
        state.withLock {
            $0.digest = digest
            $0.mtime = Date().timeIntervalSince1970
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
    onPositionChange: PositionHandler? = nil
) async throws -> ServerHandle {
    guard port > 0, port <= 65535, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
        throw XdigestError.serverStartFailed(port: port, reason: "port must be 1-65535")
    }

    let state = DigestState(
        digest: digest,
        lastSeenPostId: lastSeenPostId,
        onGenerate: onGenerate,
        onPositionChange: onPositionChange
    )
    let params = NWParameters.tcp
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

// MARK: - Connection Handling

private func handleConnection(_ connection: NWConnection, state: DigestState) {
    connection.start(queue: .global(qos: .userInitiated))

    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
        guard let data = data, error == nil else {
            connection.cancel()
            return
        }

        let request = String(data: data, encoding: .utf8) ?? ""
        let responseData = routeRequest(request, state: state)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
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

    let method = parseRequestMethod(rawRequest)
    let response: String
    switch (method, path) {
    case (_, "/"), (_, "/index.html"):
        response = handleRoot(state: state)
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
    let digest = state.digest
    let digestHTML = renderDigest(digest)
    let page = readerPage(digestHTML: digestHTML, initialPosition: state.lastSeenPostId)
    return httpResponse(status: 200, contentType: "text/html; charset=utf-8", body: page)
}

private func handleApiDigest(state: DigestState) -> String {
    let digest = state.digest
    let html = renderDigest(digest)
    return httpResponse(status: 200, contentType: "text/html; charset=utf-8", body: html)
}

private func handleApiMtime(state: DigestState) -> String {
    let digest = state.digest
    let mtime = state.mtime
    let postCount = digest.sections.reduce(0) { $0 + $1.posts.count }
    let position = state.lastSeenPostId
    let json = """
    {"mtime":\(mtime),"postCount":\(postCount),"lastSeenPostId":"\(escapeJSON(position))"}
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
    state.updatePosition(postId)
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
