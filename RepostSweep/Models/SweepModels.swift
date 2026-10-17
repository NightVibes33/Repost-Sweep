import Foundation

struct TikTokAccount: Equatable, Codable {
    var uniqueId: String
    var nickname: String
    var secUid: String
    var avatarURL: String
    var followerCount: Int
    var followingCount: Int

    enum CodingKeys: String, CodingKey {
        case uniqueId, nickname, secUid, avatarURL, followerCount, followingCount
    }

    init(
        uniqueId: String,
        nickname: String,
        secUid: String,
        avatarURL: String,
        followerCount: Int = 0,
        followingCount: Int = 0
    ) {
        self.uniqueId = uniqueId
        self.nickname = nickname
        self.secUid = secUid
        self.avatarURL = avatarURL
        self.followerCount = followerCount
        self.followingCount = followingCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uniqueId = try container.decodeIfPresent(String.self, forKey: .uniqueId) ?? ""
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        secUid = try container.decodeIfPresent(String.self, forKey: .secUid) ?? ""
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL) ?? ""
        followerCount = try container.decodeIfPresent(Int.self, forKey: .followerCount) ?? 0
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
    }

    var statsLine: String? {
        guard followerCount > 0 || followingCount > 0 else { return nil }
        return "\(Self.compact(followerCount)) followers · \(Self.compact(followingCount)) following"
    }

    private static func compact(_ value: Int) -> String {
        let number = Double(value)
        if number >= 1_000_000 {
            return trim(number / 1_000_000) + "M"
        }
        if number >= 1_000 {
            return trim(number / 1_000) + "K"
        }
        return "\(value)"
    }

    private static func trim(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        if text.hasSuffix(".0") {
            return String(text.dropLast(2))
        }
        return text
    }
}

struct RepostItem: Identifiable, Equatable, Codable {
    var id: String
    var author: String
    var caption: String
    var coverURL: String

    enum CodingKeys: String, CodingKey {
        case id, author, caption, coverURL
    }

    init(id: String, author: String, caption: String, coverURL: String) {
        self.id = id
        self.author = author
        self.caption = caption
        self.coverURL = coverURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        coverURL = try container.decodeIfPresent(String.self, forKey: .coverURL) ?? ""
    }

    var titleLine: String {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if !author.isEmpty {
            return "@\(author)"
        }
        return "Repost \(id)"
    }
}

struct BridgeEnvelope: Decodable {
    var ok: Bool
    var code: String
    var message: String
    var items: [RepostItem]
    var cursor: String
    var hasMore: Bool
    var account: TikTokAccount?
    var dataURL: String

    enum CodingKeys: String, CodingKey {
        case ok, code, message, items, cursor, hasMore, account, dataURL
    }

    init(
        ok: Bool,
        code: String,
        message: String,
        items: [RepostItem],
        cursor: String,
        hasMore: Bool,
        account: TikTokAccount?,
        dataURL: String
    ) {
        self.ok = ok
        self.code = code
        self.message = message
        self.items = items
        self.cursor = cursor
        self.hasMore = hasMore
        self.account = account
        self.dataURL = dataURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        items = try container.decodeIfPresent([RepostItem].self, forKey: .items) ?? []
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor) ?? ""
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        account = try container.decodeIfPresent(TikTokAccount.self, forKey: .account)
        dataURL = try container.decodeIfPresent(String.self, forKey: .dataURL) ?? ""
    }

    static func skipped() -> BridgeEnvelope {
        BridgeEnvelope(
            ok: false,
            code: "SKIPPED",
            message: "",
            items: [],
            cursor: "",
            hasMore: false,
            account: nil,
            dataURL: ""
        )
    }
}

enum RemovalAttempt: Equatable {
    case removed
    case rateLimited
    case notLoggedIn
    case failed(String)
}

enum SessionError: Error {
    case emptyResult
    case badPayload
}

struct SweepNotice: Equatable {
    var title: String
    var message: String
    var debugHint: String?
    var suggestLogin: Bool = false
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var itemId: String
    var title: String
    var author: String
    var date: Date
    var removed: Bool
    var detail: String
}
