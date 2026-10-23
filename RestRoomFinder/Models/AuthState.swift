import Foundation

struct AuthUser: Equatable, Sendable {
    let id: UUID
    let email: String
}

enum AuthState: Equatable {
    case loading
    case guest
    case authenticated(AuthUser)

    var user: AuthUser? {
        if case .authenticated(let user) = self { return user }
        return nil
    }
}

/// UI-safe session snapshot. Tokens remain inside Supabase's built-in storage.
struct AuthSessionSnapshot: Equatable, Sendable {
    let user: AuthUser
    let expiresAt: Date
    var isValid: Bool { expiresAt.timeIntervalSinceNow > 30 }
}

enum AuthSessionEvent: Sendable {
    case initialSession(AuthSessionSnapshot?)
    case sessionChanged(AuthSessionSnapshot?)
    case signedOut
}

enum SignupResult { case confirmationRequired, sessionCreated }

struct AccountProfile: Decodable, Equatable {
    let id: UUID
    let displayName: String?
    enum CodingKeys: String, CodingKey { case id; case displayName = "display_name" }
}

enum AuthenticationFailure: Error, LocalizedError {
    case invalidCredentials, emailNotConfirmed, emailInUse, weakPassword, rateLimited
    case network, notConfigured, unavailable, expiredSession, invalidLink, profileUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Incorrect email or password."
        case .emailNotConfirmed: return "Please verify your email before signing in."
        case .emailInUse: return "This email may already have an account. Try logging in."
        case .weakPassword: return "Choose a stronger password. Use at least 8 characters; your account service may require additional complexity."
        case .rateLimited: return "Too many attempts. Please wait a little before trying again."
        case .network: return "Unable to connect. Check your internet connection and try again."
        case .notConfigured: return "Account access isn't configured yet. You can continue as a guest."
        case .unavailable: return "We couldn't complete that account request. Please try again."
        case .expiredSession: return "Your session couldn't be restored. Please log in again, or retry when connected."
        case .invalidLink: return "This confirmation link couldn't be opened. Try logging in after verifying your email, or reopen the latest link on the device where you signed up."
        case .profileUnavailable: return "You're signed in, but your profile couldn't be loaded. Please retry."
        }
    }
}

/// Basic input validation only; Supabase enforces the project's full password policy.
enum AuthValidation {
    static let minimumPasswordLength = 8
    static func normalizedEmail(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func normalizedName(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func emailError(_ email: String) -> String? {
        let value = normalizedEmail(email)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard value.count <= 254, parts.count == 2, !parts[0].isEmpty,
              !parts[1].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !value.contains(where: { $0.isWhitespace }) else { return "Enter a valid email address." }
        return nil
    }

    static func loginError(email: String, password: String) -> String? {
        if let error = emailError(email) { return error }
        return password.isEmpty ? "Enter your password." : nil
    }

    static func signupError(name: String, email: String, password: String, confirmation: String) -> String? {
        let name = normalizedName(name)
        guard !name.isEmpty else { return "Enter your name." }
        guard name.unicodeScalars.count <= 80 else { return "Use a name with 80 characters or fewer." }
        if let error = emailError(email) { return error }
        guard password.count >= minimumPasswordLength else { return "Use at least 8 characters for your password." }
        guard password == confirmation else { return "Your passwords don't match." }
        return nil
    }
}

enum AuthCallback {
    static let redirectURL = URL(string: "restroomfinder://auth/callback")
    static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "restroomfinder" && url.host?.lowercased() == "auth" && url.path == "/callback"
        && url.user == nil && url.password == nil && url.port == nil
    }
}
