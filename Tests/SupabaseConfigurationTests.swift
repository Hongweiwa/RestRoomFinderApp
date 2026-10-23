import Foundation

enum SupabaseConfigurationTests {
    static func run() {
        let testKey = "sb_publishable_" + String(repeating: "a", count: 32)
        do {
            let configuration = try SupabaseConfiguration(values: ["SupabaseURL": " https://example.supabase.co/ ", "SupabasePublishableKey": testKey])
            precondition(configuration.url.host == "example.supabase.co" && configuration.publishableKey == testKey)
        } catch { preconditionFailure("Valid client configuration rejected") }
        expectFailure([:], .missingURL)
        expectFailure(["SupabaseURL": "$(SUPABASE_URL)"], .missingURL)
        expectFailure(["SupabaseURL": "https://YOUR_PROJECT_REF.supabase.co"], .missingURL)
        for url in ["https:", "http://example.supabase.co", "https://name:password@example.supabase.co", "https://example.supabase.co/rest/v1", "https://example.supabase.co?key=test", "https://example.supabase.co#fragment"] {
            expectFailure(["SupabaseURL": url, "SupabasePublishableKey": testKey], .invalidURL)
        }
        expectFailure(["SupabaseURL": "https://example.supabase.co"], .missingKey)
        for key in ["sb_secret_" + "test", "legacy.jwt.value", "sb_publishable_", "sb_publishable_with whitespace"] {
            expectFailure(["SupabaseURL": "https://example.supabase.co", "SupabasePublishableKey": key], .invalidKey)
        }
        print("PASS: Supabase missing/placeholder configuration, HTTPS project URL validation, publishable-only keys, secret/legacy key rejection")
    }

    private static func expectFailure(_ values: [String: Any], _ expected: SupabaseConfiguration.ConfigurationError) {
        do {
            _ = try SupabaseConfiguration(values: values)
            preconditionFailure("Expected configuration error")
        } catch let error as SupabaseConfiguration.ConfigurationError {
            precondition(String(describing: error) == String(describing: expected))
        } catch { preconditionFailure("Unexpected error") }
    }
}
