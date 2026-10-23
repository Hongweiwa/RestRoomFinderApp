import Foundation

@MainActor
protocol ProfileServicing {
    func fetchProfile(expectedUserID: UUID) async throws -> AccountProfile
    func updateDisplayName(_ name: String, expectedUserID: UUID) async throws -> AccountProfile
}

enum ProfileFailure: Error, LocalizedError {
    case sessionChanged, unavailable, network, invalidName

    var errorDescription: String? {
        switch self {
        case .sessionChanged: return "Your account session changed. Please reopen Profile."
        case .unavailable: return "Unable to load or save your profile. Please try again."
        case .network: return "Unable to connect. Check your internet connection and try again."
        case .invalidName: return "Enter a display name with 1–50 characters."
        }
    }
}

enum ProfileValidation {
    static let maximumNameLength = 50
    static func normalizedName(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func nameError(_ name: String) -> String? {
        let name = normalizedName(name)
        guard !name.isEmpty else { return "Enter your display name." }
        // Match the database's character bound, including combining Unicode scalars.
        guard name.unicodeScalars.count <= maximumNameLength else { return "Use 50 characters or fewer." }
        return nil
    }
}
