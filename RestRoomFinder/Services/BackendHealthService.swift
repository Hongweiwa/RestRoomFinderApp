import Foundation
import Supabase

/// Read-only connection probe. No Google requests, writes, login or feature integration.
@MainActor
struct BackendHealthService {
    struct ProbeRow: Decodable { let id: UUID }

    func checkConnection() async throws -> Int {
        let client = try SupabaseManager.shared.client()
        let rows: [ProbeRow] = try await client.from("restrooms").select("id").limit(1).execute().value
        // An empty table is still a successful SDK + Data API + RLS connection.
        return rows.count
    }

    #if DEBUG
    static func runDiagnosticIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--check-backend") else { return }
        Task {
            do {
                let count = try await BackendHealthService().checkConnection()
                print("[Supabase] Connection succeeded. \(count) public restroom ID(s) sampled; an empty result is valid.")
            } catch let error as SupabaseConfiguration.ConfigurationError {
                print("[Supabase] Not configured: \(error.localizedDescription)")
            } catch {
                // Do not print raw SDK/network errors that could include request headers or credentials.
                print("[Supabase] Connection failed. Check connectivity, project URL/publishable key, Data API and the Day 11 migration.")
            }
        }
    }
    #endif
}
