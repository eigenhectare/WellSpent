import Foundation

/// Handoff carries only an opaque conflict identity, never billing content.
public enum WatchReviewLink {
    public static let activityType = "com.drewreilly.wellspent.review"
    public static let conflictIDKey = "conflictID"

    public static func url(conflictID: UUID) -> URL {
        URL(string: "wellspent://review/\(conflictID.uuidString)")!
    }

    public static func conflictID(from url: URL) -> UUID? {
        guard url.scheme == "wellspent", url.host == "review",
            url.pathComponents.count == 2, url.query == nil, url.fragment == nil
        else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
