# Day 13 — Profile functionality and UI

Implemented in the requested order: first the profile service, view model, basic load/edit UI, migration and tests; then the visual redesign. Phase 1 passed the full Xcode build, Swift regression suite and local PostGIS/RLS tests before Phase 2 began. The final redesigned app also builds successfully.

## What works

Profile opens from the existing Home and Restroom Details bottom navigation. It is presented full-screen, marks Profile selected, and preserves the restroom screen/search beneath it. Find or the back arrow returns to that screen. The existing Saved item is retained; no extra tab was added.

The authenticated header displays initials, the real `profiles.display_name`, and the email from the existing Supabase Auth state. Missing names show “Your profile,” without inventing a name or activity. The Edit Profile screen changes only the display name; email is read-only. Names are trimmed, must not be blank and must contain at most 50 Unicode scalars (compatible with PostgreSQL's character limit). Existing longer Day 12 names remain readable; they must be shortened before saving an edit. The database's existing 80-character constraint is preserved rather than invalidating existing data.

Saving writes to Supabase and uses the returned row to update Profile immediately. Failed writes retain the last loaded profile and the user's draft. Repeated saves are blocked. Cancel warns before discarding a changed draft. Pull to refresh and Retry reload real backend data.

Guest Profile shows an avatar, honest account-benefit copy, Create Account and Log In. Those actions open the existing authentication forms directly. Guests still use the map, search, filters, details and directions. Logout shows a native destructive confirmation, calls the existing AuthViewModel logout, and returns to Guest Profile. It retains Day 12's current-device scope and never deletes a profile.

Activity rows (Saved Restrooms, My Reviews, My Submissions, My Reports) and settings rows (Account Settings, Privacy, Help & Support) are explicitly labelled future-feature destinations. There are no fake counts, records, support contacts, or privacy policies.

## Architecture and ownership

`ProfileView / EditProfileView → ProfileViewModel → ProfileServicing / ProfileService → existing SupabaseManager client → public.profiles`

The existing `AuthUser`, `AccountProfile`, AuthViewModel, AuthService, client configuration and session persistence are reused. No new auth manager, client, user model, or app-wide router was introduced. The account sheet gained an initial-page parameter to support direct guest Login/Create Account entry.

ProfileService obtains the active non-anonymous SDK session, checks expiry/expected identity, and filters queries by that session's UUID. It checks identity again before returning. An ID supplied by a caller is only a stale-request guard, not authority. Updates send only `display_name`; they cannot change email, ownership, avatar, timestamps or auth metadata. Existing RLS still enforces `profiles.id = auth.uid()`.

ProfileViewModel uses `idle`, `loading`, `loaded(AccountProfile)`, and `error(String)` states, with separate save progress/error state. Account changes clear profile/edit state synchronously. Request revisions reject late loads/saves from an earlier account. Authenticated loading never renders the Guest Profile. A profile-fetch failure does not log the user out.

Supabase update/filter/returned-row behavior follows the installed SDK and [official Swift update API](https://supabase.com/docs/reference/swift/update). No SDK versions or API-key values changed.

## Missing-profile recovery and manual setup

The Day 12 `auth.users` trigger remains the normal profile creation mechanism. The app does not insert or upsert profiles during signup or ordinary loads.

A successful SELECT returning no row calls `public.ensure_current_profile()`. The new function takes **no arguments**, obtains `auth.uid()`, rejects guests/anonymous sessions, and inserts only that ID with `ON CONFLICT DO NOTHING`. It returns the caller's profile. It never overwrites an edited name, copies metadata, or accepts an arbitrary user ID. A recovered missing profile initially has no name; Edit Profile lets its owner set one.

The function uses **SECURITY INVOKER**, an empty search path, existing column grants and existing RLS. Only the authenticated role receives execute permission. No service-role secret or policy weakening is needed. See [Supabase database function guidance](https://supabase.com/docs/guides/database/functions).

**Apply the new migration manually before relying on recovery:**

1. Open your existing Supabase project → SQL Editor → New query.
2. Run `supabase/migrations/202610090002_profile_recovery.sql` once, after the Day 11 foundation and Day 12 profile-trigger migrations. Do not rerun those earlier migrations if already applied.
3. Confirm the query succeeds. This task tested the migration locally; it did **not** apply it to the hosted project.
4. In Table Editor → profiles, verify RLS remains enabled and the signed-in user's UUID matches Authentication → Users. Do not add broad read/update policies.

No new Xcode configuration is required. Build the existing RestRoomFinder scheme. Keep the Day 12 confirmation redirect setup and existing project URL/publishable key. Only missing-row recovery needs the new RPC; ordinary reads/edits use the existing table permissions.

## Visual design and accessibility

The UI uses the existing monochrome adaptive theme, semantic typography, SF Symbols and rounded cards. The avatar scales with text size; long header names/emails wrap. The name input scrolls horizontally while editing, like a native single-line name field. All screens scroll vertically when space is limited. The centered content has a readable maximum width on larger devices.

Reusable ProfileAvatar, ProfileMenuRow and ProfileSectionCard provide consistent spacing and separators. Guest/login buttons reuse existing PrimaryButton and SecondaryButton. Loading uses an inline progress card; errors provide readable feedback and Retry. Logout is secondary to editing/activity, with a destructive native confirmation. It stays monochrome outside the system confirmation.

Interactive rows and actions meet the existing 44-point minimum. Avatar/actions have VoiceOver labels; section headings carry header traits. Decorative symbols are hidden from accessibility. Bottom navigation labels stay on one line and its text scaling is capped at XXXL to prevent tiny tab columns from splitting words at accessibility sizes; Profile body content continues to support accessibility text sizes.

## Tests completed and their limits

- **Phase 1 full build: passed.** Verified before the redesign.
- **Final full simulator build: passed.** Only the existing AppIntents metadata extraction warning; no new Swift compiler warnings.
- `bash Tests/run-nearby-tests.sh`: passed before and after redesign. Profile tests cover real model identity mapping through a fake service, trimmed updates, blank/oversized validation without writes, persisted-service reload, load/save failures, retry, account A → logout → account B, late responses, mismatched ownership and duplicate saves. The existing auth, location-search, discovery/filter, map/list state and directions regressions also pass.
- `bash Tests/run-backend-db-tests.sh`: passed using a disposable local PostGIS database. All migrations apply; existing foundation and Day 12 checks still pass. Day 13 checks verify persisted name edits, missing-row recovery, idempotency, preservation of existing names, caller RLS, guest/anonymous rejection and cross-user read/write rejection. Supabase's Auth schema is stubbed in this local database.
- **Actual app simulator:** Home still retrieves 20 Google nearby results. Restroom Details and its embedded Google Map load, and both Home and Details open the shared Guest Profile; its Login/Create Account buttons open the correct existing forms. The normal guest navigation remains available.
- **Separate simulator-only UI fixture host:** rendered the actual production Profile views with fake services. Verified authenticated header, edit screen, a trimmed name save immediately changing the header, read-only email, logout confirmation and guest transition, activity placeholder destination, loading, recoverable error, light/dark modes, long name/email wrapping, large iPhone layout, and a 320×568-point compact viewport. Accessibility 3 text sizing exposed tab-label wrapping, which was fixed and rechecked. This compact viewport is a layout test, not a run on physical small-iPhone hardware.

The fixture host is in `Tests`, is excluded from the app target, and contains no Supabase SDK, keys, network calls or real accounts. Its screen is labelled “UI TEST FIXTURES • NO BACKEND.” It does not prove hosted signup/login, real Keychain persistence, or hosted profile writes. No live account credentials were entered and no hosted profile was edited in this task. Those end-to-end checks remain manual below. VoiceOver labels were inspected through accessibility output; a full spoken VoiceOver navigation audit remains a device check.

To rebuild the isolated visual host on an Apple Silicon Mac, run `bash Tests/build-profile-ui-host.sh`. It prints a temporary `.app` path. Install that app into a simulator with `xcrun simctl install booted <printed-path>` and launch `com.example.RestRoomFinder.ProfileUITests`. Optional launch arguments: `--guest`, `--error`, `--loading`, `--long`, `--dark`, `--large-type`, and `--compact`. Its fixture names reset on launch. The production app never uses these test services.

## Exact manual testing steps

1. Apply the Day 13 migration above. Run the RestRoomFinder app in Xcode; use your own verified test account. Do not share passwords or confirmation links in chat.
2. As guest, open Profile. Tap Log In and confirm Welcome Back; dismiss. Tap Create Account and confirm the signup form; dismiss. Return to Find and verify map/search/filter/details/directions remain accessible.
3. Log in as user A. Open Profile. Compare its displayed name to Table Editor → profiles.display_name and its email to Authentication → Users. Match the UUIDs, not the names. There should be no brief guest screen while the profile loads.
4. Open Edit Profile. Confirm email is read-only. Enter spaces only; expect a validation error and no update. Enter 51 characters; expect a limit error. Cancel and keep editing; then cancel/discard and verify the original name is retained.
5. Save `  Test Profile A  `. Expect the trimmed name immediately in the header and a matching `display_name` in Supabase. Rapidly tap Save; only one save should run. Terminate/relaunch the app without uninstalling. After session restoration, Profile should still show the saved name fetched from Supabase.
6. Open Profile while offline and pull to refresh. Expect a readable error and Retry. Reconnect and Retry. If editing offline, expect a save error, the retained draft and no false success. Session expiry can require reauthentication; guest restroom functionality remains available.
7. Tap Log Out → Cancel; remain signed in. Tap Log Out → Log Out; expect Guest Profile. Confirm the profile row still exists. Login as user B and verify B's name/email, never A's. Repeat quickly with a slow network to check stale results are ignored.
8. For recovery testing, use a disposable account/database fixture, not a valuable profile with linked records. A server-side missing profile should recover once with the correct UUID and no fabricated name. Set a name and retry; it must not be overwritten. The local SQL tests already exercise this without deleting hosted data.
9. Tap each activity/settings row. Expect an honest future-feature placeholder, no fake activity. Test back navigation. From Home and Details, verify Profile and Find preserve the underlying restroom flow.
10. Check an iPhone SE-sized simulator and a large iPhone. Repeat light/dark appearance, accessibility text sizes, a long name and email, keyboard use, loading/error states, and VoiceOver. Scroll to every row and logout; text should wrap or scroll naturally, without overlapping controls.
11. Regression: current location, Google Map markers, nearby list, area autocomplete/search, filters/sorting, marker/list selection, Details, and the directions chooser should still work as guest and signed in. Existing automated behavior tests pass, but a live Google/external-navigation walkthrough remains worthwhile before release.

## Files created (12)

Paths are relative to `/Users/wanghongwei/Desktop/BFAPP`.

| File | Purpose |
| --- | --- |
| `RestRoomFinder/Services/ProfileServicing.swift` | Injectable profile interface, safe errors and edit-name validation. |
| `RestRoomFinder/Services/ProfileService.swift` | Shared-client profile reads, name updates, missing-row recovery and SDK identity checks. |
| `RestRoomFinder/ViewModels/ProfileViewModel.swift` | Profile/save state, immediate update, retry and stale-account protection. |
| `RestRoomFinder/Views/Profile/ProfileView.swift` | Redesigned authenticated/guest Profile, activity/settings placeholders and existing logout flow. |
| `RestRoomFinder/Views/Profile/EditProfileView.swift` | Validated name editor, read-only email, save/cancel/discard UI. |
| `RestRoomFinder/Components/ProfileComponents.swift` | Avatar, menu row and section card components. |
| `supabase/migrations/202610090002_profile_recovery.sql` | Narrow idempotent recovery RPC under existing ownership policies. |
| `supabase/tests/profile_recovery.sql` | Recovery, persistence and cross-user/RLS database tests. |
| `Tests/ProfileTests.swift` | Profile state, validation, persistence abstraction and concurrency tests. |
| `Tests/ProfileUITestHost.swift` | Isolated production-view visual fixture app; never part of the shipping target. |
| `Tests/build-profile-ui-host.sh` | Builds the standalone simulator UI test app without backend dependencies. |
| `Configuration/DAY13_PROFILE.md` | This report, file inventory, setup and manual tests. |

## Files modified (7)

| File | Reason |
| --- | --- |
| `RestRoomFinder/Views/HomeView.swift` | Existing Profile action presents ProfileView instead of the minimal account sheet. |
| `RestRoomFinder/Views/RestroomDetailView.swift` | Same Profile entry from Details, sharing existing auth state. |
| `RestRoomFinder/Views/Authentication/AuthenticationView.swift` | Initial-page parameter for direct Login/Create Account navigation. |
| `RestRoomFinder/Components/AppBottomBar.swift` | Configurable selected tab, single-line tab captions and bounded navigation text scaling. |
| `Tests/NearbyDiscoveryTests.swift` | Runs the profile regression suite. |
| `Tests/run-nearby-tests.sh` | Includes profile types/view model/tests in the Swift test executable. |
| `Tests/run-backend-db-tests.sh` | Adds Day 13 SQL tests after applying existing/all migrations. |

No auth service/view-model logic, existing model, Supabase configuration, RLS policy, Google integration, search architecture, Xcode project file or package version was modified today. Xcode's synchronized source folder picks up the new production Swift files automatically.

## Remaining work

Apply the new hosted recovery migration and run real-account tests A–G above. Day 14 scope has not been supplied or started. Future work includes implementing the currently explicit activity/settings placeholders when requested; favorites/reviews/submissions/reports backends, avatar upload/Storage, account deletion, password changes and social login were not implemented today.
