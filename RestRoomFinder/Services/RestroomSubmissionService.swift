import Foundation
import Supabase

@MainActor
final class RestroomSubmissionService: RestroomSubmissionServicing {
    private let columns = "id,user_id,name,address,latitude,longitude,is_accessible,has_baby_changing,is_gender_neutral,is_free,is_family_restroom,is_24_hours,notes,status,created_at,updated_at,client_request_id,approved_restroom_id,rejection_reason"
    private struct CandidateRequest: Encodable {
        let chosen_latitude: Double
        let chosen_longitude: Double
        let request_id: UUID
        let editing_id: UUID?
    }
    private struct Write: Encodable {
        let draft: SubmissionDraft
        var userID: UUID? = nil
        var requestID: UUID? = nil
        enum CodingKeys: String,CodingKey {
            case name,address,latitude,longitude,notes,user_id,client_request_id
            case is_accessible,has_baby_changing,is_gender_neutral,is_free,is_family_restroom,is_24_hours
        }
        func encode(to encoder: Encoder) throws {
            guard let coordinate = draft.coordinate, coordinate.isValid else { throw SubmissionFailure.invalid("Choose a valid location.") }
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(SubmissionDraft.trimmed(draft.name),forKey: .name)
            try c.encode(coordinate.latitude,forKey: .latitude); try c.encode(coordinate.longitude,forKey: .longitude)
            // Explicit null clears optional text/features when a pending submission is edited.
            try c.encode(SubmissionDraft.optional(draft.address),forKey: .address)
            try c.encode(SubmissionDraft.optional(draft.notes),forKey: .notes)
            try c.encode(draft.accessible.value,forKey: .is_accessible)
            try c.encode(draft.babyChanging.value,forKey: .has_baby_changing)
            try c.encode(draft.genderNeutral.value,forKey: .is_gender_neutral)
            try c.encode(draft.free.value,forKey: .is_free)
            try c.encode(draft.family.value,forKey: .is_family_restroom)
            try c.encode(draft.allDay.value,forKey: .is_24_hours)
            try c.encodeIfPresent(userID,forKey: .user_id)
            try c.encodeIfPresent(requestID,forKey: .client_request_id)
        }
    }
    func fetch(userID: UUID, offset: Int) async throws -> [RestroomSubmission] {
        do {
            let (client,id) = try await RestroomIdentityService.authenticated(userID)
            let start = max(0,offset)
            let rows: [RestroomSubmission] = try await client.from("restroom_submissions").select(columns)
                .eq("user_id",value: id).order("created_at",ascending: false).order("id",ascending: false)
                .range(from: start,to: start+20).execute().value
            _ = try await RestroomIdentityService.authenticated(userID)
            return rows
        } catch { throw readable(error) }
    }
    func fetch(id: UUID,userID: UUID) async throws -> RestroomSubmission {
        do {
            let (client,owner) = try await RestroomIdentityService.authenticated(userID)
            let row: RestroomSubmission = try await client.from("restroom_submissions").select(columns)
                .eq("id",value: id).eq("user_id",value: owner).single().execute().value
            _ = try await RestroomIdentityService.authenticated(userID)
            return row
        } catch { throw readable(error) }
    }
    func duplicates(coordinate: SubmissionCoordinate,requestID: UUID,editingID: UUID?,userID: UUID) async throws -> [SubmissionDuplicate] {
        guard coordinate.isValid else { throw SubmissionFailure.invalid("Choose a valid location.") }
        do {
            let (client,_) = try await RestroomIdentityService.authenticated(userID)
            let rows: [SubmissionDuplicate] = try await client.rpc("submission_duplicate_candidates",params:
                CandidateRequest(chosen_latitude: coordinate.latitude,chosen_longitude: coordinate.longitude,request_id: requestID,editing_id: editingID)).execute().value
            _ = try await RestroomIdentityService.authenticated(userID)
            return rows
        } catch { throw readable(error) }
    }
    func save(_ draft: SubmissionDraft,requestID: UUID,existing: RestroomSubmission?,userID: UUID) async throws -> RestroomSubmission {
        if let error = draft.validationError { throw SubmissionFailure.invalid(error) }
        do {
            let (client,owner) = try await RestroomIdentityService.authenticated(userID)
            let row: RestroomSubmission
            if let existing {
                guard existing.userID == owner, existing.status == .pending else { throw SubmissionFailure.noLongerPending }
                let rows: [RestroomSubmission] = try await client.from("restroom_submissions").update(Write(draft: draft))
                    .eq("id",value: existing.id).eq("user_id",value: owner).eq("status",value: "pending")
                    .select(columns).execute().value
                guard let updated = rows.first else { throw SubmissionFailure.noLongerPending }
                row = updated
            } else {
                try await RestroomIdentityService.ensureProfile(client: client,userID: owner)
                _ = try await RestroomIdentityService.authenticated(userID)
                // DO NOTHING on an existing request UUID makes a response-loss retry idempotent.
                _ = try await client.from("restroom_submissions").upsert(Write(draft: draft,userID: owner,requestID: requestID),
                    onConflict: "user_id,client_request_id",returning: .minimal,ignoreDuplicates: true).execute()
                row = try await client.from("restroom_submissions").select(columns).eq("user_id",value: owner)
                    .eq("client_request_id",value: requestID).single().execute().value
                guard row.matches(draft) else { throw SubmissionFailure.priorAttemptReceived }
            }
            _ = try await RestroomIdentityService.authenticated(userID)
            return row
        } catch { throw readable(error) }
    }
    private func readable(_ error: Error) -> SubmissionFailure {
        if let known = error as? SubmissionFailure { return known }
        if error is RestroomIdentityService.Failure || error is AuthError { return .sessionChanged }
        if let code = (error as? PostgrestError)?.code, ["PGRST202","PGRST204","PGRST205","42P01","42883","42703"].contains(code) { return .missingSetup }
        return .unavailable
    }
}
