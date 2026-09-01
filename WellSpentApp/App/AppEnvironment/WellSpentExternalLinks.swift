import Foundation

enum WellSpentExternalLinks {
    static let privacyPolicy = url(forInfoDictionaryKey: "WellSpentPrivacyPolicyURL")
    static let sourceCode = url(forInfoDictionaryKey: "WellSpentSourceCodeURL")
    static let support = url(forInfoDictionaryKey: "WellSpentSupportURL")

    static var versionDescription: String {
        let version =
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case (.some(let version), .some(let build)):
            return "\(version) (\(build))"
        case (.some(let version), .none):
            return version
        case (.none, .some(let build)):
            return build
        case (.none, .none):
            return "Unknown"
        }
    }

    private static func url(forInfoDictionaryKey key: String) -> URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            let url = URL(string: value),
            url.scheme == "https"
        else { return nil }
        return url
    }
}
