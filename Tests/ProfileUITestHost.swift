// Standalone simulator-only UI fixture host. Never compiled into RestRoomFinder's app target.
// It renders the actual production views with fake services and never accesses a network or credentials.
import SwiftUI
import CoreLocation

@MainActor
private enum ProfileFixture {
    static let id = UUID(uuidString: "13000000-0000-0000-0000-000000000001")!
    static var name = ProcessInfo.processInfo.arguments.contains("--long")
        ? "Alexandria Catherine Montgomery Wellington-Smythe" : "Alex Morgan"
    static var user: AuthUser {
        AuthUser(id: id, email: ProcessInfo.processInfo.arguments.contains("--long")
            ? "alexandria.montgomery.wellington.test@example.com" : "alex@example.com")
    }
}

@MainActor
final class ProfileService: ProfileServicing {
    func fetchProfile(expectedUserID: UUID) async throws -> AccountProfile {
        if ProcessInfo.processInfo.arguments.contains("--loading") { try await Task.sleep(for: .seconds(120)) }
        if ProcessInfo.processInfo.arguments.contains("--error") { throw ProfileFailure.network }
        return AccountProfile(id: expectedUserID, displayName: ProfileFixture.name)
    }
    func updateDisplayName(_ name: String, expectedUserID: UUID) async throws -> AccountProfile {
        try await Task.sleep(for: .milliseconds(350))
        ProfileFixture.name = name
        return AccountProfile(id: expectedUserID, displayName: name)
    }
}

@MainActor
private final class ProfileUIAuthService: AuthenticationServicing {
    var current: AuthSessionSnapshot? = ProcessInfo.processInfo.arguments.contains("--guest") ? nil
        : AuthSessionSnapshot(user: ProfileFixture.user, expiresAt: Date().addingTimeInterval(3600))
    var continuation: AsyncStream<AuthSessionEvent>.Continuation?
    func events() throws -> AsyncStream<AuthSessionEvent> {
        let (stream, continuation) = AsyncStream<AuthSessionEvent>.makeStream()
        self.continuation = continuation
        continuation.yield(.initialSession(current))
        return stream
    }
    func restoredSession() async throws -> AuthSessionSnapshot? { current }
    func signUp(name: String, email: String, password: String) async throws -> SignupResult { .confirmationRequired }
    func signIn(email: String, password: String) async throws { throw AuthenticationFailure.unavailable }
    func signOut() async throws { current = nil; continuation?.yield(.signedOut) }
    func handleCallback(_ url: URL) async throws { throw AuthenticationFailure.invalidLink }
    func loadProfile() async throws -> AccountProfile { AccountProfile(id: ProfileFixture.id, displayName: ProfileFixture.name) }
}

@main
struct ProfileUITestHost: App {
    @StateObject private var reports = MyReportsViewModel(service: ReportsUIService())
    @StateObject private var submissions = MySubmissionsViewModel(service: SubmissionsUIService())
    @StateObject private var locationManager = LocationManager()
    @StateObject private var reviews = ReviewsViewModel(service: ReviewsUIService(), places: FavoritesUIPlaces())
    @StateObject private var favorites = FavoritesViewModel(service: FavoritesUIService(), places: FavoritesUIPlaces())
    @StateObject private var auth = AuthViewModel(service: ProfileUIAuthService())
    private let args = ProcessInfo.processInfo.arguments
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Text("UI TEST FIXTURES • NO BACKEND").font(.caption2)
                Group {
                    if args.contains("--reports") {
                        NavigationStack { MyReportsView() }
                    } else if args.contains("--report-entry") {
                        NavigationStack { RestroomDetailView(restroom: ReviewsUIService.restroom) }
                    } else if args.contains("--submissions") {
                        NavigationStack { MySubmissionsView() }
                    } else if args.contains("--reviews") {
                        NavigationStack { RestroomDetailView(restroom: ReviewsUIService.restroom) }
                    } else if args.contains("--my-reviews") {
                        NavigationStack { MyReviewsView(onExplore: {}) }
                    } else if args.contains("--saved") { SavedRestroomsScreen() } else { ProfileView() }
                }
                    .environmentObject(auth).environmentObject(favorites).environmentObject(reviews).environmentObject(submissions).environmentObject(reports).environmentObject(locationManager).task { auth.start() }
                    .onChange(of: auth.state) { _, state in favorites.setUser(state.user); reviews.setUser(state.user); submissions.setUser(state.user); reports.setUser(state.user) }
                    .task(id: auth.state) { await favorites.load(user: auth.state.user) }
                    .frame(width: args.contains("--compact") ? 320 : nil,
                           height: args.contains("--compact") ? 568 : nil)
            }
            .preferredColorScheme(args.contains("--dark") ? .dark : .light)
            .environment(\.dynamicTypeSize, args.contains("--large-type") ? .accessibility3 : .large)
        }
    }
}

// Saved/Profile fixture dependencies. These detail/directions placeholders are test-only;
// production navigation is verified separately in the full application.
struct RestroomDetailView: View {
    let restroom: Restroom
    var placeAttributions: NSAttributedString? = nil
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var reviews: ReviewsViewModel
    var body: some View {
        ScrollView {
            VStack {
                Text(restroom.name); Text("DETAILS UI TEST FIXTURE")
                if let summary = reviews.summaries[restroom.reviewKey] {
                    Text("Overall \(summary.overallRating?.formatted() ?? "unknown") · Cleanliness \(summary.cleanlinessRating?.formatted() ?? "unknown") · \(summary.reviewCount) reviews")
                }
                FavoriteButton(restroom: restroom)
                ReportRestroomButton(restroom: restroom)
                RestroomReviewsSection(restroom: restroom)
            }.padding()
        }
        .appScreenStyle()
        .task(id: "\(auth.state.user?.id.uuidString ?? "guest"):\(reviews.changeRevision)") {
            reviews.setUser(auth.state.user); await reviews.load(restroom)
        }
    }
}
struct DirectionsView: View {
    let restroom: Restroom
    var body: some View { Text("Directions fixture: \(restroom.name)") }
}
enum AppRoute: Hashable { case restroomDetail(UUID) }

@MainActor
private final class FavoritesUIService: FavoritesServicing {
    let id = UUID(uuidString: "14000000-0000-0000-0000-000000000001")!
    var records: [FavoriteRecord]
    init() {
        let anchor = FavoriteRecord.Anchor(id: id, googlePlaceID: "fixture-google-id", name: nil,
            address: nil, latitude: nil, longitude: nil, features: nil)
        records = ProcessInfo.processInfo.arguments.contains("--empty") ? [] : [FavoriteRecord(restroomID: id, restroom: anchor)]
    }
    func fetchFavorites(expectedUserID: UUID) async throws -> [FavoriteRecord] {
        if ProcessInfo.processInfo.arguments.contains("--favorites-error") { throw FavoritesFailure.network }
        return records
    }
    func save(_ restroom: Restroom, expectedUserID: UUID) async throws -> FavoriteRecord {
        let record = FavoriteRecord(restroomID: id, restroom: .init(id: id, googlePlaceID: "fixture-google-id", name: nil,
            address: nil, latitude: nil, longitude: nil, features: nil))
        records = [record]; return record
    }
    func remove(_ id: UUID, expectedUserID: UUID) async throws { records.removeAll { $0.id == id } }
}
@MainActor
private final class FavoritesUIPlaces: SavedPlaceResolving {
    func fetchSavedPlace(_ placeID: String) async throws -> SavedPlaceDetails {
        if ProcessInfo.processInfo.arguments.contains("--place-error") { throw FavoritesFailure.network }
        let restroom = Restroom(id: UUID(), name: "Test Park Public Restroom", latitude: 40, longitude: -73,
            address: "Fixture address", cleanlinessRating: nil, overallRating: nil, reviewCount: nil,
            distance: nil, openingHours: nil, accessibility: nil, babyChangingStation: nil,
            genderNeutral: nil, free: nil, imageName: "toilet", googlePlaceID: "fixture-google-id", googleRating: 4.5)
        return SavedPlaceDetails(restroom: restroom)
    }
}

@MainActor
private final class ReviewsUIService: ReviewServicing {
    static let restroom = Restroom(id: UUID(uuidString: "15000000-0000-0000-0000-000000000001")!, name: "Review Test Restroom", latitude: 40, longitude: -73, address: "Test fixture only", cleanlinessRating: nil, overallRating: nil, reviewCount: nil, distance: nil, openingHours: nil, accessibility: nil, babyChangingStation: nil, genderNeutral: nil, free: nil, imageName: "toilet")
    var rows: [RestroomReview] = ProcessInfo.processInfo.arguments.contains("--empty") ? [] : [
        RestroomReview(id: UUID(), userID: ProfileFixture.id, restroomID: restroom.id, overallRating: 4, cleanlinessRating: 3,
            comment: "UI fixture only. Clean and easy to access.", createdAt: Date(), updatedAt: Date())
    ]
    func summaries(for restrooms: [Restroom]) async throws -> [RestroomRatingSummary] {
        if ProcessInfo.processInfo.arguments.contains("--reviews-error") { throw ReviewFailure.unavailable }
        return [RestroomRatingSummary(restroomID: Self.restroom.id, googlePlaceID: nil,
            overallRating: rows.isEmpty ? nil : Double(rows[0].overallRating), cleanlinessRating: rows.first?.cleanlinessRating.map(Double.init), reviewCount: rows.count)]
    }
    func reviews(restroomID: UUID, before: ReviewCursor?) async throws -> [RestroomReview] { rows }
    func myReviews(userID: UUID, restroomID: UUID?, before: ReviewCursor?) async throws -> [MyRestroomReview] {
        if ProcessInfo.processInfo.arguments.contains("--reviews-error") { throw ReviewFailure.unavailable }
        return rows.filter { $0.userID == userID }.map { MyRestroomReview(review: $0, restroom: .init(id: Self.restroom.id, googlePlaceID: nil, name: Self.restroom.name, address: "Fixture", latitude: 40, longitude: -73, features: nil)) }
    }
    func submit(_ draft: ReviewDraft, restroom: Restroom?, existing: RestroomReview?, userID: UUID) async throws {
        try await Task.sleep(for: .milliseconds(300))
        rows = [RestroomReview(id: existing?.id ?? UUID(), userID: userID, restroomID: Self.restroom.id,
            overallRating: draft.overallRating, cleanlinessRating: draft.cleanlinessRating, comment: draft.normalizedComment,
            createdAt: existing?.createdAt ?? Date(), updatedAt: Date())]
    }
    func delete(_ review: RestroomReview, userID: UUID) async throws { rows.removeAll { $0.id == review.id && $0.userID == userID } }
}

// Day 16 fixture boundaries. The actual Google map and CoreLocation manager are compiled
// and checked in the full app; this host never requests location or a network resource.
@MainActor
final class LocationManager: ObservableObject {
    enum State { case notDetermined,locating,available,denied,restricted,unavailable }
    @Published var state: State = .notDetermined
    @Published var location: CLLocation?
    var isAuthorized: Bool { state == .available }
    func requestLocation() {
        if ProcessInfo.processInfo.arguments.contains("--location-denied") { state = .denied; return }
        location = CLLocation(coordinate: .init(latitude: 40,longitude: -73),altitude: 0,horizontalAccuracy: 10,verticalAccuracy: 0,timestamp: Date())
        state = .available
    }
}
enum GoogleMapsConfiguration { static let isConfigured = true }
struct GoogleMapView: View {
    let restrooms: [Restroom]
    let location: CLLocation?
    let showsUserLocation: Bool
    let selectedRestroomID: UUID?
    let initialCenter: CLLocation?
    let recenterRequest: Int
    let onSelect: (UUID?) -> Void
    let onCameraIdle: (CLLocationCoordinate2D) -> Void
    var onLocationPick: ((CLLocationCoordinate2D) -> Void)? = nil
    var isPreview = false
    var body: some View { Text("MAP UI TEST FIXTURE. Use coordinate fields below.").padding().frame(maxWidth: .infinity).background(AppTheme.surface) }
}
@MainActor
private final class SubmissionsUIService: RestroomSubmissionServicing {
    var rows: [RestroomSubmission] = ProcessInfo.processInfo.arguments.contains("--empty") ? [] :
        SubmissionStatus.allCases.map { status in
            let draft = SubmissionsUIService.draft(status.title+" Fixture Restroom")
            return SubmissionsUIService.record(draft,userID: ProfileFixture.id,status: status)
        }
    static func draft(_ name: String) -> SubmissionDraft {
        var draft = SubmissionDraft(); draft.name = name; draft.coordinate = .init(latitude: 40,longitude: -73)
        draft.notes = "Test fixture only. Entrance beside the lobby."; return draft
    }
    static func record(_ draft: SubmissionDraft,userID: UUID,requestID: UUID = UUID(),id: UUID = UUID(),status: SubmissionStatus = .pending) -> RestroomSubmission {
        RestroomSubmission(id: id,userID: userID,name: SubmissionDraft.trimmed(draft.name),address: SubmissionDraft.optional(draft.address),
            latitude: draft.coordinate!.latitude,longitude: draft.coordinate!.longitude,accessible: draft.accessible.value,
            babyChanging: draft.babyChanging.value,genderNeutral: draft.genderNeutral.value,free: draft.free.value,
            family: draft.family.value,allDay: draft.allDay.value,notes: SubmissionDraft.optional(draft.notes),status: status,
            createdAt: Date(),updatedAt: Date(),clientRequestID: requestID,approvedRestroomID: nil,
            rejectionReason: status == .rejected ? "Fixture: location already listed." : nil)
    }
    func fetch(userID: UUID,offset: Int) async throws -> [RestroomSubmission] {
        if ProcessInfo.processInfo.arguments.contains("--submissions-error") { throw SubmissionFailure.unavailable }
        return Array(rows.filter { $0.userID == userID }.dropFirst(offset).prefix(21))
    }
    func fetch(id: UUID,userID: UUID) async throws -> RestroomSubmission {
        guard let row = rows.first(where: { $0.id == id && $0.userID == userID }) else { throw SubmissionFailure.unavailable }
        return row
    }
    func duplicates(coordinate: SubmissionCoordinate,requestID: UUID,editingID: UUID?,userID: UUID) async throws -> [SubmissionDuplicate] {
        if ProcessInfo.processInfo.arguments.contains("--duplicate-error") { throw SubmissionFailure.unavailable }
        if ProcessInfo.processInfo.arguments.contains("--duplicate") {
            return [SubmissionDuplicate(id: UUID(),kind: .restroom,name: "Nearby Fixture Restroom",address: "Test only",latitude: 40,longitude: -73,googlePlaceID: nil,distanceMeters: 5)]
        }
        return []
    }
    func save(_ draft: SubmissionDraft,requestID: UUID,existing: RestroomSubmission?,userID: UUID) async throws -> RestroomSubmission {
        try await Task.sleep(for: .milliseconds(300))
        let record = Self.record(draft,userID: userID,requestID: requestID,id: existing?.id ?? UUID())
        rows.removeAll { $0.id == record.id }; rows.insert(record,at: 0); return record
    }
}

@MainActor
private final class ReportsUIService: ReportServicing {
    private var rows: [RestroomReport] = ProcessInfo.processInfo.arguments.contains("--empty") ? [] : ReportStatus.allCases.map { status in
        ReportsUIService.record(ReportDraft(type: .incorrectOpeningHours,details: "Fixture: closes earlier than shown."),userID: ProfileFixture.id,status: status)
    }
    static func record(_ draft: ReportDraft,userID: UUID,requestID: UUID = UUID(),status: ReportStatus = .pending) -> RestroomReport {
        .init(id: UUID(),userID: userID,restroomID: ReviewsUIService.restroom.id,type: draft.type!,details: draft.normalizedDetails,status: status,
              createdAt: Date(),updatedAt: Date(),reviewedAt: status == .pending ? nil : Date(),resolvedAt: status == .resolved ? Date() : nil,
              clientRequestID: requestID,restroom: .init(id: ReviewsUIService.restroom.id,googlePlaceID: nil,name: "Fixture Restroom",address: "Test only",latitude: 40,longitude: -73,features: nil))
    }
    func submit(_ draft: ReportDraft,restroom: Restroom,requestID: UUID,userID: UUID) async throws -> RestroomReport {
        try await Task.sleep(for: .milliseconds(350))
        if ProcessInfo.processInfo.arguments.contains("--report-write-error") { throw ReportFailure.unavailable }
        let row = Self.record(draft,userID: userID,requestID: requestID)
        rows.insert(row,at: 0); return row
    }
    func fetchMyReports(userID: UUID,offset: Int) async throws -> [RestroomReport] {
        if ProcessInfo.processInfo.arguments.contains("--reports-error") { throw ReportFailure.unavailable }
        return Array(rows.filter { $0.userID == userID }.dropFirst(offset).prefix(21))
    }
    func fetchReport(id: UUID,userID: UUID) async throws -> RestroomReport {
        guard let row = rows.first(where: { $0.id == id && $0.userID == userID }) else { throw ReportFailure.unavailable }
        return row
    }
}

// Production attribution asset component is defined with search views, outside this fixture build.
struct GoogleMapsAttribution: View {
    var body: some View { Text("Google Maps • UI TEST FIXTURE").font(.caption) }
}
