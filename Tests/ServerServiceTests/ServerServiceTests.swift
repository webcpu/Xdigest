import Foundation
import Testing
@testable import ServerService
@testable import XdigestCore

// MARK: - Server Integration Tests (real HTTP)

/// Helper: find an available port by binding to 0 and reading the assigned port.
private func availablePort() throws -> Int {
    let socket = socket(AF_INET, SOCK_STREAM, 0)
    guard socket >= 0 else { throw XdigestError.serverStartFailed(port: 0, reason: "socket() failed") }
    defer { close(socket) }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0  // OS picks a free port
    addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

    let bindResult = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else { throw XdigestError.serverStartFailed(port: 0, reason: "bind() failed") }

    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(socket, $0, &len)
        }
    }
    guard nameResult == 0 else { throw XdigestError.serverStartFailed(port: 0, reason: "getsockname() failed") }

    return Int(UInt16(bigEndian: addr.sin_port))
}

/// Helper: make a GET request and return (statusCode, body).
private func httpGet(_ url: URL) async throws -> (Int, String) {
    let (data, response) = try await URLSession.shared.data(from: url)
    let httpResponse = response as! HTTPURLResponse
    let body = String(data: data, encoding: .utf8) ?? ""
    return (httpResponse.statusCode, body)
}

/// Helper: make a POST request and return (statusCode, body).
private func httpPost(_ url: URL, body: String? = nil) async throws -> (Int, String) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    if let body {
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    let httpResponse = response as! HTTPURLResponse
    let responseBody = String(data: data, encoding: .utf8) ?? ""
    return (httpResponse.statusCode, responseBody)
}

// MARK: - Root endpoint

@Test("GET / returns 200 with HTML page containing xdigest title")
func rootReturnsHTMLPage() async throws {
    let port = try availablePort()
    let digest = makeSampleDigest()
    let server = try await startServer(port: port, digest: digest)
    defer { stopServer(server) }

    let url = URL(string: "http://127.0.0.1:\(port)/")!
    let (status, body) = try await httpGet(url)

    #expect(status == 200)
    #expect(body.contains("<!DOCTYPE html>"))
    #expect(body.contains("xdigest"))
    // Should contain the digest content
    #expect(body.contains("Test post"))
}

@Test("GET / with empty digest returns page with no posts")
func rootEmptyDigest() async throws {
    let port = try availablePort()
    let emptyDigest = Digest(date: "2026-04-10", sections: [])
    let server = try await startServer(port: port, digest: emptyDigest)
    defer { stopServer(server) }

    let url = URL(string: "http://127.0.0.1:\(port)/")!
    let (status, body) = try await httpGet(url)

    #expect(status == 200)
    #expect(body.contains("<!DOCTYPE html>"))
}

// MARK: - /api/digest endpoint

@Test("GET /api/digest returns HTML fragment with post content")
func apiDigestReturnsFragment() async throws {
    let port = try availablePort()
    let digest = makeSampleDigest()
    let server = try await startServer(port: port, digest: digest)
    defer { stopServer(server) }

    let url = URL(string: "http://127.0.0.1:\(port)/api/digest")!
    let (status, body) = try await httpGet(url)

    #expect(status == 200)
    // Should be a fragment, not a full page
    #expect(!body.contains("<!DOCTYPE html>"))
    // Should contain the post
    #expect(body.contains("Test post"))
    #expect(body.contains("details"))
}

// MARK: - /api/mtime endpoint

@Test("GET /api/mtime returns JSON with mtime and postCount")
func apiMtimeReturnsJSON() async throws {
    let port = try availablePort()
    let digest = makeSampleDigest()
    let server = try await startServer(port: port, digest: digest)
    defer { stopServer(server) }

    let url = URL(string: "http://127.0.0.1:\(port)/api/mtime")!
    let (status, body) = try await httpGet(url)

    #expect(status == 200)

    let json = try JSONDecoder().decode(MtimeResponse.self, from: Data(body.utf8))
    #expect(json.mtime > 0)
    #expect(json.postCount == 1)
    #expect(json.canGenerate)
    #expect(json.autoPrefetchSectionKey.isEmpty)
}

// MARK: - 404

@Test("GET /unknown returns 404")
func unknownPathReturns404() async throws {
    let port = try availablePort()
    let digest = makeSampleDigest()
    let server = try await startServer(port: port, digest: digest)
    defer { stopServer(server) }

    let url = URL(string: "http://127.0.0.1:\(port)/unknown")!
    let (status, _) = try await httpGet(url)

    #expect(status == 404)
}

// MARK: - Digest update

@Test("Updating digest updates /api/digest and /api/mtime")
func updateDigestReflectedInAPI() async throws {
    let port = try availablePort()
    let digest1 = makeSampleDigest()
    let server = try await startServer(port: port, digest: digest1)
    defer { stopServer(server) }

    // First request
    let url = URL(string: "http://127.0.0.1:\(port)/api/mtime")!
    let (_, body1) = try await httpGet(url)
    let json1 = try JSONDecoder().decode(MtimeResponse.self, from: Data(body1.utf8))

    // Update digest
    let newPost = makeScored(id: "2", text: "New post")
    let digest2 = Digest(date: "2026-04-10", sections: [
        DigestSection(timestamp: "15:00", posts: [makeScored(id: "1", text: "Test post"), newPost])
    ])
    updateDigest(server, digest: digest2)

    // Second request
    let (_, body2) = try await httpGet(url)
    let json2 = try JSONDecoder().decode(MtimeResponse.self, from: Data(body2.utf8))

    #expect(json2.postCount == 2)
    #expect(json2.mtime > json1.mtime)

    // Verify /api/digest includes new post
    let digestURL = URL(string: "http://127.0.0.1:\(port)/api/digest")!
    let (_, digestBody) = try await httpGet(digestURL)
    #expect(digestBody.contains("New post"))
}

@Test("Auto-prefetch claims a section once and manual generate still works")
func autoPrefetchClaimsOnceAndManualGenerateStillWorks() async throws {
    let port = try availablePort()
    let counter = GenerateCounter()
    let digest = makeSampleDigest()
    let server = try await startServer(
        port: port,
        digest: digest,
        onGenerate: {
            counter.increment()
            return GenerateResult(picks: 1)
        }
    )
    defer { stopServer(server) }

    let url = URL(string: "http://127.0.0.1:\(port)/api/generate")!
    let sectionKey = "2026-04-10|14:00|1"

    let (status1, body1) = try await httpPost(
        url,
        body: #"{"mode":"prefetch","sectionKey":"2026-04-10|14:00|1"}"#
    )
    let response1 = try JSONDecoder().decode(GenerateResponse.self, from: Data(body1.utf8))
    #expect(status1 == 200)
    #expect(response1.picks == 1)
    #expect(response1.skipped == nil)

    let mtimeURL = URL(string: "http://127.0.0.1:\(port)/api/mtime")!
    let (_, mtimeBody) = try await httpGet(mtimeURL)
    let mtime = try JSONDecoder().decode(MtimeResponse.self, from: Data(mtimeBody.utf8))
    #expect(mtime.autoPrefetchSectionKey == sectionKey)

    let (status2, body2) = try await httpPost(
        url,
        body: #"{"mode":"prefetch","sectionKey":"2026-04-10|14:00|1"}"#
    )
    let response2 = try JSONDecoder().decode(GenerateResponse.self, from: Data(body2.utf8))
    #expect(status2 == 200)
    #expect(response2.picks == 0)
    #expect(response2.skipped == "already_claimed")

    let (status3, body3) = try await httpPost(url)
    let response3 = try JSONDecoder().decode(GenerateResponse.self, from: Data(body3.utf8))
    #expect(status3 == 200)
    #expect(response3.picks == 1)
    #expect(response3.skipped == nil)
    #expect(counter.current() == 2)
}

@Test("Auto-prefetch accepts a newly revealed top section")
func autoPrefetchAcceptsNewTopSection() async throws {
    let port = try availablePort()
    let counter = GenerateCounter()
    let digest = makeSampleDigest()
    let server = try await startServer(
        port: port,
        digest: digest,
        onGenerate: {
            counter.increment()
            return GenerateResult(picks: 1)
        }
    )
    defer { stopServer(server) }

    let url = URL(string: "http://127.0.0.1:\(port)/api/generate")!

    let (_, firstBody) = try await httpPost(
        url,
        body: #"{"mode":"prefetch","sectionKey":"2026-04-10|14:00|1"}"#
    )
    let firstResponse = try JSONDecoder().decode(GenerateResponse.self, from: Data(firstBody.utf8))
    #expect(firstResponse.picks == 1)

    let oldSection = DigestSection(timestamp: "14:00", posts: [makeScored(id: "1", text: "Test post")])
    let newSection = DigestSection(timestamp: "15:00", posts: [makeScored(id: "2", text: "Fresh post")])
    updateDigest(server, digest: Digest(date: "2026-04-10", sections: [newSection, oldSection]))

    let (_, secondBody) = try await httpPost(
        url,
        body: #"{"mode":"prefetch","sectionKey":"2026-04-10|15:00|2"}"#
    )
    let secondResponse = try JSONDecoder().decode(GenerateResponse.self, from: Data(secondBody.utf8))
    #expect(secondResponse.picks == 1)
    #expect(secondResponse.skipped == nil)
    #expect(counter.current() == 2)
}

@Test("Auto-prefetch can retry after zero picks")
func autoPrefetchRetriesAfterZeroPicks() async throws {
    let port = try availablePort()
    let sequence = GenerateSequence([
        GenerateResult(picks: 0),
        GenerateResult(picks: 1),
    ])
    let digest = makeSampleDigest()
    let server = try await startServer(
        port: port,
        digest: digest,
        onGenerate: { sequence.next() }
    )
    defer { stopServer(server) }

    let url = URL(string: "http://127.0.0.1:\(port)/api/generate")!
    let body = #"{"mode":"prefetch","sectionKey":"2026-04-10|14:00|1"}"#

    let (_, firstBody) = try await httpPost(url, body: body)
    let firstResponse = try JSONDecoder().decode(GenerateResponse.self, from: Data(firstBody.utf8))
    #expect(firstResponse.picks == 0)
    #expect(firstResponse.skipped == nil)

    let mtimeURL = URL(string: "http://127.0.0.1:\(port)/api/mtime")!
    let (_, mtimeBody) = try await httpGet(mtimeURL)
    let mtime = try JSONDecoder().decode(MtimeResponse.self, from: Data(mtimeBody.utf8))
    #expect(mtime.autoPrefetchSectionKey.isEmpty)

    let (_, secondBody) = try await httpPost(url, body: body)
    let secondResponse = try JSONDecoder().decode(GenerateResponse.self, from: Data(secondBody.utf8))
    #expect(secondResponse.picks == 1)
    #expect(secondResponse.skipped == nil)
    #expect(sequence.count() == 2)
}

@Test("Auto-prefetch can retry after generation error")
func autoPrefetchRetriesAfterError() async throws {
    let port = try availablePort()
    let sequence = GenerateSequence([
        GenerateResult(picks: 0, error: "boom"),
        GenerateResult(picks: 1),
    ])
    let digest = makeSampleDigest()
    let server = try await startServer(
        port: port,
        digest: digest,
        onGenerate: { sequence.next() }
    )
    defer { stopServer(server) }

    let url = URL(string: "http://127.0.0.1:\(port)/api/generate")!
    let body = #"{"mode":"prefetch","sectionKey":"2026-04-10|14:00|1"}"#

    let (status1, firstBody) = try await httpPost(url, body: body)
    #expect(status1 == 500)
    #expect(firstBody.contains("\"error\":\"boom\""))

    let mtimeURL = URL(string: "http://127.0.0.1:\(port)/api/mtime")!
    let (_, mtimeBody) = try await httpGet(mtimeURL)
    let mtime = try JSONDecoder().decode(MtimeResponse.self, from: Data(mtimeBody.utf8))
    #expect(mtime.autoPrefetchSectionKey.isEmpty)

    let (status2, secondBody) = try await httpPost(url, body: body)
    let secondResponse = try JSONDecoder().decode(GenerateResponse.self, from: Data(secondBody.utf8))
    #expect(status2 == 200)
    #expect(secondResponse.picks == 1)
    #expect(secondResponse.skipped == nil)
    #expect(sequence.count() == 2)
}

// MARK: - Helpers

private struct MtimeResponse: Codable {
    let mtime: Double
    let postCount: Int
    let canGenerate: Bool
    let autoPrefetchSectionKey: String
}

private struct GenerateResponse: Codable {
    let picks: Int
    let skipped: String?
}

private final class GenerateCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func current() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class GenerateSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [GenerateResult]
    private var calls = 0

    init(_ results: [GenerateResult]) {
        self.results = results
    }

    func next() -> GenerateResult {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        if !results.isEmpty {
            return results.removeFirst()
        }
        return GenerateResult(picks: 0, error: "no planned result")
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

private func makeSampleDigest() -> Digest {
    let post = makeScored(id: "1", text: "Test post")
    let section = DigestSection(timestamp: "14:00", posts: [post])
    return Digest(date: "2026-04-10", sections: [section])
}

private func makeScored(id: String, text: String) -> ScoredPost {
    let tweet = Tweet(
        id: id,
        text: text,
        createdAt: "Thu Apr 10 12:00:00 +0000 2026",
        author: Author(username: "testuser", name: "Test User"),
        authorId: "1"
    )
    return ScoredPost(tweet: tweet, score: 0.8, reason: "test", tags: ["test"])
}
