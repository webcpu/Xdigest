import Foundation

public final class Box<T: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let value: T

    public init(_ value: T) {
        self.value = value
    }

    public static func == (lhs: Box<T>, rhs: Box<T>) -> Bool {
        lhs.value == rhs.value
    }

    public init(from decoder: Decoder) throws {
        self.value = try T(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

public struct Author: Codable, Sendable, Equatable {
    public let username: String
    public let name: String

    public init(username: String, name: String) {
        self.username = username
        self.name = name
    }
}

public enum MediaType: String, Codable, Sendable {
    case photo
    case video
    case animatedGif = "animated_gif"
}

public struct Media: Codable, Sendable, Equatable {
    public let type: MediaType
    public let url: String
    public let width: Int
    public let height: Int
    public let previewUrl: String?
    public let videoUrl: String?
    public let durationMs: Int?

    public init(
        type: MediaType,
        url: String,
        width: Int,
        height: Int,
        previewUrl: String? = nil,
        videoUrl: String? = nil,
        durationMs: Int? = nil
    ) {
        self.type = type
        self.url = url
        self.width = width
        self.height = height
        self.previewUrl = previewUrl
        self.videoUrl = videoUrl
        self.durationMs = durationMs
    }
}

public struct Repost: Codable, Sendable, Equatable {
    public let retweeterHandle: String
    public let retweeterName: String
    public let originalHandle: String
    public let originalName: String
    public let originalId: String
    public let originalAvatarUrl: String?

    public init(
        retweeterHandle: String,
        retweeterName: String,
        originalHandle: String,
        originalName: String,
        originalId: String,
        originalAvatarUrl: String? = nil
    ) {
        self.retweeterHandle = retweeterHandle
        self.retweeterName = retweeterName
        self.originalHandle = originalHandle
        self.originalName = originalName
        self.originalId = originalId
        self.originalAvatarUrl = originalAvatarUrl
    }
}

public struct Tweet: Codable, Sendable, Equatable {
    public let id: String
    public let text: String
    public let createdAt: String
    public let author: Author
    public let authorId: String
    public let replyCount: Int?
    public let retweetCount: Int?
    public let likeCount: Int?
    public let conversationId: String?
    public let media: [Media]?
    public let avatarUrl: String?
    public let repost: Repost?
    /// Maps t.co URLs to their expanded URLs (for article links).
    public let urlReplacements: [String: String]?
    /// t.co URLs to strip from display text (media links already rendered separately).
    public let urlStrip: [String]?
    private let _quotedTweet: Box<Tweet>?

    public var quotedTweet: Tweet? { _quotedTweet?.value }

    public init(
        id: String,
        text: String,
        createdAt: String,
        author: Author,
        authorId: String,
        replyCount: Int? = nil,
        retweetCount: Int? = nil,
        likeCount: Int? = nil,
        conversationId: String? = nil,
        media: [Media]? = nil,
        avatarUrl: String? = nil,
        repost: Repost? = nil,
        urlReplacements: [String: String]? = nil,
        urlStrip: [String]? = nil,
        quotedTweet: Tweet? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.author = author
        self.authorId = authorId
        self.replyCount = replyCount
        self.retweetCount = retweetCount
        self.likeCount = likeCount
        self.conversationId = conversationId
        self.media = media
        self.avatarUrl = avatarUrl
        self.repost = repost
        self.urlReplacements = urlReplacements
        self.urlStrip = urlStrip
        self._quotedTweet = quotedTweet.map(Box.init)
    }

    enum CodingKeys: String, CodingKey {
        case id, text, createdAt, author, authorId
        case replyCount, retweetCount, likeCount, conversationId, media
        case avatarUrl, repost, urlReplacements, urlStrip
        case _quotedTweet = "quotedTweet"
    }
}

public typealias Bookmark = Tweet

public struct ScoredPost: Codable, Sendable, Equatable {
    public let tweet: Tweet
    public let score: Double
    public let reason: String
    public let tags: [String]

    public init(tweet: Tweet, score: Double, reason: String, tags: [String]) {
        self.tweet = tweet
        self.score = score
        self.reason = reason
        self.tags = tags
    }
}

public struct DigestSection: Codable, Sendable, Equatable {
    public let timestamp: String
    public let posts: [ScoredPost]

    public init(timestamp: String, posts: [ScoredPost]) {
        self.timestamp = timestamp
        self.posts = posts
    }
}

public struct Digest: Codable, Sendable, Equatable {
    public let date: String
    public let sections: [DigestSection]

    public init(date: String, sections: [DigestSection]) {
        self.date = date
        self.sections = sections
    }
}
