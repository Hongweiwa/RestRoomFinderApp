import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    enum Operation { case idle, login, signup, logout, callback }
    enum ProfileState: Equatable { case idle, loading, loaded(AccountProfile), unavailable }

    @Published private(set) var state: AuthState = .loading
    @Published private(set) var operation: Operation = .idle
    @Published private(set) var profileState: ProfileState = .idle
    @Published var message: String?
    @Published var callbackMessage: String?
    @Published private(set) var confirmationEmail: String?

    private let service: any AuthenticationServicing
    private var listener: Task<Void, Never>?
    private var profileTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var revision = 0
    private var expiresAt: Date?
    private var started = false
    var isBusy: Bool { operation != .idle }
    var profile: AccountProfile? {
        if case .loaded(let profile) = profileState { return profile }
        return nil
    }

    init(service: any AuthenticationServicing) { self.service = service }
    deinit { listener?.cancel(); profileTask?.cancel(); expiryTask?.cancel() }

    func start() {
        guard !started else { return }
        started = true
        do {
            let stream = try service.events()
            listener = Task { [weak self] in
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    await self?.receive(event)
                }
            }
        } catch {
            state = .guest
            message = friendly(error)
        }
    }

    private func receive(_ event: AuthSessionEvent) async {
        switch event {
        case .signedOut:
            revision += 1
            apply(nil)
        case .initialSession(let session), .sessionChanged(let session):
            // Re-read the SDK's current session, rather than trusting queued/stale event payloads.
            if let session, !session.isValid { state = .loading }
            await refreshSession()
        }
    }

    func refreshSession() async {
        revision += 1
        let request = revision
        do {
            let session = try await service.restoredSession()
            guard request == revision else { return }
            apply(session?.isValid == true ? session : nil)
        } catch {
            guard request == revision else { return }
            apply(nil)
            message = friendly(error)
        }
    }

    private func apply(_ session: AuthSessionSnapshot?) {
        let previousID = state.user?.id
        expiryTask?.cancel()
        guard let session, session.isValid else {
            state = .guest
            expiresAt = nil
            profileTask?.cancel()
            profileState = .idle
            return
        }
        state = .authenticated(session.user)
        expiresAt = session.expiresAt
        confirmationEmail = nil
        if previousID != session.user.id || profileState == .idle { fetchProfile(for: session.user.id) }
        // Do not keep a stale authenticated UI indefinitely if background refresh loses connectivity.
        let delay = max(1, session.expiresAt.timeIntervalSinceNow - 30)
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.state = .loading
            await self.refreshSession()
        }
    }

    func login(email: String, password: String) async {
        guard !isBusy else { return }
        message = nil
        guard let error = AuthValidation.loginError(email: email, password: password) else {
            operation = .login
            defer { operation = .idle }
            do {
                try await service.signIn(email: AuthValidation.normalizedEmail(email), password: password)
                await refreshSession()
            } catch { message = friendly(error) }
            return
        }
        message = error
    }

    func signup(name: String, email: String, password: String, confirmation: String) async {
        guard !isBusy else { return }
        message = nil
        if let error = AuthValidation.signupError(name: name, email: email, password: password, confirmation: confirmation) {
            message = error
            return
        }
        operation = .signup
        defer { operation = .idle }
        do {
            let result = try await service.signUp(name: AuthValidation.normalizedName(name),
                email: AuthValidation.normalizedEmail(email), password: password)
            switch result {
            case .confirmationRequired:
                confirmationEmail = AuthValidation.normalizedEmail(email)
                // A user object alone is not proof of authentication.
                await refreshSession()
            case .sessionCreated: await refreshSession()
            }
        } catch { message = friendly(error) }
    }

    func logout() async {
        guard !isBusy else { return }
        operation = .logout
        message = nil
        defer { operation = .idle }
        do {
            try await service.signOut()
            await refreshSession()
        } catch {
            // SDK 2.55.3 clears local storage and emits signedOut BEFORE attempting revocation.
            // Preserve that guest state even if offline server revocation reports an error.
            await refreshSession()
            message = state.user == nil
                ? "You're signed out on this device. We couldn't confirm server revocation; check your connection."
                : friendly(error)
        }
    }

    func retryProfile() {
        guard let id = state.user?.id else { return }
        fetchProfile(for: id)
    }

    private func fetchProfile(for id: UUID) {
        profileTask?.cancel()
        profileState = .loading
        profileTask = Task { [weak self, service] in
            do {
                let profile = try await service.loadProfile()
                guard let self, !Task.isCancelled, self.state.user?.id == id, profile.id == id else { return }
                self.profileState = .loaded(profile)
            } catch {
                guard let self, !Task.isCancelled, self.state.user?.id == id else { return }
                self.profileState = .unavailable
            }
        }
    }

    /// Future protected actions call this before proceeding, then present AuthenticationView if false.
    /// Refresh through the SDK so expired UI state is never enough to authorize an action.
    func requireAuthentication() async -> Bool {
        guard !isBusy else { return false }
        await refreshSession()
        return state.user != nil && (expiresAt?.timeIntervalSinceNow ?? 0) > 30
    }

    func handleCallback(_ url: URL) async {
        guard AuthCallback.matches(url) else { return }
        guard !isBusy else {
            callbackMessage = "An account request is still running. Finish it, then reopen your confirmation link."
            return
        }
        operation = .callback
        defer { operation = .idle }
        do {
            try await service.handleCallback(url)
            await refreshSession()
            if state.user != nil { callbackMessage = "Your email is confirmed and you're signed in." }
        } catch { callbackMessage = friendly(error) }
    }

    func clearFormMessages() { message = nil; confirmationEmail = nil }

    private func friendly(_ error: Error) -> String {
        (error as? AuthenticationFailure)?.localizedDescription ?? AuthenticationFailure.unavailable.localizedDescription
    }
}
