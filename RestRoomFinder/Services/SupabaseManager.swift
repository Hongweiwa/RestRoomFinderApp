import Supabase

/// A single lazy client for future services. Missing setup is an error, never an app crash.
@MainActor
final class SupabaseManager {
    static let shared = SupabaseManager()
    private let configuredClient: Result<SupabaseClient, Error>

    private init() {
        configuredClient = Result {
            let configuration = try SupabaseConfiguration.load()
            return SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.publishableKey,
                options: SupabaseClientOptions(auth: .init(
                    redirectToURL: AuthCallback.redirectURL,
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )))
        }
    }

    func client() throws -> SupabaseClient { try configuredClient.get() }
}
