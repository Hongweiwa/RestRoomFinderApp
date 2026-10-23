import Foundation

@MainActor
private final class FakeAuthenticationService: AuthenticationServicing {
    let user = AuthUser(id: UUID(), email: "test@example.com")
    var current: AuthSessionSnapshot?
    var restoreError: Error?
    var authError: Error?
    var profileError = false
    var confirmEmail = true
    var signOutFailsAfterClearing = false
    var subscriptions = 0
    var loginCalls = 0
    var signupCalls = 0
    var callbackCalls = 0
    var lastName: String?
    var lastEmail: String?
    var suspendAction = false
    var suspendRestore = false
    var suspendProfile = false
    var actionContinuation: CheckedContinuation<Void, Never>?
    var restoreContinuation: CheckedContinuation<AuthSessionSnapshot?, Error>?
    var profileContinuation: CheckedContinuation<AccountProfile, Error>?
    var continuation: AsyncStream<AuthSessionEvent>.Continuation?

    func validSession() -> AuthSessionSnapshot { AuthSessionSnapshot(user: user, expiresAt: Date().addingTimeInterval(3600)) }
    func events() throws -> AsyncStream<AuthSessionEvent> {
        subscriptions += 1
        let (stream, continuation) = AsyncStream<AuthSessionEvent>.makeStream()
        self.continuation = continuation
        continuation.yield(.initialSession(current))
        return stream
    }
    func restoredSession() async throws -> AuthSessionSnapshot? {
        if suspendRestore { return try await withCheckedThrowingContinuation { restoreContinuation = $0 } }
        if let restoreError { throw restoreError }
        return current
    }
    func signUp(name: String, email: String, password: String) async throws -> SignupResult {
        signupCalls += 1
        lastName = name; lastEmail = email
        if suspendAction { await withCheckedContinuation { actionContinuation = $0 } }
        if let authError { throw authError }
        if confirmEmail { return .confirmationRequired }
        current = validSession()
        continuation?.yield(.sessionChanged(current))
        return .sessionCreated
    }
    func signIn(email: String, password: String) async throws {
        loginCalls += 1
        lastEmail = email
        if suspendAction { await withCheckedContinuation { actionContinuation = $0 } }
        if let authError { throw authError }
        current = validSession()
        continuation?.yield(.sessionChanged(current))
    }
    func signOut() async throws {
        current = nil
        continuation?.yield(.signedOut)
        if signOutFailsAfterClearing { throw AuthenticationFailure.network }
    }
    func handleCallback(_ url: URL) async throws {
        callbackCalls += 1
        if let authError { throw authError }
        current = validSession()
        continuation?.yield(.sessionChanged(current))
    }
    func loadProfile() async throws -> AccountProfile {
        if suspendProfile { return try await withCheckedThrowingContinuation { profileContinuation = $0 } }
        if profileError { throw AuthenticationFailure.profileUnavailable }
        return AccountProfile(id: user.id, displayName: "Durable Profile")
    }
}

@MainActor
enum AuthenticationTests {
    static func run() async {
        let service = FakeAuthenticationService()
        let vm = AuthViewModel(service: service)
        precondition(vm.state == .loading)
        vm.start(); vm.start()
        await until { vm.state == .guest }
        precondition(service.subscriptions == 1)
        await vm.signup(name: " ", email: "bad", password: "short", confirmation: "other")
        await vm.signup(name: "Name", email: "valid@example.com", password: "long-password", confirmation: "mismatch")
        precondition(vm.message == "Your passwords don't match.")
        await vm.login(email: "invalid", password: "password")
        precondition(service.signupCalls == 0 && service.loginCalls == 0)
        precondition(AuthValidation.signupError(name: "Name", email: "valid@example.com", password: "1234567", confirmation: "1234567") != nil)
        precondition(AuthValidation.emailError("one@@example.com") != nil && AuthValidation.emailError("one@") != nil)
        precondition(AuthValidation.emailError("person+test@example.com") == nil)
        print("PASS: initial loading→guest, one listener, field validation before any auth request")

        await vm.signup(name: "  Person  ", email: " test@example.com ", password: "sample-password", confirmation: "sample-password")
        precondition(vm.state == .guest && vm.confirmationEmail == "test@example.com")
        precondition(service.lastName == "Person" && service.lastEmail == "test@example.com")
        service.confirmEmail = false
        await vm.signup(name: "Person", email: "test@example.com", password: "sample-password", confirmation: "sample-password")
        await until { vm.state.user?.id == service.user.id && vm.profile != nil }
        precondition(vm.confirmationEmail == nil && vm.profile?.displayName == "Durable Profile")
        await vm.logout()
        await until { vm.state == .guest }
        precondition(vm.profile == nil)
        print("PASS: both confirmation modes, trimmed input, authenticated SDK identity, durable profile read, logout")

        service.authError = AuthenticationFailure.invalidCredentials
        await vm.login(email: "test@example.com", password: "incorrect")
        precondition(vm.state == .guest && vm.message == "Incorrect email or password.")
        service.authError = AuthenticationFailure.emailNotConfirmed
        await vm.login(email: "test@example.com", password: "unconfirmed")
        precondition(vm.state == .guest && vm.message?.contains("verify your email") == true)
        service.authError = AuthenticationFailure.network
        await vm.login(email: "test@example.com", password: "offline-test")
        precondition(vm.state == .guest && vm.message?.contains("internet connection") == true)
        service.authError = nil
        service.suspendAction = true
        let loginCount = service.loginCalls
        let firstLogin = Task { await vm.login(email: "test@example.com", password: "sample-password") }
        await until { service.actionContinuation != nil }
        await vm.login(email: "test@example.com", password: "sample-password")
        precondition(service.loginCalls == loginCount + 1 && vm.isBusy)
        service.actionContinuation?.resume(); service.actionContinuation = nil
        await firstLogin.value
        service.suspendAction = false
        await until { vm.state.user != nil }
        print("PASS: invalid credentials, unconfirmed email, offline login, duplicate login prevention")

        service.signOutFailsAfterClearing = true
        await vm.logout()
        await until { vm.state == .guest }
        precondition(vm.message?.contains("signed out on this device") == true)
        service.signOutFailsAfterClearing = false
        service.suspendAction = true
        service.confirmEmail = true
        let signupCount = service.signupCalls
        let firstSignup = Task { await vm.signup(name: "Name", email: "test@example.com", password: "sample-password", confirmation: "sample-password") }
        await until { service.actionContinuation != nil }
        await vm.signup(name: "Name", email: "test@example.com", password: "sample-password", confirmation: "sample-password")
        precondition(service.signupCalls == signupCount + 1)
        service.actionContinuation?.resume(); service.actionContinuation = nil
        await firstSignup.value
        service.suspendAction = false
        precondition(vm.state == .guest)
        print("PASS: offline logout preserves SDK-cleared guest state, duplicate signup prevention")

        // Simulate a fresh VM reading SDK-persisted storage after app relaunch.
        service.current = service.validSession()
        let relaunched = AuthViewModel(service: service)
        relaunched.start()
        await until { relaunched.state.user?.id == service.user.id }
        let authorized = await relaunched.requireAuthentication()
        precondition(authorized)
        service.current = AuthSessionSnapshot(user: service.user, expiresAt: Date().addingTimeInterval(-60))
        service.restoreError = AuthenticationFailure.network
        let expiredAuthorized = await relaunched.requireAuthentication()
        precondition(!expiredAuthorized && relaunched.state == .guest)
        service.restoreError = nil
        service.current = nil
        let loggedOutRelaunch = AuthViewModel(service: service)
        loggedOutRelaunch.start()
        await until { loggedOutRelaunch.state == .guest }
        print("PASS: persisted valid session restoration, signed-out relaunch, expired/offline session cannot authorize actions")

        let expired = FakeAuthenticationService()
        expired.current = AuthSessionSnapshot(user: expired.user, expiresAt: Date().addingTimeInterval(-60))
        expired.suspendRestore = true
        let refreshing = AuthViewModel(service: expired)
        refreshing.start()
        await until { expired.restoreContinuation != nil }
        precondition(refreshing.state == .loading && refreshing.state.user == nil)
        expired.suspendRestore = false
        expired.current = expired.validSession()
        expired.restoreContinuation?.resume(returning: expired.current); expired.restoreContinuation = nil
        await until { refreshing.state.user?.id == expired.user.id }
        print("PASS: expired INITIAL_SESSION waits for SDK refresh before authenticating")

        let delayed = FakeAuthenticationService()
        delayed.current = delayed.validSession(); delayed.suspendProfile = true
        let delayedVM = AuthViewModel(service: delayed)
        delayedVM.start()
        await until { delayed.profileContinuation != nil }
        await delayedVM.logout()
        delayed.profileContinuation?.resume(returning: AccountProfile(id: delayed.user.id, displayName: "Late profile"))
        delayed.profileContinuation = nil
        await until { delayedVM.state == .guest }
        await Task.yield()
        precondition(delayedVM.profile == nil)
        delayed.suspendProfile = false; delayed.profileError = true
        await delayedVM.login(email: "test@example.com", password: "sample-password")
        await until { delayedVM.profileState == .unavailable }
        precondition(delayedVM.state.user != nil, "Profile outage must not fake a failed sign-in")
        delayed.profileError = false; delayedVM.retryProfile()
        await until { delayedVM.profile != nil }
        print("PASS: late profile cannot restore logged-out identity, profile failure is recoverable")

        guard let callback = AuthCallback.redirectURL,
              let unrelated = URL(string: "https://example.com/callback"),
              let invalidHost = URL(string: "restroomfinder://other/callback") else { preconditionFailure("Test URLs") }
        precondition(AuthCallback.matches(callback) && !AuthCallback.matches(unrelated) && !AuthCallback.matches(invalidHost))
        await loggedOutRelaunch.handleCallback(unrelated)
        precondition(service.callbackCalls == 0)
        await loggedOutRelaunch.handleCallback(callback)
        await until { loggedOutRelaunch.state.user != nil }
        precondition(service.callbackCalls == 1)
        print("PASS: auth callback routing and SDK session event handling")
    }

    private static func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("Timed out waiting for auth state")
    }
}
