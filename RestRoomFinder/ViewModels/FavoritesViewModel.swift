import Combine
import CoreLocation
import Foundation

@MainActor
final class FavoritesViewModel: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, error(String) }
    @Published private(set) var state: State = .idle
    @Published private(set) var records: [FavoriteRecord] = []
    @Published private(set) var pending: Set<String> = []
    @Published private(set) var details: [UUID: SavedPlaceDetails] = [:]
    @Published private(set) var detailFailures: Set<UUID> = []
    @Published private(set) var hydrating = false
    @Published private(set) var userID: UUID?
    private let service: any FavoritesServicing
    private let places: any SavedPlaceResolving
    private var byPlace: [String: UUID] = [:]
    private var ids: Set<UUID> = []
    private var revision = 0
    private var loadRevision = 0
    private var hydrationRevision = 0
    private var fetchedAt: [UUID: Date] = [:]
    private var loadingIDs: Set<UUID> = []
    private var location: CLLocation?

    init(service: any FavoritesServicing, places: any SavedPlaceResolving) {
        self.service = service; self.places = places
    }
    func setUser(_ user: AuthUser?) {
        guard userID != user?.id else { return }
        revision += 1; loadRevision += 1; hydrationRevision += 1
        userID = user?.id; records = []; ids = []; byPlace = [:]; details = [:]
        fetchedAt = [:]; pending = []; loadingIDs = []; detailFailures = []; hydrating = false; state = .idle
    }
    func load(user: AuthUser?, force: Bool = false) async {
        setUser(user)
        guard let user, pending.isEmpty, state != .loading, force || state != .loaded else { return }
        let account = revision
        loadRevision += 1
        let request = loadRevision
        state = .loading
        do {
            let fetched = try await service.fetchFavorites(expectedUserID: user.id)
            guard account == revision, request == loadRevision, !Task.isCancelled else { return }
            records = fetched
            rebuildIDs()
            let retained = Set(fetched.map(\.id))
            details = details.filter { retained.contains($0.key) }
            fetchedAt = fetchedAt.filter { retained.contains($0.key) }
            state = .loaded
        } catch {
            guard account == revision, request == loadRevision, !Task.isCancelled else { return }
            state = .error(Self.message(error))
        }
    }
    func key(_ restroom: Restroom) -> String { restroom.googlePlaceID.map { "google:\($0)" } ?? restroom.id.uuidString }
    func favoriteID(_ restroom: Restroom) -> UUID? {
        if let placeID = restroom.googlePlaceID { return byPlace[placeID] }
        return ids.contains(restroom.id) ? restroom.id : nil
    }
    func isFavorite(_ restroom: Restroom) -> Bool { favoriteID(restroom) != nil }
    func isPending(_ restroom: Restroom) -> Bool { pending.contains(key(restroom)) }

    /// Returns a user-facing error, or nil. Never optimistically persists a false saved state.
    func toggle(_ restroom: Restroom, user: AuthUser) async -> String? {
        guard userID == user.id else { return FavoritesFailure.sessionChanged.localizedDescription }
        guard state == .loaded else { return "Saved status is unavailable. Open Saved Restrooms and retry loading first." }
        let key = key(restroom)
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        let account = revision
        defer { if account == revision { pending.remove(key) } }
        do {
            if let id = favoriteID(restroom) {
                try await service.remove(id, expectedUserID: user.id)
                guard account == revision else { return nil }
                removeLocally(id)
            } else {
                let saved = try await service.save(restroom, expectedUserID: user.id)
                guard account == revision else { return nil }
                records.removeAll { $0.id == saved.id }; records.insert(saved, at: 0)
                // Nearby content already shown can be reused transiently until explicit Saved refresh.
                details[saved.id] = SavedPlaceDetails(restroom: restroom)
                fetchedAt[saved.id] = Date()
                rebuildIDs()
            }
            return nil
        } catch { return account == revision ? Self.message(error) : nil }
    }
    func remove(_ record: FavoriteRecord, user: AuthUser) async -> String? {
        guard userID == user.id else { return FavoritesFailure.sessionChanged.localizedDescription }
        let key = record.restroom?.googlePlaceID.map { "google:\($0)" } ?? record.id.uuidString
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        let account = revision
        defer { if account == revision { pending.remove(key) } }
        do {
            try await service.remove(record.id, expectedUserID: user.id)
            guard account == revision else { return nil }
            removeLocally(record.id)
            return nil
        } catch { return account == revision ? Self.message(error) : nil }
    }
    private func removeLocally(_ id: UUID) {
        records.removeAll { $0.id == id }; details[id] = nil; fetchedAt[id] = nil
        detailFailures.remove(id); rebuildIDs()
    }
    private func rebuildIDs() {
        ids = Set(records.map(\.id)); byPlace = [:]
        for record in records { if let placeID = record.restroom?.googlePlaceID { byPlace[placeID] = record.id } }
    }
    func setLocation(_ location: CLLocation?) { self.location = location; objectWillChange.send() }
    func restroom(for record: FavoriteRecord) -> Restroom? {
        let base: Restroom
        if let google = details[record.id]?.restroom { base = google }
        else {
            guard let anchor = record.restroom, anchor.googlePlaceID == nil,
                  let name = anchor.name, let lat = anchor.latitude, let lon = anchor.longitude,
                  CLLocationCoordinate2DIsValid(.init(latitude: lat, longitude: lon)) else { return nil }
            base = Restroom(id: anchor.id, name: name, latitude: lat, longitude: lon, address: anchor.address ?? "Address unavailable",
                cleanlinessRating: nil, overallRating: nil, reviewCount: nil, distance: nil, openingHours: nil,
                accessibility: nil, babyChangingStation: nil, genderNeutral: nil, free: nil, imageName: "toilet")
        }
        let features = record.restroom?.features
        return Restroom(id: base.id, name: base.name, latitude: base.latitude, longitude: base.longitude, address: base.address,
            cleanlinessRating: base.cleanlinessRating, overallRating: base.overallRating, reviewCount: base.reviewCount,
            distance: location?.distance(from: CLLocation(latitude: base.latitude, longitude: base.longitude)), openingHours: base.openingHours,
            accessibility: features?.accessible, babyChangingStation: features?.babyChanging,
            genderNeutral: features?.genderNeutral, free: features?.free, imageName: base.imageName,
            isOpenNow: base.isOpenNow, googlePlaceID: base.googlePlaceID, placeTypes: base.placeTypes,
            businessStatus: base.businessStatus, googleRating: base.googleRating, googleUserRatingCount: base.googleUserRatingCount)
    }
    /// Called when Saved opens / explicitly refreshes, never for heart lookups or view redraws.
    /// Sequential fetches bound concurrency to one; a ten-minute in-memory freshness window bounds repeats.
    func hydrate(force: Bool = false) async {
        guard state == .loaded, !hydrating else { return }
        let account = revision
        hydrationRevision += 1
        let request = hydrationRevision
        hydrating = true
        defer { if account == revision, request == hydrationRevision { hydrating = false } }
        for record in records {
            guard account == revision, request == hydrationRevision, !Task.isCancelled else { return }
            guard let placeID = record.restroom?.googlePlaceID, !loadingIDs.contains(record.id) else { continue }
            if !force, let date = fetchedAt[record.id], Date().timeIntervalSince(date) < 600 { continue }
            loadingIDs.insert(record.id)
            defer { if account == revision { loadingIDs.remove(record.id) } }
            do {
                let result = try await places.fetchSavedPlace(placeID)
                guard account == revision, request == hydrationRevision, !Task.isCancelled else { return }
                loadingIDs.remove(record.id)
                guard ids.contains(record.id) else { continue }
                details[record.id] = result; detailFailures.remove(record.id); fetchedAt[record.id] = Date()
            } catch {
                guard account == revision, request == hydrationRevision else { return }
                loadingIDs.remove(record.id)
                if ids.contains(record.id) { detailFailures.insert(record.id); fetchedAt[record.id] = Date() }
            }
        }
    }
    private static func message(_ error: Error) -> String {
        (error as? FavoritesFailure)?.localizedDescription ?? FavoritesFailure.unavailable.localizedDescription
    }
}
