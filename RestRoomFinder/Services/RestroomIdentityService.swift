import Foundation
import Supabase

/// Shared Day 14 identity boundary. Neither favorites nor reviews invent a Google UUID in SQL.
@MainActor
enum RestroomIdentityService {
    enum Failure: Error { case sessionChanged }
    static func authenticated(_ expected: UUID) async throws -> (SupabaseClient, UUID) {
        let client = try SupabaseManager.shared.client()
        let session = try await client.auth.session
        guard !session.isExpired, !session.user.isAnonymous, session.user.id == expected else {
            throw Failure.sessionChanged
        }
        return (client, session.user.id)
    }
    static func ensureProfile(client: SupabaseClient, userID: UUID) async throws {
        let profiles: [AccountProfile] = try await client.from("profiles").select("id,display_name")
            .eq("id", value: userID).execute().value
        if profiles.isEmpty { _ = try await client.rpc("ensure_current_profile").execute() }
    }
    static func resolve(_ restroom: Restroom, client: SupabaseClient) async throws -> UUID {
        guard let placeID = restroom.googlePlaceID else { return restroom.id }
        return try await client.rpc("resolve_google_restroom", params: ["place_id": placeID]).execute().value
    }
}
