import SwiftUI

/// Owns navigation and creates dependencies once for this scene.
struct RootView: View {
    @StateObject private var reports = MyReportsViewModel(service: ReportService())
    @StateObject private var submissions = MySubmissionsViewModel(service: RestroomSubmissionService())
    @StateObject private var reviews = ReviewsViewModel(service: ReviewService(), places: PlacesService())
    @StateObject private var favorites = FavoritesViewModel(service: FavoritesService(), places: PlacesService())
    @StateObject private var auth = AuthViewModel(service: AuthService())
    @StateObject private var viewModel = NearbyRestroomsViewModel(service: PlacesService())
    @StateObject private var locationManager = LocationManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(viewModel: viewModel, locationManager: locationManager)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .restroomDetail(let id):
                        if let restroom = viewModel.allRestrooms.first(where: { $0.id == id }) {
                            RestroomDetailView(restroom: restroom)
                        } else {
                            ContentUnavailableView("Restroom unavailable", systemImage: "mappin.slash")
                        }
                    }
                }
        }
        .environmentObject(auth)
        .environmentObject(favorites)
        .environmentObject(reviews)
        .environmentObject(submissions)
        .environmentObject(reports)
        .environmentObject(locationManager)
        .onReceive(viewModel.$allRestrooms) { submissions.register($0) }
        .onReceive(reviews.$summaries) { viewModel.applyRatings($0) }
        .task(id: viewModel.allRestrooms.map(\.reviewKey).sorted().joined(separator: "|") + ":\(reviews.changeRevision):\(viewModel.discoveryRevision)") {
            await reviews.refreshSummaries(for: viewModel.allRestrooms)
        }
        .onChange(of: auth.state) { _, state in favorites.setUser(state.user); reviews.setUser(state.user); submissions.setUser(state.user); reports.setUser(state.user) }
        .task(id: auth.state) { await favorites.load(user: auth.state.user) }
        .task { auth.start() }
        .onOpenURL { url in Task { await auth.handleCallback(url) } }
        .alert("Account", isPresented: Binding(get: { auth.callbackMessage != nil }, set: { if !$0 { auth.callbackMessage = nil } })) {
            Button("OK", role: .cancel) { auth.callbackMessage = nil }
        } message: { Text(auth.callbackMessage ?? "") }
        .onAppear { requestLocation() }
        .onDisappear { locationManager.stop() }
        .onReceive(locationManager.$location) { location in
            let authorizedLocation = locationManager.isAuthorized ? location : nil
            favorites.setLocation(authorizedLocation)
            Task { await viewModel.searchInitially(from: authorizedLocation) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { requestLocation(); Task { await auth.refreshSession(); await favorites.load(user: auth.state.user, force: true); await reviews.refreshSummaries(for: viewModel.allRestrooms) } } else { locationManager.stop(); viewModel.cancelLocationSearch() }
        }
        .tint(AppTheme.foreground)
        .foregroundStyle(AppTheme.foreground)
        .background(AppTheme.background)
    }
    private func requestLocation() {
        if GoogleMapsConfiguration.isConfigured { locationManager.requestLocation() }
    }
}

#Preview {
    RootView()
}
