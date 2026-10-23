import SwiftUI

/// Shared permission/search feedback, with no fetching logic in the view.
struct DiscoveryStatusView: View {
    @ObservedObject var viewModel: NearbyRestroomsViewModel
    @ObservedObject var locationManager: LocationManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            if !GoogleMapsConfiguration.isConfigured {
                Text("Set GOOGLE_MAPS_API_KEY in Configuration/Secrets.xcconfig, then rebuild.")
            } else {
                switch locationManager.state {
                case .notDetermined:
                    Text("Allow location access for distances from you, or search a location.")
                    SecondaryButton(title: "Allow location") { locationManager.requestLocation() }
                case .locating:
                    HStack { ProgressView(); Text("Finding your location…") }
                case .denied:
                    Text("Allow location access in Settings for distances from you. You can still search a location.")
                    SecondaryButton(title: "Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                case .restricted:
                    Text("Location access is restricted on this device.")
                case .unavailable:
                    Text("Your location is unavailable. Check Location Services or try again.")
                    SecondaryButton(title: "Try again") { locationManager.requestLocation() }
                case .available:
                    EmptyView()
                }
                if locationManager.state == .available || viewModel.state != .idle { searchStatus }
            }
        }
        .font(AppTheme.Typography.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var searchStatus: some View {
        switch viewModel.state {
        case .idle: Text("Waiting to search near your location.")
        case .loading: HStack { ProgressView(); Text("Searching for nearby restrooms…") }
        case .loaded:
            resultsStatus
        case .empty:
            Text("No public restrooms found in this area.")
        case .error(let message):
            Text(message)
            if !viewModel.allRestrooms.isEmpty { resultsStatus }
            SecondaryButton(title: "Try again") { Task { await viewModel.retry() } }
        }
    }

    private var resultsStatus: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("\(viewModel.filteredRestrooms.count) restrooms · \(viewModel.filter.sortOption.rawValue)")
            if viewModel.filteredRestrooms.isEmpty {
                Text("No restrooms match your filters.")
                if viewModel.filter.activeCount > 0 {
                    SecondaryButton(title: "Clear Filters") { viewModel.resetFilters() }
                }
            }
        }
    }
}
