import Foundation

enum ReportType: String, Codable, CaseIterable, Identifiable {
    case temporarilyClosed = "temporarily_closed", permanentlyClosed = "permanently_closed"
    case incorrectLocation = "incorrect_location", notPubliclyAccessible = "not_publicly_accessible"
    case incorrectOpeningHours = "incorrect_opening_hours", incorrectAccessibility = "incorrect_accessibility"
    case uncleanRestroom = "unclean_restroom", duplicateRestroom = "duplicate_restroom", other
    var id: Self { self }
    var title: String {
        switch self {
        case .temporarilyClosed: return "Temporarily Closed"
        case .permanentlyClosed: return "Permanently Closed"
        case .incorrectLocation: return "Incorrect Location"
        case .notPubliclyAccessible: return "Not Publicly Accessible"
        case .incorrectOpeningHours: return "Incorrect Opening Hours"
        case .incorrectAccessibility: return "Incorrect Accessibility"
        case .uncleanRestroom: return "Dirty / Unclean Restroom"
        case .duplicateRestroom: return "Duplicate Restroom"
        case .other: return "Other"
        }
    }
}

enum ReportStatus: String, Decodable, CaseIterable {
    case pending, inReview = "in_review", resolved, dismissed
    var title: String {
        switch self { case .pending: return "Pending"; case .inReview: return "In Review"; case .resolved: return "Resolved"; case .dismissed: return "Dismissed" }
    }
    var explanation: String {
        switch self {
        case .pending: return "Your report has been received and is pending review."
        case .inReview: return "Your report is being reviewed."
        case .resolved: return "Your report has been processed. This does not necessarily mean Google's external listing has changed."
        case .dismissed: return "This report was reviewed and dismissed."
        }
    }
}

struct ReportDraft: Equatable {
    var type: ReportType?
    var details = ""
    var normalizedDetails: String? {
        let text = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    var validationError: String? {
        guard let type else { return "Select the problem you want to report." }
        let length = normalizedDetails?.unicodeScalars.count ?? 0
        guard length <= 1000 else { return "Use 1,000 characters or fewer for additional details." }
        if type == .other && length < 10 { return "Describe the issue using at least 10 characters when choosing Other." }
        return nil
    }
}

/// Private claim, not a correction or a rating. Google display content is not stored.
struct RestroomReport: Decodable, Identifiable, Equatable {
    let id: UUID
    let userID: UUID?
    let restroomID: UUID
    let type: ReportType
    let details: String?
    let status: ReportStatus
    let createdAt: Date
    let updatedAt: Date
    let reviewedAt: Date?
    let resolvedAt: Date?
    let clientRequestID: UUID
    let restroom: FavoriteRecord.Anchor?
    enum CodingKeys: String, CodingKey {
        case id,status,restroom="restrooms",userID="user_id",restroomID="restroom_id",type="report_type",details="comment"
        case createdAt="created_at",updatedAt="updated_at",reviewedAt="reviewed_at",resolvedAt="resolved_at",clientRequestID="client_request_id"
    }
    var restroomLabel: String { restroom?.name ?? (restroom?.googlePlaceID == nil ? "Reported restroom" : "Google Maps restroom") }
    /// Opens the exact external place on demand without fetching/storing Google content.
    var googleMapsURL: URL? {
        guard let placeID = restroom?.googlePlaceID else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [.init(name: "api",value: "1"),.init(name: "query",value: "restroom"),.init(name: "query_place_id",value: placeID)]
        return components.url
    }
    func matches(_ draft: ReportDraft,restroomID: UUID) -> Bool {
        self.restroomID == restroomID && type == draft.type && details == draft.normalizedDetails
    }
}

@MainActor
protocol ReportServicing {
    func submit(_ draft: ReportDraft,restroom: Restroom,requestID: UUID,userID: UUID) async throws -> RestroomReport
    /// Returns at most 21 rows: 20 visible + one paging sentinel.
    func fetchMyReports(userID: UUID,offset: Int) async throws -> [RestroomReport]
    func fetchReport(id: UUID,userID: UUID) async throws -> RestroomReport
}

enum ReportFailure: Error, LocalizedError {
    case sessionChanged, unavailable, missingSetup, recentDuplicate, priorAttemptReceived, invalid(String)
    var errorDescription: String? {
        switch self {
        case .sessionChanged: return "Your account changed. Sign in again before reporting."
        case .unavailable: return "Unable to load or submit reports. Check your connection and try again."
        case .missingSetup: return "Reporting is not configured in this Supabase project yet. Apply the Day 17 migration and try again."
        case .recentDuplicate: return "An identical report was received in the last five minutes. Check My Reports before submitting again."
        case .priorAttemptReceived: return "Your earlier report was received. Check My Reports before starting a new report."
        case .invalid(let message): return message
        }
    }
    static func message(_ error: Error) -> String { (error as? ReportFailure)?.errorDescription ?? ReportFailure.unavailable.errorDescription! }
}
