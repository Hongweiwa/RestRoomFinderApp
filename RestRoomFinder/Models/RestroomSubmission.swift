import CoreLocation
import Foundation

/// These statuses describe a private contribution, not trust in a public restroom.
enum SubmissionStatus: String, Decodable, CaseIterable {
    case pending, approved, rejected
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .pending: return "clock"; case .approved: return "checkmark.circle"; case .rejected: return "xmark.circle" }
    }
}

enum SubmissionFeature: String, CaseIterable, Identifiable {
    case unknown = "Unknown", yes = "Yes", no = "No"
    var id: Self { self }
    var value: Bool? { self == .unknown ? nil : self == .yes }
    init(_ value: Bool?) { self = value.map { $0 ? .yes : .no } ?? .unknown }
}

struct SubmissionCoordinate: Equatable {
    var latitude: Double
    var longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var description: String { "\(latitude.formatted(.number.precision(.fractionLength(5)))), \(longitude.formatted(.number.precision(.fractionLength(5))))" }
    static func current(_ location: CLLocation?, now: Date = Date()) -> Self? {
        guard let location, location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSince(now)) < 60 else { return nil }
        let coordinate = Self(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        return coordinate.isValid ? coordinate : nil
    }
}

struct SubmissionDraft: Equatable {
    var name = ""
    var address = ""
    var coordinate: SubmissionCoordinate?
    var accessible: SubmissionFeature = .unknown
    var babyChanging: SubmissionFeature = .unknown
    var genderNeutral: SubmissionFeature = .unknown
    var free: SubmissionFeature = .unknown
    var family: SubmissionFeature = .unknown
    var allDay: SubmissionFeature = .unknown
    var notes = ""
    init(submission: RestroomSubmission? = nil) {
        guard let submission else { return }
        name = submission.name; address = submission.address ?? ""
        coordinate = .init(latitude: submission.latitude, longitude: submission.longitude)
        accessible = .init(submission.accessible); babyChanging = .init(submission.babyChanging)
        genderNeutral = .init(submission.genderNeutral); free = .init(submission.free)
        family = .init(submission.family); allDay = .init(submission.allDay); notes = submission.notes ?? ""
    }
    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func optional(_ text: String) -> String? { let value = trimmed(text); return value.isEmpty ? nil : value }
    var validationError: String? {
        let name = Self.trimmed(name)
        guard !name.isEmpty, name.unicodeScalars.count <= 200 else { return "Enter a restroom name with 1–200 characters." }
        guard coordinate?.isValid == true else { return "Choose a valid location before submitting." }
        guard (Self.optional(address)?.unicodeScalars.count ?? 0) <= 1000 else { return "Use 1,000 characters or fewer for the address." }
        guard (Self.optional(notes)?.unicodeScalars.count ?? 0) <= 1000 else { return "Use 1,000 characters or fewer for notes." }
        return nil
    }
}

struct RestroomSubmission: Decodable, Equatable, Identifiable {
    let id: UUID
    let userID: UUID?
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let accessible: Bool?
    let babyChanging: Bool?
    let genderNeutral: Bool?
    let free: Bool?
    let family: Bool?
    let allDay: Bool?
    let notes: String?
    let status: SubmissionStatus
    let createdAt: Date
    let updatedAt: Date
    let clientRequestID: UUID
    let approvedRestroomID: UUID?
    let rejectionReason: String?
    enum CodingKeys: String, CodingKey {
        case id,name,address,latitude,longitude,notes,status
        case userID="user_id",accessible="is_accessible",babyChanging="has_baby_changing",genderNeutral="is_gender_neutral"
        case free="is_free",family="is_family_restroom",allDay="is_24_hours",createdAt="created_at",updatedAt="updated_at"
        case clientRequestID="client_request_id",approvedRestroomID="approved_restroom_id",rejectionReason="rejection_reason"
    }
    var coordinate: SubmissionCoordinate { .init(latitude: latitude, longitude: longitude) }
    func matches(_ draft: SubmissionDraft) -> Bool { SubmissionDraft(submission: self).normalized == draft.normalized }
}

private extension SubmissionDraft {
    var normalized: Self {
        var result = self
        result.name = Self.trimmed(name); result.address = Self.optional(address) ?? ""; result.notes = Self.optional(notes) ?? ""
        return result
    }
}

struct SubmissionDuplicate: Decodable, Identifiable, Equatable {
    enum Kind: String, Decodable { case restroom, submission }
    let id: UUID
    let kind: Kind
    let name: String?
    let address: String?
    let latitude: Double
    let longitude: Double
    let googlePlaceID: String?
    let distanceMeters: Double
    var knownRestroom: Restroom? = nil
    enum CodingKeys: String,CodingKey {
        case id,kind,name,address,latitude,longitude
        case googlePlaceID="google_place_id",distanceMeters="distance_meters"
    }
    var restroom: Restroom? {
        guard kind == .restroom else { return nil }
        return knownRestroom ?? Restroom(id: id, name: name ?? "Public restroom", latitude: latitude, longitude: longitude,
            address: address ?? "Address unavailable", cleanlinessRating: nil, overallRating: nil, reviewCount: nil, distance: nil,
            openingHours: nil, accessibility: nil, babyChangingStation: nil, genderNeutral: nil, free: nil, imageName: "toilet", googlePlaceID: googlePlaceID)
    }
    static func nearby(_ restrooms: [Restroom], coordinate: SubmissionCoordinate) -> [Self] {
        guard coordinate.isValid else { return [] }
        return restrooms.compactMap { restroom in
            guard CLLocationCoordinate2DIsValid(restroom.coordinate) else { return nil }
            let distance = coordinate.location.distance(from: .init(latitude: restroom.latitude, longitude: restroom.longitude))
            guard distance <= 50 else { return nil }
            return Self(id: restroom.id,kind: .restroom,name: restroom.name,address: restroom.address,
                latitude: restroom.latitude,longitude: restroom.longitude,googlePlaceID: restroom.googlePlaceID,
                distanceMeters: distance,knownRestroom: restroom)
        }
    }
    var key: String { kind == .submission ? "submission:\(id)" : googlePlaceID.map { "google:\($0)" } ?? "restroom:\(id)" }
}

@MainActor
protocol RestroomSubmissionServicing {
    func fetch(userID: UUID, offset: Int) async throws -> [RestroomSubmission]
    func fetch(id: UUID, userID: UUID) async throws -> RestroomSubmission
    func duplicates(coordinate: SubmissionCoordinate, requestID: UUID, editingID: UUID?, userID: UUID) async throws -> [SubmissionDuplicate]
    func save(_ draft: SubmissionDraft, requestID: UUID, existing: RestroomSubmission?, userID: UUID) async throws -> RestroomSubmission
}

enum SubmissionFailure: Error, LocalizedError {
    case sessionChanged, unavailable, missingSetup, noLongerPending, priorAttemptReceived, invalid(String)
    var errorDescription: String? {
        switch self {
        case .sessionChanged: return "Your account changed. Sign in again before submitting."
        case .unavailable: return "Unable to load or submit restroom. Check your connection and try again."
        case .missingSetup: return "Submissions are not configured in this Supabase project yet. Apply the Day 16 migration and try again."
        case .noLongerPending: return "This submission is no longer pending or available to edit. Refresh My Submissions."
        case .priorAttemptReceived: return "Your earlier submission was received. Open My Submissions to review it before starting a new one."
        case .invalid(let message): return message
        }
    }
}
