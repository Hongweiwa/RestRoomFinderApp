import Foundation
import Supabase

/// Uses the existing client and SDK identity. Caller identity is only a stale-request guard.
@MainActor
final class ProfileService: ProfileServicing {
    private func authenticatedClient(expectedUserID: UUID) async throws -> (client: SupabaseClient, id: UUID) {
        let client = try SupabaseManager.shared.client()
        let session = try await client.auth.session
        guard !session.isExpired, !session.user.isAnonymous, session.user.id == expectedUserID else {
            throw ProfileFailure.sessionChanged
        }
        return (client, session.user.id)
    }

    func fetchProfile(expectedUserID: UUID) async throws -> AccountProfile {
        do {
            let (client, id) = try await authenticatedClient(expectedUserID: expectedUserID)
            let rows: [AccountProfile] = try await client.from("profiles").select("id,display_name")
                .eq("id", value: id).execute().value
            let profile: AccountProfile
            if let existing = rows.first { profile = existing }
            else {
                // Day 12's trigger remains primary. Only a genuinely missing row invokes recovery.
                // This RPC has no user-ID argument and enforces ownership through existing RLS.
                profile = try await client.rpc("ensure_current_profile").select("id,display_name")
                    .single().execute().value
            }
            _ = try await authenticatedClient(expectedUserID: expectedUserID)
            guard profile.id == expectedUserID else { throw ProfileFailure.sessionChanged }
            return profile
        } catch { throw Self.readable(error) }
    }

    func updateDisplayName(_ name: String, expectedUserID: UUID) async throws -> AccountProfile {
        guard ProfileValidation.nameError(name) == nil else { throw ProfileFailure.invalidName }
        do {
            let (client, id) = try await authenticatedClient(expectedUserID: expectedUserID)
            let profile: AccountProfile = try await client.from("profiles")
                .update(["display_name": ProfileValidation.normalizedName(name)])
                .eq("id", value: id).select("id,display_name").single().execute().value
            _ = try await authenticatedClient(expectedUserID: expectedUserID)
            guard profile.id == expectedUserID else { throw ProfileFailure.sessionChanged }
            return profile
        } catch { throw Self.readable(error) }
    }

    private static func readable(_ error: Error) -> ProfileFailure {
        let result = (error as? ProfileFailure) ?? (error is URLError ? .network : .unavailable)
        #if DEBUG
        print("[Profile] Request failed: \(result)")
        #endif
        return result
    }
}
