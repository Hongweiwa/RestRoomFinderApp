import Combine
import CoreLocation
import Foundation

/// One discovery/selection store shared by Home and the map sheet.
@MainActor
final class NearbyRestroomsViewModel: ObservableObject {
    enum State: Equatable {
        case idle, loading, loaded, empty
        case error(String)
    }
    @Published private(set) var state: State = .idle
    @Published private(set) var allRestrooms: [Restroom] = [] { didSet { applyFilters() } }
    @Published private(set) var filteredRestrooms: [Restroom] = []
    @Published private(set) var filter = RestroomFilter()
    @Published private(set) var selectedRestroomID: UUID?
    @Published private(set) var selectionRevision = 0
    @Published private(set) var discoveryRevision = 0
    @Published private(set) var userLocation: CLLocation?
    @Published private(set) var searchCenter: CLLocation?
    @Published private(set) var mapCenter: CLLocation?
    @Published var searchText = "" {
        didSet {
            if !settingSearchText && searchText.trimmingCharacters(in: .whitespacesAndNewlines) !=
                oldValue.trimmingCharacters(in: .whitespacesAndNewlines) { scheduleAutocomplete() }
        }
    }
    enum LocationSearchState: Equatable {
        case idle, waiting, loading, suggestions, empty, resolving
        case error(String)
    }
    @Published private(set) var locationSearchState: LocationSearchState = .idle
    @Published private(set) var predictions: [LocationPrediction] = []
    @Published private(set) var selectedSearchLocation: SearchLocation?
    @Published private(set) var mapFocusRevision = 0
    @Published private(set) var searchDismissRevision = 0
    private var autocompleteTask: Task<Void, Never>?
    private var autocompleteRevision = 0
    private var autocompleteSessionID: UUID?
    private var settingSearchText = false
    private let debounce: Duration
    private var nearbyRequestID = UUID()
    private var activeNearbySearch: (location: CLLocation, radius: Double)?
    private var locationService: (any LocationSearching)? { service as? any LocationSearching }
    private let service: any NearbyRestroomSearching
    private var didInitialSearch = false
    private var lastSearch: (location: CLLocation, radius: Double, date: Date)?
    private var requestedRadius = NearbySearchConfiguration.radiusMeters
    private let now: () -> Date

    init(service: any NearbyRestroomSearching, now: @escaping () -> Date = Date.init,
         debounce: Duration = LocationSearchConfiguration.debounce) {
        self.service = service
        self.now = now
        self.debounce = debounce
    }

    var filterButtonTitle: String {
        filter.activeCount == 0 ? "Filter" : "Filter (\(filter.activeCount))"
    }

    var hasNoFilterMatches: Bool {
        !allRestrooms.isEmpty && filter.activeCount > 0 && filter.apply(to: allRestrooms).isEmpty
    }

    func applyRatings(_ summaries: [String: RestroomRatingSummary]) {
        let updated = allRestrooms.map { $0.withRatings(summaries[$0.reviewKey]) }
        if updated != allRestrooms { allRestrooms = updated }
    }

    func updateFilter(_ filter: RestroomFilter) {
        self.filter = filter
        applyFilters()
    }

    private func applyFilters() {
        filteredRestrooms = filter.apply(to: allRestrooms)
        reconcileSelection()
    }

    var selectedRestroom: Restroom? { filteredRestrooms.first { $0.id == selectedRestroomID } }
    var canSearchThisArea: Bool {
        guard let mapCenter, let reference = searchCenter ?? userLocation else { return false }
        return mapCenter.distance(from: reference) >= NearbySearchConfiguration.duplicateDistanceMeters
    }

    func select(_ id: UUID?) {
        selectedRestroomID = id.flatMap { id in filteredRestrooms.contains { $0.id == id } ? id : nil }
        selectionRevision += 1
    }

    func resetFilters() {
        updateFilter(RestroomFilter())
    }

    /// Camera events only record state. They never call Places.
    func mapDidMove(to coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        mapCenter = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    func updateUserLocation(_ location: CLLocation?) {
        guard let location, isValid(location) else {
            userLocation = nil
            allRestrooms = RestroomPlaceMapper.measuring(allRestrooms, from: nil)
            return
        }
        guard userLocation?.coordinate.latitude != location.coordinate.latitude ||
                userLocation?.coordinate.longitude != location.coordinate.longitude else { return }
        userLocation = location
        allRestrooms = RestroomPlaceMapper.measuring(allRestrooms, from: location)
    }

    func searchInitially(from location: CLLocation?) async {
        updateUserLocation(location)
        guard !didInitialSearch, let location, isValid(location) else { return }
        didInitialSearch = true
        await search(from: location)
    }

    func searchThisArea() async {
        guard let mapCenter, canSearchThisArea else { return }
        selectedSearchLocation = nil
        await search(from: mapCenter)
    }

    func retry() async {
        guard let center = searchCenter ?? userLocation else { return }
        await search(from: center, radius: requestedRadius)
    }

    /// Search center is independent from the user's actual position.
    func search(from location: CLLocation, radius: Double = NearbySearchConfiguration.radiusMeters) async {
        guard isValid(location), radius.isFinite, radius > 0, radius <= 50_000 else { return }
        if let active = activeNearbySearch, active.radius == radius,
           active.location.distance(from: location) < NearbySearchConfiguration.duplicateDistanceMeters { return }
        let requestID = UUID()
        nearbyRequestID = requestID
        activeNearbySearch = nil
        searchCenter = location
        requestedRadius = radius
        if let lastSearch, lastSearch.radius == radius,
           now().timeIntervalSince(lastSearch.date) < NearbySearchConfiguration.duplicateInterval,
           lastSearch.location.distance(from: location) < NearbySearchConfiguration.duplicateDistanceMeters {
            state = allRestrooms.isEmpty ? .empty : .loaded
            return
        }
        state = .loading
        activeNearbySearch = (location, radius)
        // Retain the current markers/cards while loading or if the request fails.
        do {
            let results = try await service.searchNearbyRestrooms(
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, radius: radius)
            guard nearbyRequestID == requestID else { return }
            activeNearbySearch = nil
            var seen = Set<String>()
            let unique = results.filter { seen.insert($0.googlePlaceID ?? $0.id.uuidString).inserted }
            allRestrooms = RestroomPlaceMapper.measuring(unique, from: userLocation)
            discoveryRevision += 1
            lastSearch = (location, radius, now())
            state = allRestrooms.isEmpty ? .empty : .loaded
        } catch {
            guard nearbyRequestID == requestID else { return }
            activeNearbySearch = nil
            state = .error("Couldn't load this area. Check your connection and try again. Previous results, if any, are still shown.")
        }
    }

    // MARK: - Geographic autocomplete, independent of restroom filtering

    func retryLocationSearch() { scheduleAutocomplete() }

    private func scheduleAutocomplete() {
        autocompleteTask?.cancel()
        autocompleteRevision += 1
        let revision = autocompleteRevision
        predictions = []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= LocationSearchConfiguration.minimumQueryLength else {
            if query.isEmpty { endAutocompleteSession() }
            locationSearchState = .idle
            return
        }
        guard let locationService else {
            locationSearchState = .error("Location search is unavailable.")
            return
        }
        locationSearchState = .waiting
        let delay = debounce
        autocompleteTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, self.autocompleteRevision == revision else { return }
                let sessionID = self.autocompleteSessionID ?? UUID()
                self.autocompleteSessionID = sessionID
                let bias = (self.searchCenter ?? self.userLocation)?.coordinate
                self.locationSearchState = .loading
                let results = try await locationService.autocomplete(query: query, bias: bias, sessionID: sessionID)
                guard !Task.isCancelled, self.autocompleteRevision == revision else { return }
                var seen = Set<String>()
                self.predictions = results.filter { seen.insert($0.id).inserted }
                self.locationSearchState = self.predictions.isEmpty ? .empty : .suggestions
            } catch {
                guard let self, !Task.isCancelled, self.autocompleteRevision == revision else { return }
                self.locationSearchState = .error("Unable to load search suggestions. Try again or edit your search.")
            }
        }
    }

    func cancelLocationSearch() {
        searchDismissRevision += 1
        autocompleteTask?.cancel()
        autocompleteTask = nil
        autocompleteRevision += 1
        endAutocompleteSession()
        predictions = []
        clearQueryWithoutSearching()
        locationSearchState = .idle
    }

    private func clearQueryWithoutSearching() {
        settingSearchText = true
        searchText = ""
        settingSearchText = false
    }

    private func endAutocompleteSession() {
        if let id = autocompleteSessionID { locationService?.endAutocompleteSession(id) }
        autocompleteSessionID = nil
    }

    func selectLocationPrediction(_ prediction: LocationPrediction) async {
        guard predictions.contains(prediction), let locationService, let sessionID = autocompleteSessionID else { return }
        autocompleteTask?.cancel()
        autocompleteRevision += 1
        let revision = autocompleteRevision
        autocompleteSessionID = nil
        predictions = []
        locationSearchState = .resolving
        searchDismissRevision += 1
        // A terminated token is never reused, including after errors or cancellation.
        defer { locationService.endAutocompleteSession(sessionID) }
        do {
            let destination = try await locationService.resolveLocation(prediction, sessionID: sessionID)
            guard autocompleteRevision == revision else { return }
            guard CLLocationCoordinate2DIsValid(destination.coordinate) else {
                locationSearchState = .error("This location has no usable coordinate. Try another result.")
                return
            }
            clearQueryWithoutSearching()
            locationSearchState = .idle
            selectedSearchLocation = destination
            didInitialSearch = true // A later GPS fix must not replace the chosen area.
            let location = CLLocation(latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude)
            focusMap(on: location)
            await search(from: location)
        } catch {
            guard autocompleteRevision == revision else { return }
            locationSearchState = .error("Unable to find this location. Try searching again.")
        }
    }

    func useCurrentLocation() async {
        guard let userLocation else { return }
        cancelLocationSearch()
        selectedSearchLocation = nil
        didInitialSearch = true
        focusMap(on: userLocation)
        await search(from: userLocation)
    }

    private func focusMap(on location: CLLocation) {
        select(nil)
        mapCenter = location
        mapFocusRevision += 1
    }

    private func reconcileSelection() {
        if let id = selectedRestroomID, !filteredRestrooms.contains(where: { $0.id == id }) {
            selectedRestroomID = nil
        }
    }

    private func isValid(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0 && CLLocationCoordinate2DIsValid(location.coordinate)
    }
}
