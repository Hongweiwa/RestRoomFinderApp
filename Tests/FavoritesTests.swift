import Foundation

@MainActor
private final class FakeFavoritesService: FavoritesServicing {
    var records: [UUID: [FavoriteRecord]] = [:]
    var fetches = 0; var writes = 0; var deletes = 0
    var fail = false; var suspend = false
    var saveFailure: FavoritesFailure?
    var pending: CheckedContinuation<FavoriteRecord, Error>?
    var suspendFetch = false
    var pendingFetch: CheckedContinuation<[FavoriteRecord], Error>?
    func fetchFavorites(expectedUserID: UUID) async throws -> [FavoriteRecord] {
        fetches += 1
        if suspendFetch { return try await withCheckedThrowingContinuation { pendingFetch = $0 } }
        if fail { throw FavoritesFailure.network }
        return records[expectedUserID] ?? []
    }
    func save(_ restroom: Restroom, expectedUserID: UUID) async throws -> FavoriteRecord {
        writes += 1
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        if fail { throw FavoritesFailure.network }
        if let saveFailure { throw saveFailure }
        let value = FavoriteRecord(restroomID: UUID(), restroom: .init(id: UUID(), googlePlaceID: restroom.googlePlaceID,
            name: nil, address: nil, latitude: nil, longitude: nil, features: nil))
        records[expectedUserID, default: []].append(value)
        return value
    }
    func remove(_ id: UUID, expectedUserID: UUID) async throws {
        deletes += 1
        if fail { throw FavoritesFailure.network }
        records[expectedUserID]?.removeAll { $0.id == id }
    }
}
@MainActor
private final class FakeSavedPlaces: SavedPlaceResolving {
    var calls = 0
    var fail = false
    let restroom: Restroom
    init(_ restroom: Restroom) { self.restroom = restroom }
    func fetchSavedPlace(_ placeID: String) async throws -> SavedPlaceDetails {
        calls += 1
        if fail { throw FavoritesFailure.network }
        return SavedPlaceDetails(restroom: restroom)
    }
}
@MainActor
enum FavoritesTests {
    static func run() async {
        let a = AuthUser(id: UUID(), email: "a@example.com"), b = AuthUser(id: UUID(), email: "b@example.com")
        let restroom = RestroomPlaceMapper.map([PlaceRecord(placeID: "stable-google-id", name: "Test Restroom", latitude: 40, longitude: -73, address: nil)], from: .init(latitude: 40, longitude: -73))[0]
        let service = FakeFavoritesService(), places = FakeSavedPlaces(restroom)
        let vm = FavoritesViewModel(service: service, places: places)
        await vm.load(user: nil)
        precondition(service.fetches == 0 && vm.records.isEmpty)
        await vm.load(user: a)
        precondition(vm.state == .loaded && vm.records.isEmpty)
        let saved = await vm.toggle(restroom, user: a)
        precondition(saved == nil && vm.isFavorite(restroom) && vm.records.count == 1)
        precondition(vm.records[0].id != restroom.id, "Google-derived UI UUID is not the database UUID")
        for _ in 0..<20 { _ = vm.isFavorite(restroom) }
        precondition(service.fetches == 1 && places.calls == 0)
        await vm.hydrate(); precondition(places.calls == 0)
        await vm.hydrate(force: true); precondition(places.calls == 1)
        await vm.hydrate(); precondition(places.calls == 1)
        let relaunched = FavoritesViewModel(service: service, places: places)
        await relaunched.load(user: a); precondition(relaunched.isFavorite(restroom))
        print("PASS: cloud-backed save, canonical Place ID lookup, no per-card queries, transient details freshness and relaunch reload")
        service.fail = true
        let failure = await vm.toggle(restroom, user: a)
        precondition(failure != nil && vm.isFavorite(restroom))
        service.fail = false
        let removed = await vm.toggle(restroom, user: a)
        precondition(removed == nil && !vm.isFavorite(restroom) && vm.records.isEmpty)
        service.fail = true
        let failedSave = await vm.toggle(restroom, user: a)
        precondition(failedSave != nil && !vm.isFavorite(restroom))
        await vm.load(user: a, force: true)
        guard case .error = vm.state else { preconditionFailure("Failure must not appear empty") }
        service.fail = false
        await vm.load(user: a, force: true)
        precondition(vm.state == .loaded)
        print("PASS: save/remove failures preserve confirmed state, error distinct from empty, retry succeeds")
        service.saveFailure = .backend(step: "profile-recovery", code: "PGRST202")
        let missingRecovery = await vm.toggle(restroom, user: a)
        precondition(missingRecovery?.contains("Day 13") == true)
        precondition(missingRecovery?.contains("profile-recovery/PGRST202") == true)
        precondition(!vm.isFavorite(restroom) && !vm.isPending(restroom))
        service.saveFailure = .backend(step: "place", code: "PGRST202")
        let missingResolver = await vm.toggle(restroom, user: a)
        precondition(missingResolver?.contains("Day 14") == true)
        service.saveFailure = nil
        print("PASS: setup failures identify the missing migration and leave Save available for retry")
        service.suspend = true
        let task = Task { await vm.toggle(restroom, user: a) }
        for _ in 0..<1000 { if service.pending != nil { break }; await Task.yield() }
        precondition(service.pending != nil)
        let writes = service.writes
        _ = await vm.toggle(restroom, user: a)
        precondition(service.writes == writes)
        vm.setUser(nil)
        precondition(vm.records.isEmpty && !vm.isFavorite(restroom) && vm.details.isEmpty)
        await vm.load(user: b)
        service.pending?.resume(returning: FavoriteRecord(restroomID: UUID(), restroom: nil))
        _ = await task.value
        precondition(vm.userID == b.id && vm.records.isEmpty)
        print("PASS: duplicate taps suppressed, logout clears private state, late A save cannot appear for B")
        let unavailable = FavoriteRecord(restroomID: UUID(), restroom: nil)
        service.records[b.id] = [unavailable]
        await vm.load(user: b, force: true)
        precondition(vm.records.count == 1 && vm.restroom(for: unavailable) == nil)
        _ = await vm.remove(unavailable, user: b)
        precondition(vm.records.isEmpty)
        print("PASS: inaccessible place stays removable without invented coordinates or fake details")
        service.suspendFetch = true
        let oldLoad = Task { await vm.load(user: a) }
        for _ in 0..<1000 { if service.pendingFetch != nil { break }; await Task.yield() }
        precondition(service.pendingFetch != nil)
        vm.setUser(b)
        service.suspendFetch = false
        await vm.load(user: b)
        service.pendingFetch?.resume(returning: [unavailable])
        await oldLoad.value
        precondition(vm.userID == b.id && vm.records.isEmpty)
        let google = FavoriteRecord(restroomID: UUID(), restroom: .init(id: UUID(), googlePlaceID: "stable-google-id",
            name: nil, address: nil, latitude: nil, longitude: nil, features: nil))
        service.records[b.id] = [google]
        await vm.load(user: b, force: true)
        places.fail = true
        await vm.hydrate(force: true)
        precondition(vm.state == .loaded && vm.records.count == 1 && vm.detailFailures.contains(google.id))
        precondition(vm.restroom(for: google) == nil)
        places.fail = false
        await vm.hydrate(force: true)
        precondition(vm.restroom(for: google) != nil && vm.detailFailures.isEmpty)
        print("PASS: late A list cannot leak into B; failed Google refresh retains favorite and explicit retry recovers")

    }
}
