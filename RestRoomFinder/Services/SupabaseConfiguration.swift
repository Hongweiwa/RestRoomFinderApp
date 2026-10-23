import Foundation

/// Client-safe values supplied by xcconfig through Info.plist, never by a SwiftUI view.
struct SupabaseConfiguration {
    let url: URL
    let publishableKey: String

    enum ConfigurationError: LocalizedError {
        case missingURL, invalidURL, missingKey, invalidKey
        var errorDescription: String? {
            switch self {
            case .missingURL: return "Set SUPABASE_URL in Configuration/Supabase.local.xcconfig."
            case .invalidURL: return "SUPABASE_URL must be an HTTPS project URL without a path, credentials or query. Use https:/$()/ in xcconfig."
            case .missingKey: return "Set SUPABASE_PUBLISHABLE_KEY in Configuration/Supabase.local.xcconfig."
            case .invalidKey: return "Use a Supabase sb_publishable_ key. Secret, service-role and legacy JWT keys are not accepted."
            }
        }
    }

    init(values: [String: Any]) throws {
        let rawURL = (values["SupabaseURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (values["SupabasePublishableKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty, !rawURL.contains("$("), !rawURL.contains("YOUR_") else { throw ConfigurationError.missingURL }
        guard let components = URLComponents(string: rawURL), components.scheme == "https",
              let host = components.host, !host.isEmpty, !host.contains(where: { $0.isWhitespace }),
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/", let url = components.url else {
            throw ConfigurationError.invalidURL
        }
        guard !key.isEmpty, !key.contains("$("), !key.contains("YOUR_") else { throw ConfigurationError.missingKey }
        let prefix = "sb_publishable_"
        guard key.hasPrefix(prefix), key.count > prefix.count,
              key.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0) }) else {
            throw ConfigurationError.invalidKey
        }
        self.url = url
        publishableKey = key
    }

    static func load(bundle: Bundle = .main) throws -> SupabaseConfiguration {
        try SupabaseConfiguration(values: bundle.infoDictionary ?? [:])
    }
}
