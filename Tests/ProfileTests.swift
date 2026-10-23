import Foundation

@MainActor
private final class FakeProfileService: ProfileServicing {
    var records: [UUID: AccountProfile] = [:]
    var calls = 0
    var writes = 0
    var fail = false
    var suspendFetch = false
    var suspendSave = false
    var pendingFetch: CheckedContinuation<AccountProfile, Error>?
    var pendingSave: CheckedContinuation<AccountProfile, Error>?

    func fetchProfile(expectedUserID: UUID) async throws -> AccountProfile {
        calls += 1
        if suspendFetch { return try await withCheckedThrowingContinuation { pendingFetch = $0 } }
        if fail { throw ProfileFailure.network }
        guard let profile = records[expectedUserID] else { throw ProfileFailure.unavailable }
        return profile
    }
    func updateDisplayName(_ name: String, expectedUserID: UUID) async throws -> AccountProfile {
        writes += 1
        if suspendSave { return try await withCheckedThrowingContinuation { pendingSave = $0 } }
        if fail { throw ProfileFailure.network }
        let profile = AccountProfile(id: expectedUserID, displayName: name)
        records[expectedUserID] = profile
        return profile
    }
}

@MainActor
enum ProfileTests {
    static func run() async {
        let a = AuthUser(id: UUID(), email: "a@example.com")
        let b = AuthUser(id: UUID(), email: "b@example.com")
        let service = FakeProfileService()
        service.records[a.id] = AccountProfile(id: a.id, displayName: "User A")
        service.records[b.id] = AccountProfile(id: b.id, displayName: "User B")
        let vm = ProfileViewModel(service: service)
        await vm.load(user: nil)
        precondition(vm.state == .idle && service.calls == 0)
        await vm.load(user: a)
        precondition(vm.profile?.displayName == "User A" && vm.user?.email == a.email)
        let blank = await vm.save(name: " \n\t")
        let long = await vm.save(name: String(repeating: "a", count: 51))
        precondition(!blank && !long && service.writes == 0)
        let saved = await vm.save(name: "  Updated Name \n")
        precondition(saved && vm.profile?.displayName == "Updated Name" && service.writes == 1)
        let relaunched = ProfileViewModel(service: service)
        await relaunched.load(user: a)
        precondition(relaunched.profile?.displayName == "Updated Name")
        print("PASS: profile uses account UUID/email, trimmed update, validation prevents writes, reload reads persisted service data")

        service.fail = true
        let failed = await vm.save(name: "Failed Edit")
        precondition(!failed && vm.profile?.displayName == "Updated Name")
        await vm.load(user: a)
        guard case .error = vm.state else { preconditionFailure("Expected recoverable load error") }
        service.fail = false
        await vm.load(user: a)
        precondition(vm.profile?.displayName == "Updated Name")
        vm.setUser(nil)
        precondition(vm.profile == nil && vm.user == nil && vm.saveState == .idle)
        await vm.load(user: b)
        precondition(vm.profile?.displayName == "User B" && vm.user?.email == b.email)
        print("PASS: failed save preserves profile, load error/retry, logout clears identity and user B replaces user A")

        service.suspendFetch = true
        let loadA = Task { await vm.load(user: a) }
        await until { service.pendingFetch != nil }
        precondition(vm.state == .loading && vm.profile == nil)
        vm.setUser(b)
        service.suspendFetch = false
        await vm.load(user: b)
        service.pendingFetch?.resume(returning: AccountProfile(id: a.id, displayName: "Late A"))
        service.pendingFetch = nil
        await loadA.value
        precondition(vm.profile?.displayName == "User B")
        print("PASS: delayed user A response cannot overwrite user B; loading contains no fake profile")

        service.suspendSave = true
        let writes = service.writes
        let saveB = Task { await vm.save(name: "New B") }
        await until { service.pendingSave != nil }
        let duplicate = await vm.save(name: "Duplicate")
        precondition(!duplicate && service.writes == writes + 1)
        vm.setUser(nil)
        service.pendingSave?.resume(returning: AccountProfile(id: b.id, displayName: "New B"))
        service.pendingSave = nil
        let lateSave = await saveB.value
        precondition(!lateSave && vm.profile == nil && vm.state == .idle)
        print("PASS: duplicate saves suppressed; save finishing after logout cannot restore account data")

        service.suspendSave = false
        service.records[b.id] = AccountProfile(id: a.id, displayName: "Wrong owner")
        await vm.load(user: b)
        guard case .error = vm.state else { preconditionFailure("Wrong owner must be rejected") }
        print("PASS: mismatched profile identity rejected")
    }

    private static func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() }
        preconditionFailure("Profile operation did not reach expected state")
    }
}
