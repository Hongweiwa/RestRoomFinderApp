import Foundation
import Supabase

/// Only this service talks to Supabase Auth. No passwords/tokens are stored by app code.
@MainActor
final class AuthService: AuthenticationServicing {
    private func client() throws -> SupabaseClient {
        do { return try SupabaseManager.shared.client() }
        catch { throw AuthenticationFailure.notConfigured }
    }

    func events() throws -> AsyncStream<AuthSessionEvent> {
        let client = try client()
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    if Task.isCancelled { break }
                    switch event {
                    case .initialSession: continuation.yield(.initialSession(Self.snapshot(session)))
                    case .signedOut, .userDeleted: continuation.yield(.signedOut)
                    case .signedIn, .tokenRefreshed, .userUpdated, .passwordRecovery:
                        continuation.yield(.sessionChanged(Self.snapshot(session)))
                    default: break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func restoredSession() async throws -> AuthSessionSnapshot? {
        do {
            let client = try client()
            guard client.auth.currentSession != nil else { return nil }
            // Unlike currentSession/INITIAL_SESSION, this refreshes an expired local session.
            let session = try await client.auth.session
            guard !session.isExpired, !session.user.isAnonymous else { return nil }
            return Self.snapshot(session)
        } catch AuthError.sessionMissing { return nil }
        catch { throw Self.readable(error) }
    }

    func signUp(name: String, email: String, password: String) async throws -> SignupResult {
        do {
            let response = try await client().auth.signUp(email: email, password: password,
                data: ["display_name": .string(name)], redirectTo: AuthCallback.redirectURL)
            // The database trigger creates the durable profile, including when session is nil.
            return response.session == nil ? .confirmationRequired : .sessionCreated
        } catch { throw Self.readable(error) }
    }

    func signIn(email: String, password: String) async throws {
        do { _ = try await client().auth.signIn(email: email, password: password) }
        catch { throw Self.readable(error) }
    }

    func signOut() async throws {
        do { try await client().auth.signOut(scope: .local) }
        catch { throw Self.readable(error) }
    }

    func handleCallback(_ url: URL) async throws {
        guard AuthCallback.matches(url), url.fragment == nil,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "code" && !($0.value ?? "").isEmpty }) == true else {
            throw AuthenticationFailure.invalidLink
        }
        do {
            // SDK PKCE exchange; async form allows safe UI error handling. Never log callback URLs.
            _ = try await client().auth.session(from: url)
        } catch { throw Self.readable(error, fallback: .invalidLink) }
    }

    func loadProfile() async throws -> AccountProfile {
        do {
            let client = try client()
            let session = try await client.auth.session
            guard !session.isExpired, !session.user.isAnonymous else { throw AuthenticationFailure.expiredSession }
            // Identity comes from the SDK, not an arbitrary user ID passed by a View.
            return try await client.from("profiles").select("id,display_name")
                .eq("id", value: session.user.id).single().execute().value
        } catch { throw Self.readable(error, fallback: .profileUnavailable) }
    }

    private static func snapshot(_ session: Session?) -> AuthSessionSnapshot? {
        guard let session, !session.user.isAnonymous else { return nil }
        return AuthSessionSnapshot(user: AuthUser(id: session.user.id, email: session.user.email ?? ""),
                                   expiresAt: Date(timeIntervalSince1970: session.expiresAt))
    }

    private static func readable(_ error: Error, fallback: AuthenticationFailure = .unavailable) -> AuthenticationFailure {
        let result: AuthenticationFailure
        if let known = error as? AuthenticationFailure { result = known }
        else if error is URLError { result = .network }
        else if let auth = error as? AuthError {
            switch auth.errorCode.rawValue {
            case "invalid_credentials": result = .invalidCredentials
            case "email_not_confirmed": result = .emailNotConfirmed
            case "email_exists", "user_already_exists": result = .emailInUse
            case "weak_password": result = .weakPassword
            case "over_request_rate_limit", "over_email_send_rate_limit", "over_sms_send_rate_limit": result = .rateLimited
            case "session_not_found", "session_expired", "refresh_token_not_found", "refresh_token_already_used": result = .expiredSession
            default: result = fallback
            }
        } else { result = fallback }
        #if DEBUG
        // Fixed local error category only. Never SDK messages, email, password, URL or session data.
        print("[Auth] Request failed: \(result)")
        #endif
        return result
    }
}
