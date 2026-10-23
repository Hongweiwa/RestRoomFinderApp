import SwiftUI

struct RestroomMapView: View {
    @ObservedObject var viewModel: NearbyRestroomsViewModel
    @ObservedObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var directionsRestroom: Restroom?
    @State private var showFilters = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if GoogleMapsConfiguration.isConfigured {
                        GoogleMapView(restrooms: viewModel.filteredRestrooms, location: viewModel.userLocation,
                                      showsUserLocation: locationManager.isAuthorized && scenePhase == .active,
                                      selectedRestroomID: viewModel.selectedRestroomID,
                                      initialCenter: viewModel.mapCenter ?? viewModel.searchCenter,
                                      recenterRequest: viewModel.mapFocusRevision,
                                      onSelect: viewModel.select, onCameraIdle: viewModel.mapDidMove,
                                      onUseCurrentLocation: { Task { await viewModel.useCurrentLocation() } })
                            .frame(height: geometry.size.height * 0.45)
                            .overlay(alignment: .top) {
                                if viewModel.canSearchThisArea {
                                    SecondaryButton(title: "Search this area", systemImage: "magnifyingglass", compact: true) {
                                        Task { await viewModel.searchThisArea() }
                                    }
                                    .fixedSize()
                                    .disabled(viewModel.state == .loading)
                                    .padding(AppTheme.Spacing.small)
                                    .accessibilityIdentifier("search-this-area")
                                }
                            }
                    } else {
                        ContentUnavailableView("Google Maps needs an API key", systemImage: "map")
                    }
                    if let location = viewModel.selectedSearchLocation {
                        SearchAreaSummary(location: location).padding(.horizontal, AppTheme.Spacing.large)
                    }
                    HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                        DiscoveryStatusView(viewModel: viewModel, locationManager: locationManager)
                        SecondaryButton(title: viewModel.filterButtonTitle, systemImage: "slider.horizontal.3",
                                        cornerRadius: AppTheme.Radius.compact, compact: true) { showFilters = true }
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityIdentifier("map-filter")
                    }
                    .padding(AppTheme.Spacing.large)
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: AppTheme.Spacing.large) {
                                NearbyRestroomCards(viewModel: viewModel) { directionsRestroom = $0 }
                            }
                            .padding(AppTheme.Spacing.large)
                        }
                        .onChange(of: viewModel.selectionRevision) { _, _ in
                            if let id = viewModel.selectedRestroomID { withAnimation { proxy.scrollTo(id, anchor: .top) } }
                        }
                        .onAppear {
                            if let id = viewModel.selectedRestroomID { proxy.scrollTo(id, anchor: .top) }
                        }
                    }
                }
            }
            .appScreenStyle()
            .navigationTitle("Restroom Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .restroomDetail(let id):
                    if let restroom = viewModel.allRestrooms.first(where: { $0.id == id }) {
                        RestroomDetailView(restroom: restroom)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await viewModel.useCurrentLocation() } } label: { Image(systemName: "location.fill") }
                        .accessibilityLabel("Use current location")
                        .disabled(viewModel.userLocation == nil)
                }
            }
            .sheet(isPresented: $showFilters) { RestroomFilterView(viewModel: viewModel) }
            .sheet(item: $directionsRestroom) { DirectionsView(restroom: $0) }
        }
    }
}
