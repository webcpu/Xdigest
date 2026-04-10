import Foundation
import XdigestCore

/// Matches bird CLI's --json-full output. The `_raw` field contains
/// the full Twitter API v2 payload used for normalization.
public struct RawBirdTweet: Codable, Sendable, Equatable {
    public let id: String
    public let text: String
    public let createdAt: String
    public let author: RawAuthor
    public let authorId: String
    public let replyCount: Int?
    public let retweetCount: Int?
    public let likeCount: Int?
    public let conversationId: String?
    public let media: [RawMedia]?
    private let _quotedTweet: Box<RawBirdTweet>?
    public let _raw: JSONValue?

    public var quotedTweet: RawBirdTweet? { _quotedTweet?.value }

    enum CodingKeys: String, CodingKey {
        case id, text, createdAt, author, authorId
        case replyCount, retweetCount, likeCount, conversationId
        case media, _raw
        case _quotedTweet = "quotedTweet"
    }
}

public struct RawAuthor: Codable, Sendable, Equatable {
    public let username: String
    public let name: String
}

public struct RawMedia: Codable, Sendable, Equatable {
    public let type: String
    public let url: String
    public let width: Int?
    public let height: Int?
    public let previewUrl: String?
    public let videoUrl: String?
    public let durationMs: Int?
}

/// Generic JSON value for navigating the deeply nested _raw payload.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    /// Navigate nested JSON by key path: raw["legacy"]["full_text"]
    public subscript(key: String) -> JSONValue? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }

    public var stringValue: String? {
        guard case .string(let v) = self else { return nil }
        return v
    }

    public var objectValue: [String: JSONValue]? {
        guard case .object(let v) = self else { return nil }
        return v
    }

    public var arrayValue: [JSONValue]? {
        guard case .array(let v) = self else { return nil }
        return v
    }
}
