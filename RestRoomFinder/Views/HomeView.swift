import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var reviews: ReviewsViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @State private var showProfile = false
    @State private var showSaved = false
    @ObservedObject var viewModel: NearbyRestroomsViewModel
    @ObservedObject var locationManager: LocationManager
    @State private var directionsRestroom: Restroom?
    @State private var showFilters = false
    @State private var showMap = false
    @State private var notice: String?
    @State private var searchID = UUID()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    Label(viewModel.userLocation == nil ? "Location unavailable" : "Distances from your current location", systemImage: "location.fill")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.secondary)
                    HStack(spacing: AppTheme.Spacing.small) {
                        SearchBar(text: $viewModel.searchText, placeholder: "Search location…", focusRequest: searchID, surface: AppTheme.background, compact: true,
                                  dismissFocusRequest: viewModel.searchDismissRevision)
                        SecondaryButton(title: viewModel.filterButtonTitle, systemImage: "slider.horizontal.3", cornerRadius: AppTheme.Radius.compact, compact: true) {
                            showFilters = true
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("home-filter")
                    }
                    LocationSearchSuggestions(viewModel: viewModel)
                    if let location = viewModel.selectedSearchLocation { SearchAreaSummary(location: location) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.small) {
                            FilterChip(title: "OPEN NOW", showsCheckmark: false, compact: true, isSelected: .constant(false)).disabled(true)
                            FilterChip(title: "ACCESSIBLE", showsCheckmark: false, compact: true, isSelected: .constant(false)).disabled(true)
                            FilterChip(title: "CLEAN 4+", showsCheckmark: false, compact: true, isSelected: Binding(
                                get: { viewModel.filter.minimumCleanlinessRating != nil },
                                set: { enabled in var filter = viewModel.filter; filter.minimumCleanlinessRating = enabled ? 4 : nil; viewModel.updateFilter(filter) }))
                            FilterChip(title: "FREE", showsCheckmark: false, compact: true, isSelected: .constant(false)).disabled(true)
                        }
                    }
                    if let message = reviews.summaryError {
                        Text(message).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                        Button("Retry ratings") { Task { await reviews.refreshSummaries(for: viewModel.allRestrooms) } }
                    }
                    HStack {
                        SectionHeader(title: "NEARBY FACILITIES", isEyebrow: true)
                        HStack(spacing: 0) {
                            Label("LIST", systemImage: "list.bullet")
                                .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                                .padding(.horizontal, AppTheme.Spacing.small)
                                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact))
                            Button { showMap = true } label: {
                                Label("MAP", systemImage: "map.fill")
                                    .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                                    .padding(.horizontal, AppTheme.Spacing.small)
                            }
                        }
                        .font(AppTheme.Typography.badge)
                        .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                        .padding(AppTheme.Spacing.xs)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                    }
                    DiscoveryStatusView(viewModel: viewModel, locationManager: locationManager)
                    NearbyRestroomCards(viewModel: viewModel) { restroom in
                        directionsRestroom = restroom
                    }
                    HStack {
                        Spacer()
                        locationControls
                    }
                    Text("Place information from Google Maps · Amenities may be unknown.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.secondary)
                }
                .padding(AppTheme.Spacing.large)
                .padding(.bottom, AppTheme.Metrics.symbolSize)
            }
            .onChange(of: viewModel.selectionRevision) { _, _ in
                if let id = viewModel.selectedRestroomID { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .onChange(of: viewModel.mapFocusRevision) { _, _ in showMap = true }
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.canvas)
        .appScreenStyle()
        .navigationTitle("LOOFINDER")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { searchID = UUID() } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search location")
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("About this preview") { notice = "Nearby public restrooms from Google Places." }
                } label: { Image(systemName: "line.3.horizontal") }
                .accessibilityLabel("Menu")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sheet(item: $directionsRestroom) { DirectionsView(restroom: $0) }
        .sheet(isPresented: $showFilters) { RestroomFilterView(viewModel: viewModel) }
        .sheet(isPresented: $showMap) { RestroomMapView(viewModel: viewModel, locationManager: locationManager) }
        .fullScreenCover(isPresented: $showSaved) { SavedRestroomsScreen() }
        .fullScreenCover(isPresented: $showProfile) { ProfileView().environmentObject(auth) }
        .alert("Preview", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
    }

    private var locationControls: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Button {
                if let restroom = viewModel.selectedRestroom { directionsRestroom = restroom }
                else { notice = "Select a restroom to get directions." }
            } label: {
                Image(systemName: "arrow.turn.up.right")
                    .frame(width: AppTheme.Metrics.minimumTapTarget, height: AppTheme.Metrics.minimumTapTarget)
            }
            .accessibilityLabel("Get directions to selected restroom")
            Button {
                if viewModel.userLocation != nil {
                    Task { await viewModel.useCurrentLocation() }
                } else {
                    locationManager.requestLocation()
                    showMap = true
                }
            } label: {
                Image(systemName: "scope")
                    .font(AppTheme.Typography.title)
                    .frame(width: AppTheme.Metrics.symbolSize, height: AppTheme.Metrics.symbolSize)
            }
            .accessibilityLabel("Use current location")
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.background)
        .background(AppTheme.foreground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
    }

    private var bottomBar: some View {
        AppBottomBar(onFind: {},
                     onSaved: { showSaved = true },
                     onProfile: { showProfile = true })
    }

}

#Preview { RootView() }
