import Combine
import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    enum State: Equatable { case idle, loading, loaded(AccountProfile), error(String) }
    enum SaveState: Equatable { case idle, saving, error(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var saveState: SaveState = .idle
    @Published private(set) var user: AuthUser?
    private let service: any ProfileServicing
    private var revision = 0
    var isSaving: Bool { saveState == .saving }
    var profile: AccountProfile? {
        if case .loaded(let profile) = state { return profile }
        return nil
    }

    init(service: any ProfileServicing) { self.service = service }

    /// Called synchronously on auth changes so an old response cannot survive an account switch.
    func setUser(_ user: AuthUser?) {
        guard self.user != user else { return }
        revision += 1
        self.user = user
        state = .idle
        saveState = .idle
    }

    func load(user: AuthUser?) async {
        setUser(user)
        guard let user, !isSaving else { return }
        revision += 1
        let request = revision
        state = .loading
        do {
            let profile = try await service.fetchProfile(expectedUserID: user.id)
            guard request == revision, self.user?.id == user.id, !Task.isCancelled else { return }
            guard profile.id == user.id else { throw ProfileFailure.sessionChanged }
            state = .loaded(profile)
        } catch {
            guard request == revision, self.user?.id == user.id, !Task.isCancelled else { return }
            state = .error(Self.message(error))
        }
    }

    func save(name: String) async -> Bool {
        guard !isSaving, let user, profile?.id == user.id else { return false }
        if let message = ProfileValidation.nameError(name) { saveState = .error(message); return false }
        revision += 1
        let request = revision
        saveState = .saving
        do {
            let profile = try await service.updateDisplayName(ProfileValidation.normalizedName(name), expectedUserID: user.id)
            guard request == revision, self.user?.id == user.id, !Task.isCancelled else { return false }
            guard profile.id == user.id else { throw ProfileFailure.sessionChanged }
            state = .loaded(profile)
            saveState = .idle
            return true
        } catch {
            guard request == revision, self.user?.id == user.id else { return false }
            saveState = .error(Self.message(error))
            return false
        }
    }

    func clearSaveError() { if !isSaving { saveState = .idle } }
    private static func message(_ error: Error) -> String {
        (error as? ProfileFailure)?.localizedDescription ?? ProfileFailure.unavailable.localizedDescription
    }
}
