import CoreLocation
import Foundation

@MainActor
private final class FakePlacesService: NearbyRestroomSearching {
    var calls = 0
    var requestedLatitude: Double?
    var requestedLongitude: Double?
    var result: Result<[Restroom], Error> = .success([])
    var pending: CheckedContinuation<[Restroom], Error>?
    var suspend = false
    func searchNearbyRestrooms(latitude: Double, longitude: Double, radius: Double) async throws -> [Restroom] {
        calls += 1
        requestedLatitude = latitude
        requestedLongitude = longitude
        if suspend {
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        return try result.get()
    }
}

@main
struct NearbyDiscoveryTests {
    @MainActor static func main() async {
        await AuthenticationTests.run()
        await ProfileTests.run()
        await FavoritesTests.run()
        await ReviewTests.run()
        await SubmissionTests.run()
        await ReportTests.run()
        SupabaseConfigurationTests.run()
        await DirectionsTests.run()
        let origin = CLLocation(latitude: 0, longitude: 0)
        let record = PlaceRecord(placeID: "one", name: "Public bathroom", latitude: 0, longitude: 0.01,
                                 address: "Test address", types: ["public_bathroom"], businessStatus: .operational,
                                 rating: 4.5, ratingCount: 12)
        let closer = PlaceRecord(placeID: "two", name: "Public bathroom", latitude: 0, longitude: 0.005, address: nil)
        let invalid = PlaceRecord(placeID: "invalid", name: nil, latitude: 100, longitude: 0, address: nil)
        let missingID = PlaceRecord(placeID: nil, name: nil, latitude: 0, longitude: 0, address: nil)
        let mapped = RestroomPlaceMapper.map([record, closer, record, invalid, missingID], from: origin)
        precondition(mapped.count == 2 && Set(mapped.compactMap(\.googlePlaceID)).count == 2)
        precondition(mapped[0].googlePlaceID == "two", "Sort by distance; equal names must stay distinct")
        precondition(abs((mapped[1].distance ?? 0) - 1113.2) < 5, "CoreLocation distance in meters")
        precondition(mapped[1].id == RestroomPlaceMapper.map([record], from: origin)[0].id)
        precondition(mapped[1].googleRating == 4.5 && mapped[1].googleUserRatingCount == 12)
        precondition(mapped.allSatisfy { $0.cleanlinessRating == nil && $0.accessibility == nil &&
            $0.babyChangingStation == nil && $0.genderNeutral == nil && $0.free == nil &&
            $0.overallRating == nil && $0.reviewCount == nil && $0.isOpenNow == nil && $0.openingHours == nil })
        print("PASS: mapping, unique IDs, distance, stable routes, unknown attributes")

        // Details use the selected coordinate, not the search center or Google ID.
        let directions = DirectionsService.appleMapsURL(destination: mapped[1].coordinate)
        guard let directions, let components = URLComponents(url: directions, resolvingAgainstBaseURL: false) else {
            fatalError("Expected valid Apple Maps URL")
        }
        let parameters = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        precondition(components.host == "maps.apple.com" && components.scheme == "https")
        precondition(parameters["daddr"] == "0.0,0.01" && parameters["dirflg"] == "w")
        precondition(parameters["saddr"] == nil, "Apple Maps chooses current origin, never map search center")
        precondition(DirectionsService.appleMapsURL(destination: CLLocationCoordinate2D(latitude: 100, longitude: 0)) == nil)
        precondition(DirectionsService.appleMapsURL(destination: CLLocationCoordinate2D(latitude: .nan, longitude: 0)) == nil)
        var missing = mapped[0]
        missing.googlePlaceID = nil
        missing.distance = nil
        precondition(missing.distanceDescription == "Distance unavailable")
        precondition(DirectionsService.appleMapsURL(destination: missing.coordinate) != nil, "Directions do not require Google ID")
        missing.distance = .infinity
        precondition(missing.distanceDescription == "Distance unavailable")
        missing.businessStatus = .operational
        precondition(missing.availabilityDescription == "Hours unknown", "Operational is not Open now")
        missing.businessStatus = .temporarilyClosed
        precondition(missing.availabilityDescription == "Temporarily closed")
        print("PASS: Details directions destination, missing Google ID/distance, invalid coordinates, honest opening status")

        var date = Date()
        let service = FakePlacesService()
        service.result = .success(mapped)
        let vm = NearbyRestroomsViewModel(service: service, now: { date })
        precondition(vm.state == .idle && vm.allRestrooms.isEmpty)
        await vm.searchInitially(from: nil)
        await vm.searchInitially(from: CLLocation(coordinate: origin.coordinate, altitude: 0,
                                                 horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: date))
        precondition(service.calls == 0, "No fix means no Places request")
        service.suspend = true
        let task = Task { await vm.searchInitially(from: origin) }
        while service.pending == nil { await Task.yield() }
        precondition(vm.state == .loading && vm.allRestrooms.isEmpty)
        await vm.search(from: origin)
        precondition(service.calls == 1, "No overlapping requests")
        service.pending?.resume(returning: mapped)
        service.pending = nil
        await task.value
        service.suspend = false
        precondition(vm.state == .loaded && vm.allRestrooms == mapped, "Marker data is exactly service output")
        await vm.searchInitially(from: CLLocation(latitude: 1, longitude: 1))
        await vm.search(from: origin)
        await vm.search(from: CLLocation(latitude: 0, longitude: 0.0001))
        precondition(service.calls == 1, "Initial only once; repeated nearby queries cached")
        date = date.addingTimeInterval(61)
        await vm.search(from: origin)
        precondition(service.calls == 2, "Cache expires")
        await vm.search(from: origin, radius: 1000)
        precondition(service.calls == 3, "Radius is part of search identity")
        print("PASS: no location, loading, loaded, exact marker data, in-flight and nearby request protection")

        let emptyService = FakePlacesService()
        let emptyVM = NearbyRestroomsViewModel(service: emptyService)
        await emptyVM.searchInitially(from: origin)
        precondition(emptyVM.state == .empty && emptyVM.allRestrooms.isEmpty)
        let failureService = FakePlacesService()
        failureService.result = .failure(NSError(domain: "Test", code: 1))
        let failureVM = NearbyRestroomsViewModel(service: failureService)
        await failureVM.searchInitially(from: origin)
        guard case .error = failureVM.state else { fatalError("Expected error state") }
        precondition(failureVM.allRestrooms.isEmpty, "No mock fallback on error")
        failureService.result = .success(mapped)
        await failureVM.search(from: origin)
        precondition(failureVM.state == .loaded && failureService.calls == 2, "Failed request can retry immediately")
        print("PASS: empty, error, retry")

        let sharedService = FakePlacesService()
        sharedService.result = .success(mapped)
        let shared = NearbyRestroomsViewModel(service: sharedService)
        await shared.searchInitially(from: origin)
        let selectedID = mapped[1].id
        shared.select(selectedID)
        precondition(shared.selectedRestroom?.googlePlaceID == "one")
        let revision = shared.selectionRevision
        shared.select(selectedID)
        precondition(shared.selectionRevision == revision + 1, "Repeat marker taps still request card scrolling")
        shared.mapDidMove(to: CLLocationCoordinate2D(latitude: 0, longitude: 1))
        precondition(sharedService.calls == 1 && shared.canSearchThisArea, "Panning never fetches")
        sharedService.suspend = true
        let areaTask = Task { await shared.searchThisArea() }
        while sharedService.pending == nil { await Task.yield() }
        precondition(shared.state == .loading && shared.allRestrooms == mapped, "Keep old markers/cards while loading")
        await shared.searchThisArea()
        precondition(sharedService.calls == 2)
        sharedService.pending?.resume(returning: [mapped[1], mapped[1], mapped[0]])
        sharedService.pending = nil
        await areaTask.value
        sharedService.suspend = false
        precondition(sharedService.requestedLongitude == 1 && shared.searchCenter?.coordinate.longitude == 1)
        precondition(shared.userLocation?.coordinate.longitude == 0, "Search center never becomes user location")
        precondition(shared.allRestrooms == mapped && shared.selectedRestroomID == selectedID,
                     "Dedup, sort from actual user, and preserve selection across reordered results")
        shared.mapDidMove(to: CLLocationCoordinate2D(latitude: 0, longitude: 2))
        sharedService.result = .failure(NSError(domain: "Test", code: 2))
        await shared.searchThisArea()
        guard case .error = shared.state else { fatalError("Expected area failure") }
        precondition(shared.allRestrooms == mapped && shared.selectedRestroomID == selectedID)
        sharedService.result = .success([mapped[0]])
        await shared.retry()
        precondition(sharedService.requestedLongitude == 2 && shared.selectedRestroom == nil,
                     "Retry failed center; remove stale selection")
        shared.select(mapped[0].id)
        shared.searchText = "no-match"
        precondition(!shared.filteredRestrooms.isEmpty && shared.selectedRestroom != nil, "Location queries do not filter restroom names")
        shared.searchText = ""
        shared.mapDidMove(to: CLLocationCoordinate2D(latitude: 0, longitude: 3))
        sharedService.result = .success([])
        await shared.searchThisArea()
        precondition(shared.state == .empty && shared.allRestrooms.isEmpty)
        shared.updateUserLocation(nil)
        let callCount = sharedService.calls
        await shared.retry()
        precondition(sharedService.calls == callCount && !shared.canSearchThisArea)
        print("PASS: shared selection, repeat selection, manual area search, user-relative distance, preserved results on error, retry center, stale selection and empty replacement")
        await testFilters()
        await LocationSearchTests.run()
    }

    @MainActor static func testFilters() async {
        let origin = CLLocation(latitude: 0, longitude: 0)
        let records = [
            PlaceRecord(placeID: "near", name: "Near", latitude: 0, longitude: 0.005, address: "A", rating: 4.0, ratingCount: 50),
            PlaceRecord(placeID: "far", name: "Far", latitude: 0, longitude: 0.02, address: "B", rating: 4.8, ratingCount: 10),
            PlaceRecord(placeID: "unknown", name: "Unknown", latitude: 0, longitude: 0.009, address: "C"),
            PlaceRecord(placeID: "low", name: "Low", latitude: 0, longitude: 0.001, address: "D", rating: 3.0, ratingCount: 100)
        ]
        let results = RestroomPlaceMapper.map(records, from: origin)
        func ids(_ values: [Restroom]) -> [String] { values.compactMap(\.googlePlaceID) }
        precondition(ids(RestroomFilter(maximumDistanceMiles: 1).apply(to: results)) == ["low", "near", "unknown"])
        precondition(ids(RestroomFilter(minimumGoogleRating: 4).apply(to: results)) == ["near", "far"])
        precondition(ids(RestroomFilter(sortOption: .highestRated).apply(to: results)) == ["far", "near", "low", "unknown"])
        precondition(ids(RestroomFilter(sortOption: .mostReviewed).apply(to: results)) == ["low", "near", "far", "unknown"])
        precondition(ids(RestroomFilter().apply(to: results.reversed())) == ["low", "near", "unknown", "far"])
        var statuses = results
        for index in statuses.indices {
            statuses[index].isOpenNow = statuses[index].googlePlaceID == "near" ? true :
                (statuses[index].googlePlaceID == "far" ? false : nil)
        }
        precondition(ids(RestroomFilter(openNowOnly: true).apply(to: statuses)) == ["near"], "Only confirmed open; unknown is not false or true")
        precondition(ids(RestroomFilter(maximumDistanceMiles: 1, minimumGoogleRating: 4, openNowOnly: true).apply(to: statuses)) == ["near"])
        let nearIndex = statuses.firstIndex { $0.googlePlaceID == "near" }!
        statuses[nearIndex].businessStatus = .temporarilyClosed
        precondition(RestroomFilter(openNowOnly: true).apply(to: statuses).isEmpty, "Business closures override stale open status")
        var boundary = results[0]
        boundary.distance = 1609.344
        precondition(RestroomFilter(maximumDistanceMiles: 1).apply(to: [boundary]).count == 1)
        for distance in [Double.nan, .infinity, -1] {
            boundary.distance = distance
            precondition(RestroomFilter(maximumDistanceMiles: 1).apply(to: [boundary]).isEmpty)
        }
        boundary.distance = nil
        boundary.googleRating = .nan
        precondition(RestroomFilter(minimumGoogleRating: 3).apply(to: [boundary]).isEmpty)
        precondition(RestroomFilter().apply(to: [boundary]).count == 1, "Any includes missing data")
        print("PASS: distance boundaries, Google thresholds, unknown/invalid values, tri-state opening, all sort options, combined filters")

        let service = FakePlacesService()
        service.result = .success(results)
        let vm = NearbyRestroomsViewModel(service: service)
        await vm.searchInitially(from: origin)
        let original = vm.allRestrooms
        let near = results.first { $0.googlePlaceID == "near" }!
        vm.select(near.id)
        var draft = vm.filter
        draft.minimumGoogleRating = 4
        precondition(vm.filter.minimumGoogleRating == nil && vm.filteredRestrooms.count == 4, "Draft edits don't commit")
        vm.updateFilter(draft)
        precondition(vm.selectedRestroomID == near.id && vm.filteredRestrooms.count == 2)
        draft.minimumGoogleRating = 4.5
        vm.updateFilter(draft)
        precondition(vm.selectedRestroomID == nil && vm.filteredRestrooms.count == 1)
        vm.updateFilter(RestroomFilter(maximumDistanceMiles: 0.5, minimumGoogleRating: 4.5))
        precondition(vm.state == .loaded && vm.filteredRestrooms.isEmpty && vm.hasNoFilterMatches)
        precondition(vm.filter.activeCount == 2 && vm.filterButtonTitle == "Filter (2)")
        vm.resetFilters()
        precondition(vm.allRestrooms == original && vm.filteredRestrooms == original && vm.filter == RestroomFilter())
        precondition(service.calls == 1, "Filtering, sorting, and reset must not call Places")
        vm.updateFilter(RestroomFilter(maximumDistanceMiles: 1, minimumGoogleRating: 4))
        vm.mapDidMove(to: CLLocationCoordinate2D(latitude: 0, longitude: 1))
        service.result = .success(Array(results.reversed()))
        await vm.searchThisArea()
        precondition(service.calls == 2 && ids(vm.filteredRestrooms) == ["near"])
        precondition(vm.filter.maximumDistanceMiles == 1 && vm.filter.minimumGoogleRating == 4)
        precondition(vm.allRestrooms == original, "Distance must use actual user, not distant search center")
        vm.select(near.id)
        vm.updateUserLocation(nil)
        precondition(vm.filteredRestrooms.isEmpty && vm.selectedRestroomID == nil)
        precondition(vm.allRestrooms.allSatisfy { $0.distance == nil })
        vm.updateUserLocation(origin)
        precondition(ids(vm.filteredRestrooms) == ["near"] && service.calls == 2)
        vm.searchText = "no match"
        precondition(ids(vm.filteredRestrooms) == ["near"] && !vm.hasNoFilterMatches, "Location typing leaves restroom filters unchanged")
        vm.resetFilters()
        precondition(vm.searchText == "no match", "Reset preserves independent search text")
        vm.searchText = ""
        precondition(vm.filteredRestrooms == original)
        vm.updateFilter(RestroomFilter(sortOption: .highestRated))
        precondition(vm.filter.activeCount == 0 && ids(vm.filteredRestrooms).first == "far")
        vm.updateUserLocation(CLLocation(latitude: 0, longitude: 0.02))
        precondition(ids(vm.filteredRestrooms).first == "far" && vm.filter.sortOption == .highestRated)
        vm.mapDidMove(to: CLLocationCoordinate2D(latitude: 0, longitude: 2))
        service.result = .success([])
        await vm.searchThisArea()
        precondition(vm.state == .empty && !vm.hasNoFilterMatches && vm.filter.sortOption == .highestRated)
        print("PASS: draft isolation, original results retained, reset, counts, selection reconciliation, filters persist across areas, no local API calls, location loss/recovery, empty-state distinction")
    }

}
