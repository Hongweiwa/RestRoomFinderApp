import CoreLocation
import Foundation

@MainActor
private final class FakeLocationPlacesService: NearbyRestroomSearching, LocationSearching {
    struct Call { let query: String; let bias: CLLocationCoordinate2D?; let sessionID: UUID }
    var calls: [Call] = []
    var detailSessions: [UUID] = []
    var endedSessions: [UUID] = []
    var nearbyCenters: [CLLocationCoordinate2D] = []
    var suggestions: [LocationPrediction] = []
    var nearbyResults: [Restroom] = []
    var destination = SearchLocation(id: "boston", name: "Boston Common", address: "Boston, MA",
                                     coordinate: CLLocationCoordinate2D(latitude: 42.355, longitude: -71.065))
    var failAutocomplete = false
    var failDetails = false
    var suspendAutocomplete = false
    var suspendDetails = false
    var suspendNearby = false
    var pendingAutocomplete: [String: CheckedContinuation<[LocationPrediction], Error>] = [:]
    var pendingDetails: CheckedContinuation<SearchLocation, Error>?
    var pendingNearby: [Double: CheckedContinuation<[Restroom], Error>] = [:]

    func autocomplete(query: String, bias: CLLocationCoordinate2D?, sessionID: UUID) async throws -> [LocationPrediction] {
        calls.append(Call(query: query, bias: bias, sessionID: sessionID))
        if failAutocomplete { throw NSError(domain: "AutocompleteTest", code: 1) }
        if suspendAutocomplete {
            return try await withCheckedThrowingContinuation { pendingAutocomplete[query] = $0 }
        }
        return suggestions
    }
    func resolveLocation(_ prediction: LocationPrediction, sessionID: UUID) async throws -> SearchLocation {
        detailSessions.append(sessionID)
        if failDetails { throw NSError(domain: "DetailsTest", code: 1) }
        if suspendDetails { return try await withCheckedThrowingContinuation { pendingDetails = $0 } }
        return destination
    }
    func endAutocompleteSession(_ sessionID: UUID) { endedSessions.append(sessionID) }
    func searchNearbyRestrooms(latitude: Double, longitude: Double, radius: Double) async throws -> [Restroom] {
        nearbyCenters.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        if suspendNearby { return try await withCheckedThrowingContinuation { pendingNearby[longitude] = $0 } }
        return nearbyResults
    }
}

@MainActor
struct LocationSearchTests {
    private static func eventually(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        preconditionFailure("Timed out waiting for test operation")
    }

    static func run() async {
        let origin = CLLocation(latitude: 40.7536, longitude: -73.9832)
        let service = FakeLocationPlacesService()
        let prediction = LocationPrediction(id: "boston", primaryText: "Boston Common", secondaryText: "Boston, MA")
        service.suggestions = [prediction]
        let vm = NearbyRestroomsViewModel(service: service, debounce: .milliseconds(20))
        await vm.searchInitially(from: origin)
        vm.searchText = "B"
        vm.searchText = "Bo"
        try? await Task.sleep(for: .milliseconds(30))
        precondition(service.calls.isEmpty)
        vm.searchText = "Bos"
        vm.searchText = "Bost"
        vm.searchText = "Boston"
        await eventually { vm.locationSearchState == .suggestions }
        precondition(service.calls.count == 1 && service.calls[0].query == "Boston")
        precondition(service.nearbyCenters.count == 1 && service.detailSessions.isEmpty, "Typing only calls Autocomplete")
        precondition(service.calls[0].bias?.longitude == origin.coordinate.longitude)
        let session = service.calls[0].sessionID
        vm.searchText = "Boston Common"
        await eventually { service.calls.count == 2 && vm.locationSearchState == .suggestions }
        precondition(service.calls[1].sessionID == session, "Reuse one session across queries")
        vm.searchText = " Boston Common "
        try? await Task.sleep(for: .milliseconds(30))
        precondition(service.calls.count == 2, "Whitespace-only changes don't repeat requests")

        let records = [PlaceRecord(placeID: "toilet", name: "Public Restroom", latitude: 42.356, longitude: -71.065,
                                   address: "Boston", rating: 4.8, ratingCount: 10)]
        service.nearbyResults = RestroomPlaceMapper.map(records, from: origin)
        vm.updateFilter(RestroomFilter(minimumGoogleRating: 4, sortOption: .highestRated))
        await vm.selectLocationPrediction(prediction)
        precondition(service.detailSessions == [session] && service.endedSessions.contains(session))
        precondition(service.nearbyCenters.count == 2 && vm.searchText.isEmpty && vm.predictions.isEmpty)
        precondition(vm.searchCenter?.coordinate.latitude == 42.355 && vm.mapCenter?.coordinate.latitude == 42.355)
        precondition(vm.userLocation?.coordinate.longitude == origin.coordinate.longitude && vm.mapFocusRevision == 1)
        precondition(vm.filteredRestrooms.count == 1 && (vm.filteredRestrooms[0].distance ?? 0) > 100_000)
        precondition(vm.filter.minimumGoogleRating == 4 && vm.filter.sortOption == .highestRated)
        await vm.selectLocationPrediction(prediction)
        precondition(service.detailSessions.count == 1, "Double taps don't fetch twice")
        let retained = vm.allRestrooms
        vm.searchText = "Back Bay"
        await eventually { vm.locationSearchState == .suggestions }
        precondition(service.calls.last?.sessionID != session && service.calls.last?.bias?.latitude == 42.355)
        vm.searchText = ""
        precondition(vm.predictions.isEmpty && vm.allRestrooms == retained && vm.searchCenter?.coordinate.latitude == 42.355)
        print("PASS: debounce/minimum length, duplicate query prevention, tokens reused/reset, bias priority, details only after selection, actual distances, filters retained")

        service.suspendAutocomplete = true
        vm.searchText = "Old query"
        await eventually { service.pendingAutocomplete["Old query"] != nil }
        vm.searchText = "New query"
        await eventually { service.pendingAutocomplete["New query"] != nil }
        let latest = LocationPrediction(id: "new", primaryText: "New result", secondaryText: nil)
        service.pendingAutocomplete.removeValue(forKey: "New query")?.resume(returning: [latest])
        await eventually { vm.predictions == [latest] }
        service.pendingAutocomplete.removeValue(forKey: "Old query")?.resume(returning: [prediction])
        try? await Task.sleep(for: .milliseconds(20))
        precondition(vm.predictions == [latest], "Late responses must not replace the latest query")
        vm.searchText = "Cancelled query"
        await eventually { service.pendingAutocomplete["Cancelled query"] != nil }
        vm.cancelLocationSearch()
        service.pendingAutocomplete.removeValue(forKey: "Cancelled query")?.resume(returning: [prediction])
        try? await Task.sleep(for: .milliseconds(20))
        precondition(vm.predictions.isEmpty && vm.locationSearchState == .idle && vm.allRestrooms == retained)
        service.suspendAutocomplete = false
        service.failAutocomplete = true
        vm.searchText = "Failure"
        await eventually { if case .error = vm.locationSearchState { return true }; return false }
        precondition(vm.allRestrooms == retained && service.nearbyCenters.count == 2)
        service.failAutocomplete = false
        service.suggestions = []
        vm.retryLocationSearch()
        await eventually { vm.locationSearchState == .empty }
        precondition(vm.state == .loaded && vm.allRestrooms == retained, "No locations differs from no restrooms")
        print("PASS: late query responses ignored, clear/cancel preserves results, autocomplete failure and empty states")

        service.suggestions = [prediction]
        vm.searchText = "Boston Common"
        await eventually { vm.locationSearchState == .suggestions }
        service.failDetails = true
        await vm.selectLocationPrediction(prediction)
        precondition(vm.allRestrooms == retained && service.nearbyCenters.count == 2)
        service.failDetails = false
        vm.retryLocationSearch()
        await eventually { vm.locationSearchState == .suggestions }
        service.suspendDetails = true
        let resolving = Task { await vm.selectLocationPrediction(prediction) }
        await eventually { service.pendingDetails != nil }
        vm.cancelLocationSearch()
        service.pendingDetails?.resume(returning: service.destination)
        service.pendingDetails = nil
        await resolving.value
        service.suspendDetails = false
        precondition(vm.locationSearchState == .idle && service.nearbyCenters.count == 2)
        await vm.useCurrentLocation()
        precondition(vm.searchCenter?.coordinate.longitude == origin.coordinate.longitude && vm.selectedSearchLocation == nil)
        precondition(service.nearbyCenters.count == 3 && vm.filter.minimumGoogleRating == 4)
        vm.mapDidMove(to: CLLocationCoordinate2D(latitude: 42.36, longitude: -71.09))
        await vm.searchThisArea()
        precondition(service.nearbyCenters.last?.longitude == -71.09 && vm.userLocation?.coordinate.latitude == origin.coordinate.latitude)
        print("PASS: detail failure/cancellation, current-location shortcut, Search this area and filter compatibility")

        service.suspendNearby = true
        let old = Task { await vm.search(from: CLLocation(latitude: 42, longitude: -70)) }
        await eventually { service.pendingNearby[-70] != nil }
        let new = Task { await vm.search(from: CLLocation(latitude: 43, longitude: -69)) }
        await eventually { service.pendingNearby[-69] != nil }
        service.pendingNearby.removeValue(forKey: -69)?.resume(returning: [])
        await new.value
        service.pendingNearby.removeValue(forKey: -70)?.resume(returning: retained)
        await old.value
        precondition(vm.state == .empty && vm.allRestrooms.isEmpty && vm.searchCenter?.coordinate.longitude == -69)
        service.suspendNearby = false
        let noGPS = NearbyRestroomsViewModel(service: service, debounce: .milliseconds(1))
        noGPS.searchText = "Boston"
        await eventually { noGPS.locationSearchState == .suggestions }
        await noGPS.selectLocationPrediction(prediction)
        precondition(noGPS.userLocation == nil && noGPS.allRestrooms.allSatisfy { $0.distance == nil })
        let count = service.nearbyCenters.count
        await noGPS.searchInitially(from: origin)
        precondition(service.nearbyCenters.count == count && noGPS.searchCenter?.coordinate.latitude == 42.355)
        precondition(noGPS.allRestrooms.allSatisfy { ($0.distance ?? 0) > 100_000 })
        print("PASS: newer nearby searches win, location search without GPS, late GPS never replaces chosen destination")
    }
}
