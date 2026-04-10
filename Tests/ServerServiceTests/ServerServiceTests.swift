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

// MARK: - Helpers

private struct MtimeResponse: Codable {
    let mtime: Double
    let postCount: Int
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
