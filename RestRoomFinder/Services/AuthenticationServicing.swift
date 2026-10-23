import Foundation

@MainActor
protocol AuthenticationServicing {
    func events() throws -> AsyncStream<AuthSessionEvent>
    func restoredSession() async throws -> AuthSessionSnapshot?
    func signUp(name: String, email: String, password: String) async throws -> SignupResult
    func signIn(email: String, password: String) async throws
    func signOut() async throws
    func handleCallback(_ url: URL) async throws
    func loadProfile() async throws -> AccountProfile
}
