import Foundation
import Supabase

@MainActor
final class FavoritesService: FavoritesServicing {
    private let columns = "restroom_id,restrooms(id,google_place_id,name,address,latitude,longitude,restroom_features(is_accessible,has_baby_changing,is_gender_neutral,is_free))"
    private func identity(_ expected: UUID) async throws -> (SupabaseClient, UUID) {
        try await RestroomIdentityService.authenticated(expected)
    }
    func fetchFavorites(expectedUserID: UUID) async throws -> [FavoriteRecord] {
        do {
            let (client, id) = try await identity(expectedUserID)
            // Page explicitly rather than silently truncating at PostgREST's default row limit.
            var records: [FavoriteRecord] = []
            var offset = 0
            while true {
                let page: [FavoriteRecord] = try await client.from("favorites").select(columns)
                    .eq("user_id", value: id).order("created_at", ascending: false).order("restroom_id")
                    .range(from: offset, to: offset + 199).execute().value
                records += page
                if page.count < 200 { break }
                offset += 200
            }
            _ = try await identity(expectedUserID)
            return records
        } catch { throw Self.readable(error, step: "load") }
    }
    func save(_ restroom: Restroom, expectedUserID: UUID) async throws -> FavoriteRecord {
        var step = "session"
        do {
            let (client, authenticatedID) = try await identity(expectedUserID)
            step = "profile-recovery"
            try await RestroomIdentityService.ensureProfile(client: client, userID: authenticatedID)
            step = "place"
            let id = try await RestroomIdentityService.resolve(restroom, client: client)
            _ = try await identity(expectedUserID)
            // Identity comes from the captured SDK session; RLS compares it with auth.uid().
            // Including it prevents a changed SDK session from saving to the next account.
            step = "save"
            _ = try await client.from("favorites").upsert(["restroom_id": id.uuidString, "user_id": authenticatedID.uuidString],
                onConflict: "user_id,restroom_id", ignoreDuplicates: true).execute()
            let (_, userID) = try await identity(expectedUserID)
            step = "confirmation"
            return try await client.from("favorites").select(columns).eq("user_id", value: userID)
                .eq("restroom_id", value: id).single().execute().value
        } catch { throw Self.readable(error, step: step) }
    }
    func remove(_ id: UUID, expectedUserID: UUID) async throws {
        do {
            let (client, userID) = try await identity(expectedUserID)
            _ = try await client.from("favorites").delete().eq("user_id", value: userID)
                .eq("restroom_id", value: id).execute()
            _ = try await identity(expectedUserID)
        } catch { throw Self.readable(error, step: "remove") }
    }
    private static func readable(_ error: Error, step: String) -> FavoritesFailure {
        // Only expose a bounded error code, never server messages, records or credentials.
        let code = (error as? PostgrestError)?.code
        let safeCode = code.flatMap { value in
            value.range(of: "^[A-Z0-9]{5,10}$", options: .regularExpression) != nil ? value : nil
        } ?? (error is DecodingError ? "RESPONSE" : "UNKNOWN")
        if error is RestroomIdentityService.Failure { return .sessionChanged }
        let result = (error as? FavoritesFailure) ?? (error is URLError ? .network : .backend(step: step, code: safeCode))
        #if DEBUG
        print("[Favorites] Request failed: \(result)")
        #endif
        return result
    }
}
