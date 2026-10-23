import Foundation
import Supabase

@MainActor
final class ReportService: ReportServicing {
    private let columns = "id,user_id,restroom_id,report_type,comment,status,created_at,updated_at,reviewed_at,resolved_at,client_request_id,restrooms(id,google_place_id,name,address,latitude,longitude)"
    private struct Write: Encodable {
        let user_id: UUID
        let restroom_id: UUID
        let report_type: ReportType
        let comment: String?
        let client_request_id: UUID
    }
    func submit(_ draft: ReportDraft,restroom: Restroom,requestID: UUID,userID: UUID) async throws -> RestroomReport {
        if let error = draft.validationError { throw ReportFailure.invalid(error) }
        do {
            let (client,owner) = try await RestroomIdentityService.authenticated(userID)
            try await RestroomIdentityService.ensureProfile(client: client,userID: owner)
            _ = try await RestroomIdentityService.authenticated(userID)
            let restroomID = try await RestroomIdentityService.resolve(restroom,client: client)
            _ = try await RestroomIdentityService.authenticated(userID)
            // The owner comes from the verified SDK session; the database independently checks auth.uid().
            let write = Write(user_id: owner,restroom_id: restroomID,report_type: draft.type!,comment: draft.normalizedDetails,client_request_id: requestID)
            _ = try await client.from("reports").upsert(write,onConflict: "user_id,client_request_id",returning: .minimal,ignoreDuplicates: true).execute()
            let row: RestroomReport = try await client.from("reports").select(columns).eq("user_id",value: owner)
                .eq("client_request_id",value: requestID).single().execute().value
            _ = try await RestroomIdentityService.authenticated(userID)
            guard row.matches(draft,restroomID: restroomID) else { throw ReportFailure.priorAttemptReceived }
            return row
        } catch { throw readable(error) }
    }
    func fetchMyReports(userID: UUID,offset: Int) async throws -> [RestroomReport] {
        do {
            let (client,owner) = try await RestroomIdentityService.authenticated(userID)
            let start = max(0,offset)
            let rows: [RestroomReport] = try await client.from("reports").select(columns).eq("user_id",value: owner)
                .order("created_at",ascending: false).order("id",ascending: false).range(from: start,to: start+20).execute().value
            _ = try await RestroomIdentityService.authenticated(userID)
            return rows
        } catch { throw readable(error) }
    }
    func fetchReport(id: UUID,userID: UUID) async throws -> RestroomReport {
        do {
            let (client,owner) = try await RestroomIdentityService.authenticated(userID)
            let row: RestroomReport = try await client.from("reports").select(columns).eq("user_id",value: owner)
                .eq("id",value: id).single().execute().value
            _ = try await RestroomIdentityService.authenticated(userID)
            return row
        } catch { throw readable(error) }
    }
    private func readable(_ error: Error) -> ReportFailure {
        if let known = error as? ReportFailure { return known }
        if error is RestroomIdentityService.Failure || error is AuthError { return .sessionChanged }
        if let code = (error as? PostgrestError)?.code {
            if code == "P1701" { return .recentDuplicate }
            if ["PGRST202","PGRST204","PGRST205","42P01","42883","42703","22P02"].contains(code) { return .missingSetup }
        }
        return .unavailable
    }
}
