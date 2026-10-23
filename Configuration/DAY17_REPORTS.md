# Day 17 — Report Incorrect Information

Reporting is implemented in the iOS app with Supabase persistence, private My Reports, validation, request retries, and secure pending moderation. **The hosted migration has not been applied by Codex. Live authenticated submission/restart testing remains necessary after the setup below.** No hosted reports, account changes, or moderation actions were created during implementation.

## Required setup

1. Use the existing Supabase project configured locally for this app. Keep the existing publishable key; no new key or package is required.
2. Ensure the earlier migrations through Day 16 have been applied. Do not rerun already-applied migrations. The shared `resolve_google_restroom` and `ensure_current_profile` functions must exist.
3. Open [202610220002_reports.sql](/Users/wanghongwei/Desktop/BFAPP/supabase/migrations/202610220002_reports.sql), copy its entire contents into **Supabase Dashboard → SQL Editor → New query**, and run it **once**. It is transactional and reloads the Data API schema cache after commit.
4. Build and run the **RestRoomFinder** scheme in Xcode. If reporting still says setup is missing, confirm this is the same Supabase project configured in Xcode; after confirming successful migration, run `notify pgrst, 'reload schema';`.

The migration preserves existing rows and extends the existing reports table. It renames legacy enum labels: `closed → temporarily_closed`, `not_public → not_publicly_accessible`, `wrong_hours → incorrect_opening_hours`, `dirty → unclean_restroom`, `duplicate → duplicate_restroom`, and status `reviewed → in_review`. Existing SQL clients/scripts using those old labels must switch to the new labels. It adds `permanently_closed`. No table or row is deleted. Historical reports with longer comments or insufficient Other explanations are retained; new constraints are NOT VALID for historical data, while new writes enforce them.

## Files created — exact inventory

| File | Purpose |
| --- | --- |
| [RestroomReport.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Models/RestroomReport.swift) | Typed categories/statuses, private report model, trimmed/validated draft, service contract, friendly errors and optional external Place ID link. |
| [ReportService.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Services/ReportService.swift) | Existing Supabase client/session/resolver integration; submit, fetch own page, fetch own report; idempotent confirmed writes. |
| [ReportViewModel.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/ViewModels/ReportViewModel.swift) | One form's draft, validation, submitting/error/success state, tap lock and cancellation generation. |
| [MyReportsViewModel.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/ViewModels/MyReportsViewModel.swift) | Account-scoped history, pagination, confirmed-submit synchronization, private detail retrieval and stale-response protection. |
| [ReportRestroomButton.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Components/ReportRestroomButton.swift) | Existing REPORT action; existing Create Account / Log In / Cancel flow for guests, report sheet for authenticated users. |
| [ReportView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Reports/ReportView.swift) | Monochrome report form, single category selection, details field, validation/errors, fixed submit control and confirmed success. Includes reusable text/symbol status badge. |
| [MyReportsView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Reports/MyReportsView.swift) | Private history with loading, empty, error/retry, localized dates, current statuses, refresh and Load More. |
| [ReportDetailView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Reports/ReportDetailView.swift) | Refetches an owned report by ID; displays available comment/moderation dates and honest status explanations. |
| [202610220002_reports.sql](/Users/wanghongwei/Desktop/BFAPP/supabase/migrations/202610220002_reports.sql) | Schema extension, enum migration, indexes, constraints, server duplicate protection and protected column grants. |
| [reports.sql](/Users/wanghongwei/Desktop/BFAPP/supabase/tests/reports.sql) | Local role-based SQL tests for ownership, moderation protection, validation, identity resolution and unchanged public data. |
| [run-report-concurrency-tests.sh](/Users/wanghongwei/Desktop/BFAPP/Tests/run-report-concurrency-tests.sh) | Two-connection local PostgreSQL tests for simultaneous identical reports and same-request retries. |
| [ReportTests.swift](/Users/wanghongwei/Desktop/BFAPP/Tests/ReportTests.swift) | Async form/history tests: validation, failure/retry, rapid taps, logout/account races, paging, identity and Google link encoding. |
| [DAY17_REPORTS.md](/Users/wanghongwei/Desktop/BFAPP/Configuration/DAY17_REPORTS.md) | This completion report, migration instructions and manual verification checklist. |

## Files modified — exact inventory

| File | Change |
| --- | --- |
| [RootView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/App/RootView.swift) | Creates one shared reports store, injects it and clears its private state when authentication changes. |
| [RestroomDetailView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/RestroomDetailView.swift) | Replaces existing report placeholder with the protected report action; supplies the reports dependency in its preview. |
| [ProfileView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Profile/ProfileView.swift) | Connects existing My Reports menu item and updates its accessibility hint. |
| [NearbyDiscoveryTests.swift](/Users/wanghongwei/Desktop/BFAPP/Tests/NearbyDiscoveryTests.swift) | Runs reporting tests alongside existing regression suites. |
| [run-nearby-tests.sh](/Users/wanghongwei/Desktop/BFAPP/Tests/run-nearby-tests.sh) | Compiles the report model/view models/tests into the existing Swift test runner. |
| [run-backend-db-tests.sh](/Users/wanghongwei/Desktop/BFAPP/Tests/run-backend-db-tests.sh) | Runs new report SQL and concurrency tests against a disposable local PostGIS database. |
| [backend_foundation.sql](/Users/wanghongwei/Desktop/BFAPP/supabase/tests/backend_foundation.sql) | Updates legacy report category fixtures and supplies authenticated claims for the report fixture. Existing assertions remain. |
| [ProfileUITestHost.swift](/Users/wanghongwei/Desktop/BFAPP/Tests/ProfileUITestHost.swift) | Adds report-only fixture services/routes/dependencies for native UI verification. Test-only data is outside the app target and never reaches Supabase. |
| [build-profile-ui-host.sh](/Users/wanghongwei/Desktop/BFAPP/Tests/build-profile-ui-host.sh) | Includes production reporting views/models/view models in the isolated UI host. |

No package, key/config secret, original model, discovery service, map, rating, favorites, authentication service or submission service was modified.

## Reporting architecture

```text
ReportView → ReportViewModel → ReportService
                                      ↓
                       existing SupabaseManager / SDK session
                                      ↓
                             public.reports + RLS

Profile → My Reports → MyReportsViewModel → same ReportService
```

The service validates the expected account against the actual authenticated Supabase SDK session before and after asynchronous operations. The inserted owner is taken from that session, not arbitrary view state. The database independently verifies `auth.uid()` and rejects anonymous Auth users.

The existing `RestroomIdentityService` prepares an account profile if missing and resolves Google Place IDs through the existing narrow `resolve_google_restroom` RPC. It reuses a unique ID-only Google anchor, without storing name/address/coordinates or publishing a placeholder. Canonical approved user/admin restrooms use their existing UUID directly. Reporting never matches by name.

No report operation changes a restroom, feature, review, cleanliness rating, map marker, visibility or external Google listing. A report is a private, unverified claim until authorized moderation.

## Database changes and security

The existing `comment` column is retained as the report's optional description. Swift presents it as additional details. The migration adds:

- `reviewed_at` and `resolved_at`, both nullable and readable by the owner.
- `client_request_id`, backfilled with generated UUIDs, plus UNIQUE(user_id, client_request_id).
- A 1,000-code-point comment CHECK and an Other explanation CHECK requiring at least 10 trimmed characters, preserving legacy rows using NOT VALID.
- An own-history `(user_id, created_at DESC, id DESC)` index and a recent-issue `(user_id, restroom_id, report_type, created_at DESC)` index.
- A SECURITY INVOKER BEFORE INSERT trigger that verifies ownership, trims text, converts blank optional details to NULL and prevents recent identical reports.
- A tightened INSERT policy allowing verified canonical restrooms and the existing explicitly defined minimal Google anchors, while excluding arbitrary private pending submissions.
- Explicit readable columns and INSERT column grants only for `user_id`, `restroom_id`, `report_type`, `comment`, `client_request_id`.

New reports receive database-default `pending` status. The ordinary client cannot supply status, primary key, created/updated times, reviewed/resolved times, or change ownership after insert. The existing own-read policy and RLS remain enabled. No ordinary UPDATE/DELETE grant or policy is added. The nullable historical `user_id`/ON DELETE SET NULL relationship is retained for existing account-deletion behavior; new client reports cannot have a missing owner.

| Actor | Create | Read | Update / delete / resolve |
| --- | --- | --- | --- |
| Guest or anonymous Auth | No | No private reports | No |
| Registered user A | Own, pending only | Own reports, every status | No |
| Registered user B | Own, pending only | Cannot read A's reports, even by known report ID | Cannot modify A's reports |
| Trusted database/server administration | Only under a separately authorized administrative workflow | Privileged | Can moderate outside the iOS client; no admin UI was built |

The iOS app continues to use the existing publishable key and authenticated session. No service-role/secret key or privileged endpoint was introduced.

### Duplicate and retry protection

Each form owns one request UUID throughout failures/retries. ON CONFLICT DO NOTHING followed by an owned read confirms an already-received attempt. If the draft was changed after an earlier accepted request, the returned row is checked against the draft; the app directs the user to My Reports rather than claiming the changed draft was saved.

A separate database check prevents a new UUID from bypassing the five-minute window for the same owner/restroom/type/trimmed description. A different explanation or a report after the window is allowed. An advisory transaction lock serializes that owner's inserts before the check, including simultaneous requests. The VOLATILE invoker trigger uses fresh query snapshots at READ COMMITTED, following [PostgreSQL's documented snapshot semantics](https://www.postgresql.org/docs/current/xfunc-volatility.html). Two concurrent connections were tested. This is a lightweight safeguard; before a large public launch, add trusted server-side per-account/IP volume limits and monitoring. Client loading locks are not a security boundary.

## My Reports and privacy

Profile's existing My Reports item opens the real private history. The service requests only the current SDK user's rows, with RLS independently enforcing that filter. Each page has 20 visible records and one lookahead row; Load More is offered only when appropriate. Ordering is `created_at DESC, id DESC`.

Success updates the shared history store; opening or refreshing My Reports fetches confirmed server state. Foreground refresh reloads statuses. Report Details performs an owned server read instead of trusting a passed row. Report IDs and author UUIDs are never rendered as user identity.

Canonical app-owned names/addresses can be displayed from the linked restroom. Google names already available during this session are used transiently after submission. After a restart, an ID-only Google anchor honestly appears as “Google Maps restroom” instead of retaining copied/stale provider content. Its detail page offers **View reported place in Google Maps**, using the existing Place ID through [Google's Maps URL format](https://developers.google.com/maps/documentation/urls/get-started). The app makes no extra automatic Places lookup to label report history. If a linked public record is unavailable, the report remains readable with a generic label.

Logout/account switching synchronously clears report rows and transient labels. Generation/request checks prevent delayed A responses or completed old forms from appearing in B's session. Loading, genuinely empty, failed load and failed next page remain distinct states. Dates use localized Swift format styles. Status is always text plus a symbol, with VoiceOver labels; it is not communicated by color alone.

## Moderation

Today's app submits pending claims and tracks `Pending`, `In Review`, `Resolved`, `Dismissed`. Reviewed/resolved dates appear only when supplied by the backend. Resolved explicitly means processed and does not claim Google's listing was updated.

Future moderation must run in a trusted server/admin environment with authorization and auditing. It should set status/reviewed/resolved timestamps, retain reviewer/audit information, and decide separately whether app-owned canonical information should change. Any privileged secret belongs only in that environment. Adding moderation must not grant ordinary iOS clients UPDATE access. No full admin dashboard, auto-approval, photos, notifications or Google editing was implemented.

## Verification performed locally

- Full Xcode simulator app build: **passed**. No introduced compiler warnings; only the existing AppIntents metadata extraction warning remains.
- Existing Swift regression runner including Day 17: **43 PASS groups**. Covers auth/session behavior, profiles, favorites, reviews/ratings, submissions, discovery/filter/search/directions, plus report validation, retries and account isolation.
- Disposable local PostGIS database suite: **197 PASS checks**, including all migrations, prior database regressions, report RLS/permissions, constraints, canonical/Google association, no public correction, expiring duplicate window and two concurrent connection tests.
- Real-app smoke check: relaunch, 20 nearby results, public rating display, Restroom Details and the protected REPORT guest prompt all loaded successfully. No report was submitted to the hosted project.
- Native simulator fixture checks: guest Create Account/Log In/Cancel; missing type; Other explanation required; successful pending confirmation; readable write failure with retained category; distinct empty/read-error states with Retry; private list/detail navigation; all four status labels; resolved explanation; dark mode and accessibility text size.

The UI fixture app is separate from the real target, has conspicuous test labeling, never uses credentials/network, and does not create hosted data. Local database tests model verified JWT claims/roles; they are not a claim that Supabase Auth or the hosted REST gateway was exercised end to end. Real authenticated API writes/relaunch verification and the full live regression checklist below remain for the configured project after migration.

To rerun locally from the project folder:

```sh
bash Tests/run-nearby-tests.sh
bash Tests/run-backend-db-tests.sh
```

The second command requires running Docker Desktop. It creates/removes an isolated disposable local PostGIS container and never connects to hosted Supabase. Do not run the local auth-stub SQL in a hosted project.

## Exact manual iOS checks after applying the migration

Use a development project/test accounts and a controlled restroom so test claims are distinguishable from genuine reports.

1. **Guest:** open Restroom Details → REPORT. Confirm Sign In Required, Create Account, Log In, Cancel. Cancel keeps browsing available. Sign in through the existing flow, then tap REPORT again.
2. **Missing type:** submit without a selection. Confirm a category validation error and no new database row.
3. **Optional details:** select Incorrect Opening Hours, leave details blank or only whitespace, submit. Confirm loading/disabled Submit, then Report Submitted and Pending. In Supabase, `comment` should be NULL. No correction should be claimed.
4. **Other:** select Other with blank/short details. Submission must fail validation. Enter a meaningful explanation of at least 10 characters and submit successfully. More than 1,000 code points must be rejected.
5. **Rapid taps / duplicates:** rapidly tap Submit; only one request proceeds. Reopen a form for the same issue and same details within five minutes. Confirm a readable recent-duplicate message and no extra row. A different explanation is allowed; after five minutes, a later identical report is allowed.
6. **My Reports:** Profile → My Reports. Confirm the new report, issue/date/Pending, then open Report Details. Check the real optional description and available dates; no author email/UUID or fake moderation notes should be shown.
7. **Persistence:** stop/restart the real app, restore/login to the same account, reopen My Reports. Confirm the row remains. An ID-only Google record may use the honest Google Maps restroom label; its external link identifies the place without copying provider fields.
8. **Different accounts:** A submits, logs out, B logs in. Confirm A's rows disappear immediately and B only sees B's reports. B must not gain edit/delete/status controls. Return to A and confirm A's reports remain.
9. **Network failure:** in a test environment interrupt connectivity before submitting. Confirm an error rather than success, with the category/details preserved. Restore connectivity and retry. If the first write succeeded but its response was lost, retrying the same form must not create a second row.
10. **Google identity:** report a Google-origin result, then compare `reports.restroom_id` with the one `restrooms` row for its `google_place_id`. Repeated resolution must reuse that ID. No copied Google fields or newly verified placeholder should appear.
11. **Canonical identity:** report an approved app-owned restroom. Confirm its existing canonical UUID is used directly, with no extra restroom row.
12. **No automatic correction:** compare the restroom's coordinates, hours, features, verification status, and review/cleanliness summary before/after an incorrect-location or unclean report. Reporting must not change them.
13. **Status tracking:** only in a development project, use an authorized server/admin workflow to set a test report to In Review/Resolved/Dismissed and real review/resolution dates as appropriate. Pull to refresh its owner's history/details. Confirm status text updates; resolved does not imply Google was changed.
14. **Accessibility:** enable large Dynamic Type and VoiceOver on a device. Check category labels/selected states, readable details field, Submit above the keyboard, Done keyboard control, status announcements and scrolling without clipped content.
15. **Paging:** with more than 20 genuine test reports, confirm initial 20 rows and Load More, with a separate retryable page error when connectivity fails.

## Supabase Dashboard verification

1. **Table Editor → reports:** inspect `user_id`, `restroom_id`, `report_type`, `comment`, `status`, `client_request_id`, `created_at`, `updated_at`, `reviewed_at`, `resolved_at`. A new row is pending; moderation dates are NULL. Blank optional details are NULL.
2. **Authentication → Users:** compare the reviewer's UUID with `reports.user_id`. Do not expose that UUID or email in public UI.
3. **Table Editor → restrooms:** locate the referenced UUID. For Google rows, confirm a single unique `google_place_id`, ID-only anchor and unverified status when originally unresolved. For app-owned rows, confirm the canonical record is unchanged.
4. **Database → reports → RLS policies:** RLS must be enabled. `reports_read_own` must require `auth.uid()=user_id` and a registered user. `reports_insert_own` must require the same ownership, pending status, NULL moderation dates and an eligible public/Google anchor. There must be no ordinary UPDATE/DELETE policy.
5. SQL Editor can inspect schema safely with:

```sql
select to_regprocedure('public.resolve_google_restroom(text)'),
       to_regprocedure('public.ensure_current_profile()');
select column_name, data_type
from information_schema.columns
where table_schema='public' and table_name='reports'
order by ordinal_position;
select conname, pg_get_constraintdef(oid), convalidated
from pg_constraint where conrelid='public.reports'::regclass;
select indexname,indexdef from pg_indexes
where schemaname='public' and tablename='reports';
select policyname,cmd,qual,with_check from pg_policies
where schemaname='public' and tablename='reports';
select relrowsecurity from pg_class where oid='public.reports'::regclass;
select privilege_type,column_name from information_schema.column_privileges
where table_schema='public' and table_name='reports' and grantee='authenticated'
order by privilege_type,column_name;
```

A Dashboard Table Editor/SQL Editor administrative session is **not** evidence that a normal user can write a field. For live RLS verification, use two actual authenticated test sessions through the normal publishable-key client: attempt A reading B's known report ID, A updating/deleting B, inserting `status=resolved`/`dismissed`, and supplying `reviewed_at` or `resolved_at`. Reads must return no B rows; writes must be denied. The disposable SQL tests already exercise equivalent roles/claims, including own-status writes and forged owner/timestamps, without disabling RLS.

## Regression checklist and remaining work

After hosted setup, run the existing real-app path for account creation/login/logout/session restoration and guest browsing; Profile/Edit Profile; Favorites/Saved; reviews/ratings/My Reviews and cleanliness filters; Add Restroom/My Submissions; Google Map/Places nearby results, list/marker selection, filters, location search, Details and directions. Local automated regression suites and full compilation passed, but this entire live matrix has not been manually completed against hosted services in this task.

Report submission/history adds **no Google Places SDK/API requests**. The shared resolution is a Supabase RPC, not a Google fetch. Existing nearby/search/navigation behavior continues to make its usual requests. Opening the explicit external Google Maps link is a separate user action.

Suggested Day 18: a protected server-side moderation workflow with audit history and server-side abuse/volume controls. No Day 18 implementation was started. Photos, push notifications, full admin dashboards and automatic restroom corrections remain outside today's scope.
