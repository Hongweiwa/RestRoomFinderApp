import CoreLocation
import SwiftUI

/// Screenshot-based detail layout, using the existing selected result without enrichment calls.
struct RestroomDetailView: View {
    @EnvironmentObject private var reviews: ReviewsViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @State private var showProfile = false
    @State private var showSaved = false
    let restroom: Restroom
    var placeAttributions: NSAttributedString? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var notice: String?
    @State private var showDirections = false
    @State private var reviewScrollRequest = 0

    private var directionsURL: URL? { DirectionsService.appleMapsURL(destination: restroom.coordinate) }
    private var displayName: String {
        restroom.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Public restroom" : restroom.name
    }
    private var displayAddress: String {
        let address = restroom.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? "Address unavailable" : address
    }
    private var googleRating: Double? { validRating(restroom.googleRating) }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.extraLarge) {
                hero
                identity
                ratingsPanel
                mapPreview
                informationTiles
                HStack(spacing: AppTheme.Spacing.medium) {
                    FavoriteButton(restroom: restroom)
                    ReportRestroomButton(restroom: restroom,placeAttributions: placeAttributions)
                }
                RestroomReviewsSection(restroom: restroom).id("restroom-reviews")
                Text("Place information from Google Maps. Amenities and hours may be unverified. Community ratings describe the restroom; Google ratings describe the place.")
                    .font(AppTheme.Typography.badge)
                    .foregroundStyle(AppTheme.secondary)
                if let placeAttributions { Text(AttributedString(placeAttributions)).font(AppTheme.Typography.caption) }
            }
            .padding(AppTheme.Spacing.extraLarge)
        }
        .onChange(of: reviewScrollRequest) { _, _ in
            withAnimation { proxy.scrollTo("restroom-reviews", anchor: .top) }
        }
        }
        .background(AppTheme.canvas)
        .appScreenStyle()
        .navigationTitle("RESTROOM DETAIL")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .frame(width: AppTheme.Metrics.minimumTapTarget, height: AppTheme.Metrics.minimumTapTarget)
                }.accessibilityLabel("Back")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "\(displayName)\n\(displayAddress)\n\(directionsURL?.absoluteString ?? "")") {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: AppTheme.Metrics.minimumTapTarget, height: AppTheme.Metrics.minimumTapTarget)
                }.accessibilityLabel("Share \(displayName)")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
        .task(id: "\(restroom.reviewKey):\(auth.state.user?.id.uuidString ?? "guest"):\(reviews.changeRevision)") {
            reviews.setUser(auth.state.user)
            await reviews.load(restroom)
        }
        .refreshable { await reviews.load(restroom) }
        .sheet(isPresented: $showDirections) { DirectionsView(restroom: restroom) }
        .fullScreenCover(isPresented: $showSaved) { SavedRestroomsScreen() }
        .fullScreenCover(isPresented: $showProfile) { ProfileView().environmentObject(auth) }
        .alert("RestRoom Finder", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
    }

    private var hero: some View {
        Image("DetailHero")
            .resizable().scaledToFill()
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                Text("ILLUSTRATION")
                    .font(AppTheme.Typography.badge)
                    .padding(AppTheme.Spacing.small)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.7), in: Capsule())
                    .padding(AppTheme.Spacing.medium)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(restroom.availabilityDescription.uppercased())
                    .font(AppTheme.Typography.badge)
                    .tracking(1)
                    .padding(.horizontal, AppTheme.Spacing.medium)
                    .padding(.vertical, AppTheme.Spacing.small)
                    .foregroundStyle(.white)
                    .background(.black, in: Capsule())
                    .padding(AppTheme.Spacing.medium)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Illustration of a park restroom, not a photo of this location. \(restroom.availabilityDescription)")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(displayName.uppercased())
                .font(AppTheme.Typography.detailTitle)
                .accessibilityAddTraits(.isHeader)
            Text("\(restroom.distanceDescription)  ·  PUBLIC RESTROOM")
                .font(AppTheme.Typography.secondary)
                .foregroundStyle(AppTheme.secondary)
        }
    }

    private var ratingsPanel: some View {
        adaptiveColumns {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("RESTROOM FINDER")
                    .font(AppTheme.Typography.badge)
                Text(ratingText(reviews.summaries[restroom.reviewKey]?.overallRating))
                    .font(AppTheme.Typography.headline)
                if let rating = googleRating {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Label("Google: \(rating.formatted(.number.precision(.fractionLength(1)))) / 5", systemImage: "star.fill")
                       
                        if let count = restroom.googleUserRatingCount, count > 0 {
                            Text("\(count.formatted()) Google ratings")
                        }
                    }
                    .font(AppTheme.Typography.badge)
                    .foregroundStyle(AppTheme.secondary)
                    .padding(.top, AppTheme.Spacing.small)
                    .accessibilityElement(children: .combine)
                }
                Button("VIEW REVIEWS") { reviewScrollRequest += 1 }
                    .font(AppTheme.Typography.badge).underline()
                    .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                if reviews.entry(for: restroom).state == .loaded {
                    Text(reviews.summaries[restroom.reviewKey]?.countDescription ?? "0 restroom reviews")
                        .font(AppTheme.Typography.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("CLEANLINESS").font(AppTheme.Typography.headline)
                Text(ratingText(reviews.summaries[restroom.reviewKey]?.cleanlinessRating))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.Spacing.large)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
    }

    private var mapPreview: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            if GoogleMapsConfiguration.isConfigured && CLLocationCoordinate2DIsValid(restroom.coordinate) {
                GoogleMapView(restrooms: [restroom], location: nil, showsUserLocation: false,
                              selectedRestroomID: nil,
                              initialCenter: CLLocation(latitude: restroom.latitude, longitude: restroom.longitude),
                              recenterRequest: 0, onSelect: { _ in }, onCameraIdle: { _ in }, isPreview: true)
                    .frame(height: AppTheme.Metrics.detailMapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                    .accessibilityLabel("Map preview of \(displayName)")
            } else {
                Label("Map preview unavailable", systemImage: "map")
                    .frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.detailMapHeight)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
            }
            Text(displayAddress).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                .textSelection(.enabled)
        }
    }

    private var informationTiles: some View {
        adaptiveColumns {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Label("HOURS", systemImage: "clock.fill").font(AppTheme.Typography.eyebrow)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(restroom.availabilityDescription).font(AppTheme.Typography.cardTitle)
                    if let hours = restroom.openingHours, hours != restroom.availabilityDescription {
                        Text(hours).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                    } else if restroom.isOpenNow == nil && restroom.businessStatus == .operational {
                        Text("Opening times unverified").font(AppTheme.Typography.badge).foregroundStyle(AppTheme.secondary)
                    }
                }
            }
            .detailTile()
            NavigationLink { featuresPage } label: {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    Label("FEATURES", systemImage: "figure.roll").font(AppTheme.Typography.eyebrow)
                    HStack(spacing: AppTheme.Spacing.medium) {
                        if restroom.accessibility == true { Image(systemName: "figure.roll").accessibilityLabel("Wheelchair accessible") }
                        if restroom.babyChangingStation == true { Image(systemName: "figure.and.child.holdinghands").accessibilityLabel("Baby changing available") }
                        if restroom.genderNeutral == true { Image(systemName: "person.2").accessibilityLabel("Gender-neutral restroom") }
                        if restroom.free == true { Image(systemName: "banknote").accessibilityLabel("Free entry") }
                        if [restroom.accessibility, restroom.babyChangingStation, restroom.genderNeutral, restroom.free].allSatisfy({ $0 == nil }) {
                            Text("Not yet verified").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                        } else {
                            Image(systemName: "chevron.right").font(AppTheme.Typography.badge)
                        }
                    }
                }
                .detailTile()
            }
            .buttonStyle(.plain)
            .accessibilityHint("View available, unavailable and unverified restroom features")
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 0) {
            PrimaryButton(title: "GET DIRECTIONS", systemImage: "arrow.turn.up.right", iconAtEnd: false) { showDirections = true }
                .accessibilityLabel("Get directions to \(displayName)")
                .accessibilityIdentifier("detail-get-directions")
                .padding(.horizontal, AppTheme.Spacing.extraLarge)
                .padding(.vertical, AppTheme.Spacing.medium)
            AppBottomBar(onFind: { dismiss() },
                         onSaved: { showSaved = true },
                         onProfile: { showProfile = true })
        }
        .background(AppTheme.canvas)
    }

    @ViewBuilder private func adaptiveColumns<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium, content: content)
        } else {
            HStack(alignment: .top, spacing: AppTheme.Spacing.medium, content: content)
        }
    }

    private var featuresPage: some View {
        Form {
            RestroomFeatureRow(title: "Wheelchair accessibility", systemImage: "figure.roll", value: restroom.accessibility)
            RestroomFeatureRow(title: "Baby changing", systemImage: "figure.and.child.holdinghands", value: restroom.babyChangingStation)
            RestroomFeatureRow(title: "Gender-neutral restroom", systemImage: "person.2", value: restroom.genderNeutral)
            RestroomFeatureRow(title: "Entry cost", systemImage: "banknote", value: restroom.free, availableText: "Free", unavailableText: "Paid")
            LabeledContent("RestRoom Finder rating", value: ratingText(reviews.summaries[restroom.reviewKey]?.overallRating))
        }.appScreenStyle().navigationTitle("Restroom Features")
    }

    private func ratingText(_ rating: Double?) -> String {
        switch reviews.entry(for: restroom).state {
        case .idle, .loading: return "Loading…"
        case .error: return "Rating unavailable"
        case .loaded: return rating.map { "\($0.formatted(.number.precision(.fractionLength(1)))) / 5" } ?? "Not rated yet"
        }
    }

    private func validRating(_ rating: Double?) -> Double? {
        guard let rating, rating.isFinite, (0...5).contains(rating) else { return nil }
        return rating
    }


}

private extension View {
    func detailTile() -> some View {
        self.frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.detailTileHeight, alignment: .topLeading)
            .padding(AppTheme.Spacing.large)
            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
    }
}

#Preview("Detail layout") {
    NavigationStack { RestroomDetailView(restroom: SampleRestrooms.all[0]) }
        .environmentObject(AuthViewModel(service: AuthService()))
        .environmentObject(ReviewsViewModel(service: ReviewService(), places: PlacesService()))
        .environmentObject(FavoritesViewModel(service: FavoritesService(), places: PlacesService()))
        .environmentObject(MyReportsViewModel(service: ReportService()))
}
