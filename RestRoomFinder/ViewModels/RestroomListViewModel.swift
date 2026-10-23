import Combine
import Foundation

@MainActor
final class RestroomListViewModel: ObservableObject {
    @Published private(set) var restrooms: [Restroom] = []
    @Published var searchText = ""
    @Published var openNowOnly = false
    @Published var accessibleOnly = false
    @Published var cleanOnly = false
    @Published var freeOnly = false
    let currentLocation = "Midtown Manhattan, New York"

    var visibleRestrooms: [Restroom] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return restrooms.filter {
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.address.localizedCaseInsensitiveContains(query)) &&
            (!openNowOnly || $0.isOpenNow == true) && (!accessibleOnly || $0.accessibility == true) &&
            (!cleanOnly || ($0.cleanlinessRating ?? -1) >= 4.5) && (!freeOnly || $0.free == true)
        }
    }

    func resetFilters() {
        openNowOnly = false
        accessibleOnly = false
        cleanOnly = false
        freeOnly = false
    }

    private let service: any RestroomService

    init(service: any RestroomService) {
        self.service = service
        loadRestrooms()
    }

    func loadRestrooms() {
        restrooms = service.fetchRestrooms()
    }
}
