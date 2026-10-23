# Day 14 — Cloud favorites and Saved Restrooms

Implemented a shared cloud-favorites flow, heart action in Restroom Details, Saved tab destinations, and Profile → Saved Restrooms. Existing cards had no favorite control to connect; their layout is preserved. Saved reuses RestroomCard and the existing RestroomDetailView/Details directions flow. No reviews, reports, submissions, photos or Day 15 features were implemented.

## Required hosted setup

1. Ensure the Day 11 schema, Day 12 profile trigger, and Day 13 recovery migration have already been applied in chronological order. Saving uses Day 13's `ensure_current_profile()` for accounts whose profile is missing.
2. Open Supabase → SQL Editor → New query. Run `supabase/migrations/202610100001_favorites.sql` once. Do not rerun earlier migrations if already applied.
3. No new Xcode key, SDK, package, or capability is required. Keep the existing publishable key and Google Places configuration.

**The Day 14 migration was tested locally, but was not applied to your hosted project in this task.** Real authenticated cloud operations require that manual setup and a verified test account you control. No hosted favorites were created or deleted during this implementation.

## Architecture and identity

`FavoriteButton / SavedRestroomsView → shared FavoritesViewModel → FavoritesService → existing SupabaseManager client → favorites + restrooms`

RootView owns one FavoritesViewModel and supplies it to Home, map/detail presentation, Profile and Saved. The service uses the existing client and actual non-anonymous SDK session, checks expiry, and verifies the expected account before/after operations. The existing AuthViewModel and `requireAuthentication()` helper are reused; no second auth manager, client, favorites table or persistent local store was created.

FavoritesViewModel holds an in-memory internal-UUID set and a Google Place ID → internal UUID lookup. A Google-derived UI UUID is never mistaken for the database UUID. Heart lookups are local; there is no database or Google request per card. Favorites are fetched in pages of 200 to avoid silently truncating the default PostgREST result limit.

Login/session restoration loads favorites from RootView without opening Profile. Logout/account changes clear relationships, ID lookups, transient place details and pending operations. Revision checks ignore late results from an earlier account. Foregrounding and pull-to-refresh reload cloud relationships. This provides cross-device persistence and refresh, not realtime subscriptions or offline synchronization.

Save/remove actions are serialized per place and independent of unrelated controls. UI changes occur only after the operation succeeds. A network error keeps the last confirmed state. If a server committed a write but the response was lost, a retry or refresh reconciles the state; inserts are idempotent. Removing a favorite never deletes a restroom. The selected Details view keeps a snapshot so unsaving there does not unexpectedly remove the screen from navigation.

## Google association and database changes

On an authenticated Save of a Google restroom:

1. Obtain identity from the SDK; read the caller's profile and invoke Day 13 recovery only if the row is missing.
2. Call `resolve_google_restroom(place_id)` with the original Google Place ID.
3. Reuse the unique existing restroom UUID, or create a minimal row with only Google Place ID and `source = google` plus database-generated UUID/timestamps/default status.
4. Insert the authenticated user's favorite under caller RLS using `ON CONFLICT DO NOTHING` behavior.
5. Read back the association and update shared UI state.

The existing `restrooms.google_place_id` unique constraint prevents duplicate anchors, including across accounts. The existing favorites primary key `(user_id, restroom_id)` prevents duplicate relationships. Existing indexes already cover the user prefix and `restroom_id`, so no redundant indexes were added.

**Google fields persisted in Supabase: Google Place ID only.** Names, addresses, coordinates, Google ratings, hours, business status, photos and provider attributions are not copied to Supabase. Normal nearby discovery creates zero database rows. Only an explicit Save may create an anchor. App-owned verified restroom data remains separate and can be read through the association.

The Day 11 schema already supported ID-only anchors, but favorites inserts originally allowed only verified restrooms. The migration adds a narrowly defined anchor case: source Google, status unverified, and no app-owned name/address/coordinates/creator. Registered users can read these identifier-only rows and favorite them. Pending/rejected records and unverified contributions remain excluded. An anchor is **never marked verified** merely because a user saved it.

## RLS and server privilege

All tables retain RLS. Favorites SELECT/DELETE ownership policies are unchanged: `user_id = auth.uid()` and registered account required. INSERT keeps the same ownership condition and accepts verified restrooms or the narrowly defined Google anchor. The app includes the captured SDK user UUID in the insert, rather than trusting a View-supplied ID; RLS compares it with the request's authenticated identity. This also prevents a request for account A from silently writing to account B after a session switch.

Ordinary clients still cannot directly insert or edit restrooms. A narrowly scoped SECURITY DEFINER function is used **only for resolving/creating the ID-only anchor**, with an empty search path, explicit registered-user check, bounded nonblank Place ID, fixed columns, no dynamic SQL and execution restricted to authenticated users. It cannot set verification, store Google display content, choose a favorite owner or alter another user's favorites. Favorite writes themselves use caller RLS; no iOS service-role/admin credentials or general RLS bypass are introduced.

A narrow new read policy makes identifier-only Google anchors visible to registered users. Private favorite relationships remain private. Database tests verify user B cannot read, insert as, or delete user A's favorites. Existing foundation tests still reject hidden/unverified contributions and anonymous-user writes.

## Saved content and Google API usage

**New Google Place Details requests were added for Saved display.** They request Place ID, name, coordinate, formatted address, business status, rating and rating count. No autocomplete session token is used for this non-autocomplete flow.

- Opening Saved refreshes Google information for missing/stale in-memory entries.
- A newly saved nearby result can reuse the content already displayed during this session.
- Successful details and failed attempts have a ten-minute in-memory freshness/backoff window.
- Pull to refresh explicitly refreshes details; requests already in progress are not duplicated.
- Details requests are sequential, limiting concurrency to one; view redraws and heart checks trigger no Google requests.
- The cache is transient and cleared on logout/account changes. There is no persistent Google-content cache.

Saved adds Google Maps attribution and displays returned third-party attributions; these are passed into the existing Details view when opened from Saved. Stable IDs follow the [Google Place ID storage exception](https://developers.google.com/maps/documentation/places/ios-sdk/policies). These additional Place Details requests can affect Google billing according to the requested fields and your project configuration.

App-owned accessibility, baby-changing, gender-neutral and free-entry fields come from the linked Supabase features row where existing RLS permits reading it. Unknown data stays unknown. No Google cleanliness value or fake app review score is invented; review aggregates/submissions are outside today's scope. Distance is recomputed from the available user location, not persisted.

If an anchor is no longer readable or Google cannot return current details, its favorite remains listed and removable. Coordinates are not fabricated and directions/details are unavailable until usable place data exists. If an in-session detail refresh fails, existing content is labelled as such. A backend list failure shows an error/Retry, not “no favorites.”

## Guest behavior and navigation

Guest Save calls the existing authentication requirement helper and opens the existing Create Account / Log In / Continue as Guest flow. It does not call the favorites service or invent local/cloud favorites. After signing in, tap Save again; the app does not silently replay a prior guest action.

Guests opening Saved see an account prompt and Explore action. Authenticated users see loading, loaded, empty or recoverable error state. Profile → Saved and existing bottom Saved controls share the same screen/state. Explore returns to the underlying restroom experience. Heart labels name the restroom, indicate saved state, and use existing minimum tap targets. Saved uses the app's adaptive monochrome design.

## Tests completed

- Entire final simulator Xcode project builds successfully. Only the pre-existing AppIntents metadata extraction warning; no new Swift compiler warnings.
- Swift suite `bash Tests/run-nearby-tests.sh` passes. Added coverage: stable Place ID vs internal UUID, no per-card queries, save/remove confirmation, failure retention, empty vs error, retry, duplicate taps, persisted-service reload, account clearing, late A save/list ignored after B signs in, unavailable-record removal, Google failure retention and refresh recovery, freshness/cost bounds.
- Disposable local PostGIS tests `bash Tests/run-backend-db-tests.sh` pass. All migrations plus Day 11–13 checks still pass. New checks cover one anchor per Place ID, one favorite per user/place, no Google display fields persisted, no false verification, cross-user isolation, guest/anonymous rejection, and unsaving without deleting the restroom or another user's relationship.
- Real app simulator: nearby Google results still load, existing Details/embedded Google Map loads, and guest Save opens the real authentication UI.
- Separate simulator fixture host: production Saved view/card/heart components checked for save/unsave synchronization, detail-route retention after removal, direct list removal, empty state and dark error/Retry state. The fixture host's Details/directions destinations are explicit test stubs; real Details was checked in the full app. No fixture data enters the shipping app or Supabase.

**Not claimed:** real hosted authenticated saves, cloud relaunch persistence or two-device/account end-to-end tests. Those require applying the migration and signing in with test accounts. Local SQL tests and injected-service tests are not substitutes for those final live checks. No user password was requested or entered in this task.

## Manual tests A–K and dashboard verification

1. Apply the migration(s) above and run the RestRoomFinder scheme in Xcode.
2. **A — Guest:** log out, open a restroom, tap Save. Expect authentication. Close it; the heart must remain unsaved. Map/search/details/directions remain usable.
3. Log in as verified user A. **B — Save:** open a real nearby restroom and tap Save. Expect SAVED/filled heart after success.
4. In **Authentication → Users**, copy A's UUID. In **Table Editor → favorites**, verify `user_id` equals that UUID. Copy `restroom_id`; find the corresponding row in **restrooms**. It should have the original Google Place ID, with Google-origin display fields null for a new anchor and status unverified.
5. **C — Duplicate:** rapidly tap Save while the request is active; only one operation should run. Save/unsave/save again after completion is an intentional toggle. Confirm at most one `(user_id, restroom_id)` row. A second account saving the same Google place should reuse the same restroom UUID, with its own favorite relationship.
6. **E — List:** save a second restroom. Open the Saved tab and then Profile → Saved Restrooms; both use the same two associations. **F — Details:** open a card's arrow, check existing Details, and open its directions chooser.
7. **D — Remove:** tap the filled heart in Details. Stay on Details and confirm it becomes unsaved. Return to Saved; that row should disappear. Also test Remove from Saved directly. In Supabase, only the favorite row disappears; the restroom anchor remains.
8. **G — Persistence:** save a place, stop the app completely and relaunch without uninstalling. After auth/session restoration, the place remains saved. On a second device signed in as A, open Saved or pull to refresh; it should appear there too. Google details may load separately.
9. **H/I — Isolation:** log out. Saved must show guest content with no A favorites. Sign in as B; only B favorites should appear. Switch back to A and confirm A's cloud records remain. Try this while a load is slow to check stale results do not flash into B's list.
10. **J — Failure:** with the device offline, try saving an unsaved place. Expect a readable error with no permanently filled heart. Try removing a saved place offline; it should remain until a confirmed delete. Reload Saved offline; expect an error, not an empty state. Reconnect and Retry/pull to refresh.
11. **K — RLS:** run the local database test runner to verify caller-role isolation. Supabase's administrative Table Editor shows all users by design and does not prove client RLS. Do not disable RLS or add permissive policies to make the UI work.
12. For a failed/retired Google place, the association must remain removable. Test empty state/Explore, light/dark modes and larger text. Confirm no copied Google payload appears in the restrooms table.
13. Regression: account creation/email verification, login/logout, session persistence, Profile/Edit Profile, map/location, nearby/area search, filters, selection sync, Details and directions. Existing automated behavioral tests pass; repeat these live flows before release.

## Exact file inventory

Paths are relative to `/Users/wanghongwei/Desktop/BFAPP`.

### Created (9)

| File | Purpose |
| --- | --- |
| `RestRoomFinder/Models/FavoriteRecord.swift` | Cloud relationship/anchor DTOs, transient place response, service interfaces and safe errors. |
| `RestRoomFinder/Services/FavoritesService.swift` | Shared Supabase client favorites fetch/save/delete and minimal Google resolution. |
| `RestRoomFinder/ViewModels/FavoritesViewModel.swift` | Shared account cache, confirmed mutations, stale-response guards and transient place refresh. |
| `RestRoomFinder/Components/FavoriteButton.swift` | Reusable accessible heart, auth gate, per-action loading and error feedback. |
| `RestRoomFinder/Views/Saved/SavedRestroomsView.swift` | Shared guest/loading/error/empty/list Saved UI and existing Details/directions navigation. |
| `supabase/migrations/202610100001_favorites.sql` | Narrow Google-anchor resolver and RLS support without broad table write access. |
| `supabase/tests/favorites.sql` | Duplicate/ownership/anchor/removal database tests. |
| `Tests/FavoritesTests.swift` | Favorites identity, state, failure, account switching and freshness tests. |
| `Configuration/DAY14_FAVORITES.md` | This implementation report and setup/test guide. |

### Modified (12)

| File | Reason |
| --- | --- |
| `RestRoomFinder/App/RootView.swift` | Owns shared favorites and synchronizes login/logout, restored sessions, foreground refresh and location. |
| `RestRoomFinder/Services/PlacesService.swift` | Adds current saved-place details lookup through the existing Google SDK. |
| `RestRoomFinder/Components/RestroomCard.swift` | Optional details action for Saved's stable navigation snapshot; corrected unknown-distance wording. |
| `RestRoomFinder/Views/HomeView.swift` | Connects the existing Saved tab. |
| `RestRoomFinder/Views/RestroomDetailView.swift` | Connects heart/Saved actions, supports saved-place attribution, and supplies preview dependencies. |
| `RestRoomFinder/Views/Profile/ProfileView.swift` | Replaces Saved placeholder with real shared Saved UI; updates guest benefits copy. |
| `RestRoomFinder/Views/Authentication/AuthenticationView.swift` | Updates welcome copy now that saving is available. |
| `Tests/NearbyDiscoveryTests.swift` | Runs the favorites regression suite. |
| `Tests/run-nearby-tests.sh` | Compiles favorites types, state and tests. |
| `Tests/run-backend-db-tests.sh` | Runs favorites SQL checks after existing migrations/tests. |
| `Tests/ProfileUITestHost.swift` | Extends isolated UI fixtures to Saved; includes explicit test-only detail/directions stubs. |
| `Tests/build-profile-ui-host.sh` | Includes production Saved/heart/card files in the isolated visual host. |

No auth logic, client configuration, API-key values, Restroom model, package versions, existing tables, Google search logic or Xcode project file was replaced. No prior persistent local-favorites store existed to migrate. Xcode's synchronized source folder includes the new app files automatically.

## Remaining work

Apply the hosted migration and run real-account/relaunch/cross-device checks above. Day 15 scope has not been supplied and was not started. Reviews, reports, submissions, photos, offline syncing, realtime subscriptions and other future features remain outside Day 14.
