# Day 16 — Add a Restroom and private user submissions

Day 16 adds authenticated pending submissions, a form with tri-state features, current/map/coordinate location selection, duplicate warnings, My Submissions, private details, and pending edits. No submission is automatically copied to the public restroom dataset or public map.

The implementation has been built and tested locally. Hosted setup and the live authenticated submission/restart checks below remain necessary. No hosted migration, account creation, submission or moderation action was performed in this task.

## Required setup

1. Use the same Supabase project configured in `Configuration/Supabase.local.xcconfig`.
2. The existing Day 11–15 migrations should already be applied. In particular, a missing account profile needs Day 13's `ensure_current_profile()`. Check with `select to_regprocedure('public.ensure_current_profile()');` and apply the existing Day 13 recovery migration only if missing. Do not rerun already-applied foundation/favorites/reviews migrations.
3. Run **`supabase/migrations/202610220001_restroom_submissions.sql`** once in Supabase SQL Editor. It runs as a transaction and requests an API schema-cache reload. If the API still reports missing setup after successful application, run `notify pgrst, 'reload schema';` in the same project.
4. Run the RestRoomFinder scheme in Xcode. No new key, SDK, package, location capability or Google Cloud API is required. Existing location permission text/configuration is reused.

## Entry and architecture

Authenticated path: **Profile → My Submissions → Add a Restroom**. Guests have an Add a Restroom entry on Profile; it opens Create Account / Log In / Cancel through the existing authentication flow. Browsing, search, maps, details and reviews remain available to guests. After signing in, tap Add a Restroom again.

`AddRestroomView → AddRestroomViewModel → RestroomSubmissionService → existing SupabaseManager → restroom_submissions`

`MySubmissionsView / SubmissionDetailView → MySubmissionsViewModel → the same service`

RootView owns the shared submissions list state and supplies the existing LocationManager to the new screens. Existing Restroom, AuthViewModel, AuthService, Supabase client and GoogleMapView are reused. The submission DTO represents a private contribution, not another canonical restroom model. Views perform no Supabase queries.

The form view model owns a single submission state: idle, locating, checking, duplicate warning, submitting, success or error. It validates before calling the backend, snapshots the draft for duplicate confirmation, blocks concurrent writes, and ignores results after cancellation/account change. Fields and submit are disabled during checking/writing. The footer keeps submit/progress/errors visible while the form scrolls.

The service obtains the actual SDK session identity through the existing RestroomIdentityService. IDs passed by Views only guard against stale-account requests. Every read/write checks identity before and after asynchronous work; owner constraints and RLS enforce the request's authenticated user. My Submissions clears private data on logout/account change and ignores late responses from the previous account.

## Form and location

Required: a trimmed 1–200-character name and finite coordinates in latitude −90…90 / longitude −180…180. Address is optional (up to 1,000 characters). Notes are optional, trimmed, and capped at 1,000 characters. Unicode scalar counts match PostgreSQL character limits. Blank address/notes become NULL.

Accessibility, baby changing, gender neutral, free entry, family restroom and 24-hour opening each use **Yes / No / Unknown**. Unknown is serialized as NULL; editing a known value back to Unknown explicitly clears the database value rather than dropping the update key.

- **Use Current Location** reuses RootView's LocationManager. A fresh authorized location can be used immediately; otherwise the existing manager requests a fix/permission. Stale or invalid fixes are rejected. Denied, restricted, timeout/unavailable states show an error and retain Choose on Map as an alternative. Coordinates are displayed for confirmation; users are told device location can be approximate.
- **Choose on Map** uses GoogleMapView with a small optional coordinate-selection callback. Tap a point or move the map beneath a fixed pin, then confirm. Existing Explore marker/camera callbacks retain their behavior.
- The map's visual fallback center is **not** silently accepted as a submission location. A new picker starts without a selected coordinate; a user gesture or explicit coordinate entry is required. An existing draft can retain its already selected coordinate.
- Labelled latitude/longitude fields provide an accessible alternative to map gestures and work when the map is unconfigured. Use Entered Coordinates validates the values and recenters the map. Confirmation requires the fields to match the selected coordinate, so uncommitted/invalid edits cannot silently confirm an older location.
- Address is user-entered. No reverse geocoder or extra Places request is made just to obtain a formatted address.

The focused picker and private submission preview use the existing Google Maps SDK, including its normal map loading. No new Google Places calls were introduced.

## Duplicate protection

Checks run before a new submission or pending edit:

1. Already-loaded nearby Google/restroom results are checked locally by real geographic distance, within 50 meters. No additional Places search is triggered.
2. `submission_duplicate_candidates` checks verified public Supabase restrooms within 50 meters and the caller's own pending submissions within 25 meters. It excludes the current edit and same request ID. Results are bounded to ten. Other users' private pending contributions never appear in this endpoint.
3. Candidates are deduplicated by Google identity or internal identity. Names help identify the candidate in the UI; a name alone never blocks a submission.

The server RPC is SECURITY INVOKER and retains caller RLS. Its geography predicates use [PostGIS ST_DWithin](https://postgis.net/docs/ST_DWithin.html), which takes meter distances for geography. A SELECT grant on the static `gis.spatial_ref_sys` reference catalog is necessary for these distance calculations; no writes or broad grant on GIS/application tables was added. Keep `gis` out of the exposed Data API schemas.

The warning offers **View Existing / Submit Anyway / Cancel**. Public candidates open existing Restroom Details; the owner's pending candidates open private submission details. A duplicate-check failure is explicitly shown as unavailable and requires Submit Anyway or Cancel. It never counts as a successful “no duplicates” check. Fuzzy proximity does not automatically reject a legitimate separate restroom. Moderation makes the final decision.

Each new form has a stable request UUID. The database enforces UNIQUE(user_id, client_request_id), and insert uses ON CONFLICT DO NOTHING behavior. A retry in the same form after a lost response reads the already-created row. If the user changed the draft after an earlier request was accepted, the app directs them to review My Submissions instead of pretending the newer draft was inserted. A new form has a new request ID and still runs duplicate checks.

## Database and RLS changes

The existing status enum (`pending`, `approved`, `rejected`), name/coordinate constraints, timestamp defaults/trigger and ownership policies are reused.

The migration adds:

- Six nullable Boolean feature columns.
- `client_request_id` plus the owner/request unique constraint. Existing rows receive generated request IDs.
- `approved_restroom_id`, nullable FK to restrooms. A check allows a link only when status is approved. No link is fabricated or set by iOS.
- Future moderation fields: `reviewed_by` (profile FK), `reviewed_at`, private `moderation_notes`, and owner-readable `rejection_reason`, with bounded text.
- A 1,000-character notes CHECK, marked NOT VALID to retain historical notes without truncation; inserts and updates enforce the new limit. An existing longer historical note must be shortened before editing that row.
- A trigger trimming name/address/notes and turning empty optional text into NULL.
- Owner/date/id paging index and an owner/coordinate index for pending duplicate candidates.
- The bounded duplicate-check RPC and its specific PostGIS catalog read grant.

Permissions:

| Actor | Insert | View | Update | Moderate / delete |
| --- | --- | --- | --- | --- |
| Guest / anonymous Auth | No | No private submissions | No | No |
| Registered user A | Own submission, pending only | Own submissions, all statuses | Own pending content/features only | No |
| Registered user B | Own only | Cannot read A's submissions | Cannot modify A's rows | No |
| Future trusted server/admin tooling | Privileged workflow | As authorized by server tooling | Controlled moderation | Outside iOS; not implemented today |

RLS stays enabled. INSERT requires `auth.uid() = user_id`, registered identity and pending status. UPDATE checks both the existing and resulting row are owned/pending. Column grants prevent changing user_id, request ID, status, approval link, timestamps, reviewer identity or moderation fields. Approved/rejected rows are read-only to ordinary users. Deletion/withdrawal is deferred; no client DELETE grant was added.

Authenticated SELECT is restricted to the app-visible columns. Even the owner cannot request internal reviewer UUID/moderation notes. Submitter UUID remains internal; no email, account metadata or UUID is displayed in submission screens. Rejection reason can be read only by its owner.

A moderation race is handled on the server: an edit filters by ID, authenticated owner and pending status. If moderation already changed the status, the update affects no row and returns a readable refresh instruction.

## My Submissions and details

The list fetches only the SDK user's rows, with RLS enforcing ownership even if parameters are manipulated. It loads 20 items with a 21st-row lookahead and Load More, newest first with an ID tie breaker. Loading, true empty, network/setup error and page error remain separate; Retry/pull-to-refresh reconcile current status.

A confirmed save updates shared state and refreshes the list. Details show the real saved name, optional address, coordinates/private map preview, all six feature states, notes, status and localized submitted date. Pending rows offer a prefilled edit form. Approved/rejected rows do not offer editing. If supplied by moderation, a rejected row shows its rejection reason.

Approved canonical linking is prepared in the schema; navigation to a public canonical row is deferred. No public link is invented for an unlinked approval. Withdrawal/deletion and resubmission after rejection are also deferred to keep this day focused.

## Moderation and public promotion strategy

Today all ordinary inserts enter **restroom_submissions only** with pending status. No trigger creates a restrooms row, copies features, changes verification, or inserts a public map marker. The pin in private submission details is only the owner's preview.

Future privileged moderation should perform a transaction:

1. Lock/recheck the pending submission and investigate duplicates; never trust client status or an admin flag in user-editable metadata.
2. Reject with reviewer identity/time, internal notes and an appropriate owner-visible rejection reason; or approve by reusing/creating a canonical restroom.
3. For a new community restroom, use the existing restrooms model with source `user_submission`, trusted/verified status and **google_place_id = NULL** unless a legitimate independent link exists.
4. Copy/normalize the six tri-state features into restroom_features, preserving NULLs.
5. Set submission status, reviewed metadata and approved_restroom_id together in the transaction.
6. A later discovery layer can merge verified Supabase restrooms with Google Places. Pending/rejected submissions must never enter public discovery.

This requires protected server/admin tooling or a secured Edge Function; no moderator dashboard, moderation endpoint, service-role key or admin credential was added to iOS.

## Testing completed

- Full Xcode simulator project builds successfully; only the existing AppIntents metadata warning remained.
- `bash Tests/run-nearby-tests.sh` passes, including existing auth/profile/favorites/reviews/ratings/search/filter/map-selection/directions regressions. New tests cover invalid name/missing/NaN/out-of-range coordinates and notes with zero backend writes, NULL/true/false features, fresh/stale locations, nearby duplicate warnings/cancel/override, duplicate-check failure, stable retry request IDs, rapid-tap suppression, stale/cancelled saves, pending edits, approved-edit refusal, list paging/reload, account clearing and late A response isolation, and error/empty/retry distinction.
- `bash Tests/run-backend-db-tests.sh` passes all Day 11–16 SQL tests in disposable local PostgreSQL/PostGIS. New role tests cover guest/anonymous rejection, own-only data, spoofed owners, self-approval/status/link/moderation denial, private moderator-column denial, required/bounded fields, NULL text/features, idempotent inserts, pending edits and Unknown restoration, duplicate geography and privacy, excluding own edit/retry, invalid duplicate coordinates, approved/rejected edit denial, and no public restroom creation.
- Explicitly labelled, in-memory simulator fixture: new form validation, all Unknown defaults, current-location boundary, duplicate warning and Submit Anyway, success/Pending message, new row in My Submissions, private details, prefilled edit and coordinate-entry/confirmation round trip, readable status rows, and guest Create Account / Log In / Cancel checked. Fixture map/location/auth/service implementations are test stubs; fixture data does not reach Supabase or ship in the app.
- Final real app simulator: nearby Google results and live community ratings loaded; Profile showed the new Add a Restroom entry; the guest authentication dialog presented Create Account / Log In / Cancel. The final app build was installed/launched and the disposable fixture app removed.
- Hosted authenticated insert/edit/restart, real map gesture selection, denied-device-location interaction, physical VoiceOver and full device/account regression remain manual verification. No hosted setup/operation is claimed from local SQL/fixture tests.

## Exact manual testing instructions

After applying migrations and running the real Xcode app:

1. **Guest:** Profile → Add a Restroom. Expect Create Account / Log In / Cancel; Cancel writes nothing. Browsing, search and directions should still work.
2. **Required fields:** sign in as A. Profile → My Submissions → Add a Restroom. Submit empty: readable name error and no row. Enter a name but no coordinate: blocked. Test invalid coordinates (latitude 91, NaN/non-number) in Choose on Map. Confirmation must not accept an invalid/uncommitted coordinate edit.
3. **Location:** Use Current Location and verify displayed coordinate. Test first permission request, deny/restrict/unavailable states, then choose on map instead. Move/tap the real map, confirm, and check the returned coordinate. Open a new picker with no prior selection: it must not accept the visual fallback center until you choose a location. Manual coordinate entry should recenter the map and require confirmation.
4. **Features/text:** keep all features Unknown; leave address blank and notes whitespace. Submit. Check NULL values in Supabase. Repeat or edit with Yes/No values. Set a known feature back to Unknown and clear notes; expect actual NULL updates. Notes >1,000 characters must be rejected before writing.
5. **Duplicate warning:** select near a loaded Google restroom or verified Supabase restroom, or near your own pending submission. Expect View Existing / Submit Anyway / Cancel. Cancel retains the draft without creating a row. View Existing opens the appropriate existing detail. Submit Anyway may create a separate pending submission. Check failure/offline must show that duplicate detection could not complete.
6. **Submit:** rapidly tap Submit. Expect one pending row, a success message saying it requires review, and a single entry in My Submissions. If a write response is lost, retry in the same form; request ID should prevent another row. Starting a separate form remains a distinct contribution and runs duplicate warnings.
7. **Details/edit:** open the new item, verify name/location/features/notes/status/date. Edit while pending and save; same ID/request ID, updated content/timestamp, status still pending. Pull to refresh My Submissions.
8. **Persistence:** stop/relaunch the real app without uninstalling, restore/sign in as A and reopen My Submissions. The saved row must remain.
9. **Account privacy:** sign out A and sign in B. B must not see A's private rows, details, notes or pending duplicate candidates. Repeat while a request is slow. The local role tests verify the database cannot be manipulated to edit A's rows as B.
10. **Status security:** run the local SQL suite to reproduce denied client status/owner/link/moderation writes. To simulate moderation in a disposable test project, an authorized database owner can change a test row to approved or rejected. Refresh as A: status text changes, editing disappears. An in-flight pending edit after approval must fail. Do not add client moderation grants to perform this test.
11. **No publication:** immediately after submission, compare restrooms rows/map results. There must be no new trusted/public restroom, no copied feature row and no public pending marker. A submission does not need a Google Place ID.
12. **Failure/retry/accessibility:** test offline list/submit/edit, reconnect and Retry; no false success/empty list. Test larger text, screen reader labels/statuses/Yes-No-Unknown, coordinate entry, keyboard scrolling, and light/dark mode.
13. **Regression:** account creation/confirmation/login/logout/session restoration; Profile/Edit Profile; Favorites/Saved; reviews/cleanliness; Google Maps/Places; map/list selection; location search; filters; Details/directions. Automated behavior checks pass; repeat real hosted/device flows before release.

## Supabase Dashboard verification

- **Table Editor → restroom_submissions:** check id, actual auth user_id, name, latitude/longitude, optional address/notes, six Boolean fields, status `pending`, client_request_id, created_at/updated_at, and NULL approved_restroom_id. The request UUID is an idempotency identifier, not an owner identity.
- **Authentication → Users:** copy A's user UUID and compare to row user_id. No email/UUID appears publicly in the app.
- **Table Editor → restrooms / restroom_features:** pending insertion and edits create neither a canonical restroom nor public feature rows. Any approved link must have been supplied by privileged moderation, not the client.
- **Database → Policies/permissions:** verify RLS remains enabled; own-only SELECT/INSERT; UPDATE own pending only; no ordinary status/user/approval/moderator-field writes or DELETE. Dashboard SQL Editor/Table Editor normally use administrative access and cannot by themselves prove caller RLS; use the local role tests.
- **Database → Functions:** submission_duplicate_candidates is security-invoker, registered-only, bounded and read-only. Internal moderation notes/reviewer ID are not in the client SELECT grant.

## Remaining work / Day 17

Hosted setup and the live-account/device tests above remain Day 16 verification work. Withdrawals, rejected resubmission, public approved-link navigation and merged verified-Supabase discovery are deferred. Recommended Day 17 work is a secured moderation/promotion workflow and approved community-restroom discovery, subject to the next brief. Day 17 has not been started. Reports, photos, notifications, AI verification and a full admin dashboard were not implemented.

## Exact file inventory

### Created (15)

| File | Purpose / reason |
| --- | --- |
| [Configuration/DAY16_SUBMISSIONS.md](/Users/wanghongwei/Desktop/BFAPP/Configuration/DAY16_SUBMISSIONS.md) | This setup, architecture, inventory and verification report. |
| [RestRoomFinder/Components/AddRestroomButton.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Components/AddRestroomButton.swift) | Reusable existing-auth gate and contribution entry. |
| [RestRoomFinder/Components/SubmissionFeaturePicker.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Components/SubmissionFeaturePicker.swift) | Reusable tri-state input and readable status badge. |
| [RestRoomFinder/Models/RestroomSubmission.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Models/RestroomSubmission.swift) | Submission/status/tri-state models, coordinate/text validation, duplicate snapshots and service interface. |
| [RestRoomFinder/Services/RestroomSubmissionService.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Services/RestroomSubmissionService.swift) | Shared-client owner-checked paging, duplicate checks and idempotent insert/pending update. |
| [RestRoomFinder/ViewModels/AddRestroomViewModel.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/ViewModels/AddRestroomViewModel.swift) | Validated form state, frozen duplicate confirmation, submission and cancellation guards. |
| [RestRoomFinder/ViewModels/MySubmissionsViewModel.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/ViewModels/MySubmissionsViewModel.swift) | Private list/detail state, paging, refresh and account isolation. |
| [RestRoomFinder/Views/Submissions/AddRestroomView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Submissions/AddRestroomView.swift) | Native monochrome form, shared location use and pending-success feedback. |
| [RestRoomFinder/Views/Submissions/MySubmissionsView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Submissions/MySubmissionsView.swift) | Actual owner-only list with loading/error/empty/paging states. |
| [RestRoomFinder/Views/Submissions/SubmissionDetailView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Submissions/SubmissionDetailView.swift) | Private saved content/status/location and pending editing. |
| [RestRoomFinder/Views/Submissions/SubmissionDuplicateWarning.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Submissions/SubmissionDuplicateWarning.swift) | Warning, existing-item preview, override/cancel and private lookup. |
| [RestRoomFinder/Views/Submissions/SubmissionLocationPicker.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Submissions/SubmissionLocationPicker.swift) | Focused existing-map selection and validated coordinate fallback. |
| [Tests/SubmissionTests.swift](/Users/wanghongwei/Desktop/BFAPP/Tests/SubmissionTests.swift) | Form/list validation, concurrency, retry, location, duplicate and account regressions. |
| [supabase/migrations/202610220001_restroom_submissions.sql](/Users/wanghongwei/Desktop/BFAPP/supabase/migrations/202610220001_restroom_submissions.sql) | Feature/idempotency/moderation foundation, column privileges, pending-update RLS and duplicate RPC. |
| [supabase/tests/submissions.sql](/Users/wanghongwei/Desktop/BFAPP/supabase/tests/submissions.sql) | Database validation, privacy, ownership, status, duplicate and no-publication tests. |

### Modified (8)

| File | Purpose / reason |
| --- | --- |
| [RestRoomFinder/App/RootView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/App/RootView.swift) | Own/inject shared submissions state and the existing LocationManager; register loaded nearby candidates. |
| [RestRoomFinder/Components/GoogleMapView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Components/GoogleMapView.swift) | Optional focused location selection via existing delegate, preserving Explore behavior. |
| [RestRoomFinder/Views/Profile/ProfileView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Profile/ProfileView.swift) | Replace My Submissions placeholder and provide guest contribution entry. |
| [Tests/NearbyDiscoveryTests.swift](/Users/wanghongwei/Desktop/BFAPP/Tests/NearbyDiscoveryTests.swift) | Run submission regression tests alongside existing suites. |
| [Tests/ProfileUITestHost.swift](/Users/wanghongwei/Desktop/BFAPP/Tests/ProfileUITestHost.swift) | In-memory submission fixtures, auth/location/map stubs and UI paths. |
| [Tests/build-profile-ui-host.sh](/Users/wanghongwei/Desktop/BFAPP/Tests/build-profile-ui-host.sh) | Compile production submission UI into the isolated fixture host. |
| [Tests/run-backend-db-tests.sh](/Users/wanghongwei/Desktop/BFAPP/Tests/run-backend-db-tests.sh) | Run Day 16 database tests with existing migrations/regressions. |
| [Tests/run-nearby-tests.sh](/Users/wanghongwei/Desktop/BFAPP/Tests/run-nearby-tests.sh) | Compile submission models/view-models/tests. |
