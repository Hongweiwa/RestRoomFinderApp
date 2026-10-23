# Day 15 — Reviews and cleanliness ratings

Implementation is complete locally. The full project builds and the Swift and disposable PostgreSQL regression suites pass. The hosted Day 15 migration has **not** been applied, and authenticated cloud submit/edit/delete/relaunch verification is **not claimed**. The user could not log in during the preceding favorites investigation; no password was requested, no account was created, and no cloud review was written or deleted today.

## Required Supabase setup

Use the project configured in `Configuration/Supabase.local.xcconfig`. No new Google API, key, Swift package or Xcode capability is needed.

1. Day 11 foundation and Day 12 profile trigger must already be applied.
2. Check the Day 13 and Day 14 dependencies in SQL Editor:

   ```sql
   select to_regprocedure('public.ensure_current_profile()') as day13,
          to_regprocedure('public.resolve_google_restroom(text)') as day14;
   ```

3. If `day13` is NULL, run the existing `supabase/migrations/202610090002_profile_recovery.sql` once. This was missing from the API in the earlier save investigation. If `day14` is NULL, run the existing `supabase/migrations/202610100001_favorites.sql` once. Do not rerun migrations that are already applied.
4. Run **`supabase/migrations/202610150001_reviews.sql`** once. It uses a transaction and notifies PostgREST to reload its schema cache.
5. Build and run the RestRoomFinder scheme in Xcode, then perform the live-account checks below.

If an existing function is still reported missing from the API, run `notify pgrst, 'reload schema';` in the same project's SQL Editor. A missing reviews migration is displayed as setup unavailable, never as “No Reviews Yet.”

## Review architecture

`SwiftUI → shared ReviewsViewModel → ReviewService → existing SupabaseManager → PostgreSQL/RLS`

RootView creates one ReviewsViewModel. Detail, My Reviews, and nearby rating enrichment share it. ReviewService is the only new review transport layer; Views do not query Supabase. RestroomReview, ReviewDraft, rating summaries, and MyRestroomReview are typed app-level values. The SDK retains session/token handling.

The existing Day 14 identity/profile/Google resolver calls were extracted into RestroomIdentityService, used by both FavoritesService and ReviewService. It calls the existing `resolve_google_restroom(place_id)` RPC. There is no second resolver, client, mapping table or favorite store. Reads never create Google anchors. An explicit first review can resolve/create an ID-only anchor, using the existing unique Google Place ID constraint. App-owned restrooms use their existing database UUID.

Writes obtain identity from the actual SDK session. Caller UUIDs are stale-account guards, not authorization. Insert includes the captured SDK user UUID; RLS compares it with `auth.uid()`. Updates/deletes also constrain both review ID and SDK user UUID. A changed account invalidates cached review management data and ignores old responses. The UI only reflects successful writes. A global in-flight guard blocks duplicate submission; database uniqueness independently blocks concurrent duplicates.

## Database changes

The existing reviews table already had stable UUIDs, nullable/deleted-account authorship, restroom FK, created/updated timestamps, a timestamp trigger, integer 1–5 checks, UNIQUE(user_id,restroom_id), and ownership policies. Those are retained.

The Day 15 migration adds:

- A required-cleanliness CHECK and a 1,000-character comment CHECK for inserts/updates. Both are `NOT VALID` to preserve any historical nullable-cleanliness/long-comment rows without inventing scores or truncating content. Historical rows remain readable; subsequent updates must meet the new constraints. The app requires both scores before any new/edit submission. Existing 1–5 database constraints remain enforced.
- A trigger trimming leading/trailing whitespace and converting blank comments to NULL. An empty comment edit explicitly sends JSON null to clear the saved comment.
- Public read access to the same narrowly defined Google ID-only anchors used by Day 14: Google source, unverified status, no app-owned name/address/coordinates/creator. Private/pending/rejected contributions remain excluded. Anchor visibility does not mark a place verified.
- Public review SELECT and owner-only INSERT policies accepting verified restrooms or these minimal anchors. Existing owner-only UPDATE/DELETE policies and column grants are unchanged. Clients cannot transfer review authorship, change restroom IDs, set timestamps, or change verification.
- `(restroom_id, created_at DESC, id DESC)` and `(user_id, created_at DESC, id DESC)` paging indexes. Existing constraints/indexes are preserved.
- `restroom_rating_summaries(restroom_ids uuid[], place_ids text[])`: bounded batches, PostgreSQL AVG(overall_rating), AVG(cleanliness_rating), COUNT(review ID). Empty aggregates are NULL averages and count 0. Historical unknown cleanliness is omitted from the average, never treated as zero.
- `restroom_reviews_page(target_restroom, before_created, before_id, page_size)`: public newest-first keyset paging. A timestamp plus UUID breaks timestamp ties. Server result limit is capped at 21; UI displays 20 and uses the extra row only to detect Load More.
- `my_restroom_reviews(target_restroom, before_created, before_id, page_size)`: authenticated management paging. **No user-ID parameter** is accepted. The server filters by `auth.uid()` and registered-user status. An optional restroom filter supports finding the user's existing review even when it is beyond the first public page.

All three new RPCs are **SECURITY INVOKER**, with empty search paths and explicit execution grants. They obey caller RLS; no new definer or bypass is used. The existing Day 14 narrowly scoped Google-anchor creation function remains unchanged. SQL uses transaction rollback tests with real anon/authenticated database roles. PostgreSQL explains these semantics in its [row-security documentation](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) and [NOT VALID constraint documentation](https://www.postgresql.org/docs/current/sql-altertable.html).

## Public identity and privacy

Public rows use “RestRoom Finder User”; the user's own row is labelled “You.” Profile names currently belong to a private owner-only profile model, so this implementation does not widen profile access or assume names are public. No email, UUID, token or auth information is rendered in review rows. The author UUID remains in the internal model/database for ownership and future moderation. Published review data is public under RLS; the management RPC always returns only the caller's reviews, including a caller's review whose parent later becomes unavailable.

## Rating architecture and filter

PostgreSQL computes the aggregates; Swift never downloads all reviews to calculate them. Nearby results use one summary RPC for up to 100 restrooms (20 results normally), with chunking for larger sets. No per-card summary requests are made. Detail loads one summary, one public page and, for a signed-in user, a separate owner lookup. Load More uses precise database timestamp strings to preserve microseconds and avoid skipped rows.

Mutation success invalidates summaries/list state and increments a shared revision. Visible Details/My Reviews and the nearby batch refresh from Supabase. Initial discovery, successful new searches and foregrounding refresh nearby ratings. Errors stay distinct from empty/unrated states.

`Restroom.overallRating`, `cleanlinessRating` and `reviewCount` represent RestRoom Finder only. `googleRating` and `googleUserRatingCount` remain separate and are never input to SQL aggregates. Details shows separate community overall, cleanliness, count, and Google reference rating. Cards retain their layout, prefer a labelled RestRoom Finder score when available, and otherwise show the explicitly labelled Google reference.

The actual Day 8 model had only a Google minimum; the new `minimumCleanlinessRating` is independent. Filter screen offers Any/3.0+/3.5+/4.0+/4.5+. Unknown, nonfinite or out-of-range cleanliness cannot satisfy a threshold. The Home “CLEAN 4+” shortcut uses the same filter. Backend rating-load errors clear unverified summary values and show Retry; they are not converted to 0.0. Existing Google filters/sorting, search, distance, and map/list selection logic are retained.

## Screens and reusable controls

- Details preserves the hero/map/information/actions layout and adds a reviews section below the existing actions. VIEW REVIEWS scrolls to it.
- Write a Review becomes Edit Your Review when the owner's row exists, including beyond the first public page. The entry action rechecks authentication and existing ownership before opening the form.
- Guests can read reviews and ratings; Write a Review presents Create Account / Log In / Cancel using the existing auth views.
- ReviewEditorView has two required star controls, an optional comment, count/validation, progress/disabled state, and server-error feedback. Edit prefills existing values and UPDATEs the same row.
- StarRatingControl has 44-point touch targets and one labelled VoiceOver-adjustable element with “N out of 5” value. Dates use localized Swift formatting. Shared AppTheme styles support light/dark mode.
- Delete requires a confirmation and never deletes the restroom. My Reviews supports own-row editing/deletion, paging, retry, empty state and Explore.
- My Reviews reuses known nearby/visited place data for names. For Google anchors with no current in-memory data, it honestly shows “Reviewed restroom” with “Open to load current place information.” Tapping retrieves current Place Details through the existing PlacesService and opens the existing RestroomDetailView. Unavailable places remain editable/deletable without fabricated coordinates.

## API usage

Review reads, ratings, submit, edit, delete, and Google-to-internal-ID resolution make **zero new Google requests**. The resolver is a Supabase SQL operation using the retained Place ID.

Opening a My Reviews destination that lacks current in-memory Google place data can make **one existing Google Place Details request**. It reuses the existing SavedPlaceResolving/PlacesService API, caches the result only in memory, and carries provider attribution into Details and the My Reviews display. There is no per-row automatic Google enrichment and no copied Google name/address/rating persisted in reviews/restrooms. Existing discovery/map behavior is unchanged.

## Tests completed

- Full simulator build: **BUILD SUCCEEDED**, only the existing AppIntents metadata warning.
- `bash Tests/run-nearby-tests.sh`: all tests pass. New coverage includes rating/comment validation; blank normalization; unknown cleanliness; Google/community separation; one batched request; 20-row paging; own-review lookup beyond a public page; failure retention; mutation invalidation; duplicate-submit suppression; late account-A response isolation; rejecting account-B management of A; error/retry versus empty; exact microsecond cursors; deleted-author and historical-cleanliness decoding. Existing auth/profile/favorites/search/filter/map-selection/directions tests continue passing.
- `bash Tests/run-backend-db-tests.sh`: all foundation/auth/profile/favorites/review SQL tests pass in disposable local PostgreSQL/PostGIS. Review checks cover public guest reads; registered vs anonymous Auth; score bounds/required cleanliness/comment cap; trimming/NULL comments; unique reviews; math for two users; 3→5 cleanliness edit; delete/count changes; restroom preservation; resolver reuse; A/B spoof/update/delete rejection; own-management filtering; bounded aggregate/page requests; timestamp-tie pagination.
- Separate, explicitly marked simulator fixture app: production review section/editor/My Reviews checked for existing-review detection, prefilled values, save/dismiss/reload, deletion confirmation, resulting unknown scores/zero count/empty state, Profile → My Reviews, readable dark layout, guest-readable rows and exact sign-in choices. Fixture data is memory-only and does not reach Supabase. Its Details wrapper is a test stub, not a claim of complete real navigation/backend validation.
- Final real app simulator: 20 nearby Google results loaded, Google/community labels remained separate, Details embedded map and directions chooser opened, and guest Write a Review presented Create Account / Log In / Cancel. The hosted review API returned missing-setup state as expected before applying Day 15; no false empty community scores were shown. The final production build was installed/launched and the disposable fixture app was removed.
- Star control labels/values were observed in accessibility output. Direct star-adjustment automation was blocked by Device Hub's computer-use bridge; physical VoiceOver gestures and tapping each star still need the device check below.

## Required live manual tests (Day 15 completion gate)

After applying migrations, use accounts you control. Do not send passwords or tokens in chat.

1. **Guest read/auth gate:** open a real restroom. With no app reviews, expect Not rated yet, unknown cleanliness, zero reviews, and the empty state. Tap Write a Review: Create Account / Log In / Cancel. Cancel must not create a row. Once another user has reviewed, a guest must see those public reviews and the same aggregate.
2. **Validation:** login as A, open Write a Review. Submit stays disabled until both ratings are 1–5. Tap each star; test VoiceOver increment/decrement and its spoken label/value. Enter 1,001 characters; expect validation. Blank/whitespace comment should save as NULL. Check larger text and keyboard scrolling.
3. **Submit:** choose Overall 4, Cleanliness 5, comment “Very clean.” Submit once and rapidly tap again. Expect one row, SAVED form dismissal, overall 4.0, cleanliness 5.0, one review. Google score must remain unchanged and separately labelled.
4. **Duplicate/edit:** revisit the same restroom. Expect Edit Your Review, prefilled values, and the same review ID after Save Changes. No second row. Set cleanliness 3; verify count still one and cleanliness 3.0.
5. **Aggregates:** B reviews the same restroom Overall 2, Cleanliness 5. Expect overall 3.0, cleanliness 4.0, count two. Change A cleanliness 3→5: expect cleanliness 5.0 and count two.
6. **My Reviews:** Profile → My Reviews shows only the current user's entries, dates and both scores. Edit here and return to Details: averages/list must refresh. Tap the restroom title to open existing Details. When place details cannot load, the review still permits edit/delete.
7. **Persistence:** stop/relaunch the real app without uninstalling. Login/session restore, public reviews, personal list, and ratings must remain. Repeat on another device if available.
8. **Deletion:** cancel the confirmation once (nothing changes), then confirm deletion of A's review. It disappears from A's list; the aggregate becomes B's score/count one. The restroom and B's review/favorites remain. Delete the final review: averages become unknown, count zero, Write a Review returns.
9. **Accounts/RLS:** switch A→B while a load is slow; no A management list/controls should appear for B. Use the local SQL suite to verify actual caller-role writes cannot edit/delete/spoof B. Dashboard Table Editor runs administratively and is not an RLS test.
10. **Cleanliness filter:** have reviewed and unrated results in the same discovered area. Set 4.0+: only actual community cleanliness >=4 appears. Google 4.7 with restroom cleanliness 3.4 must fail. Unrated is excluded. Clear the filter; markers/list/selection should reconcile together.
11. **Pagination:** with >20 real test reviews, Load More should add rows in created_at DESC/UUID order without duplicates/skips. Own Edit remains available even if the owner's row is older than the first 20. SQL tests exercise timestamp ties without writing cloud fixtures.
12. **Failure/retry:** offline, try save/edit/delete; no success state or invented score. Restore connectivity and Retry/refresh. A response lost after a server commit is reconciled by refresh; uniqueness prevents a duplicate. Verify errors do not show fake empty lists.
13. **Regression:** create/confirm an account, login/logout, restore session, Profile/Edit Profile, Favorites/Saved, Maps, Places nearby search, map/list synchronization, filters, location autocomplete/search, Details, and directions. Automated behavioral tests pass; full hosted account/device regression remains to be run.

## Supabase Dashboard verification

- **Table Editor → reviews:** inspect `id`, `user_id`, `restroom_id`, `overall_rating`, `cleanliness_rating`, `comment`, `created_at`, `updated_at`. Edits preserve id/created_at and advance updated_at. Verify only one `(user_id,restroom_id)` row. Comments contain no unintended whitespace.
- **Authentication → Users:** reviewer `user_id` must match that account's UUID. Emails are not used in public review UI.
- **Table Editor → restrooms:** review.restroom_id references the canonical row. Saving and reviewing the same Google Place ID reuse it. New Google anchors only store the Place ID/source/bookkeeping, with display fields null; they remain unverified.
- **Database → Policies:** RLS remains enabled. `reviews_read_public` allows verified-parent/minimal-anchor reviews; owner SELECT/INSERT/UPDATE/DELETE require auth.uid() and registered status as appropriate. No permissive write policy or client admin key was introduced.
- **SQL Editor:** independently compare SQL AVG/COUNT against the UI for a known restroom. Check the aggregate and page RPCs exist and are security-invoker. The local tests are the reproducible ownership verification; SQL Editor's admin role alone cannot prove RLS.

## Remaining work

Hosted migration/setup and the live-account/device tests above remain Day 15 verification work. Day 16 has not been started, and its feature scope has not been supplied. No submissions, reports, photos, avatars, notifications, replies, likes, admin dashboard, or AI moderation were implemented. Future reporting/moderation can target the existing stable review/author IDs and timestamps; this is not a complete App Store UGC moderation system.

## Exact files created and modified

### Created (13)

| File | Purpose |
| --- | --- |
| [RestRoomFinder/Models/RestroomReview.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Models/RestroomReview.swift) | Typed review/draft/summary/paging contracts and validation. |
| [RestRoomFinder/Services/RestroomIdentityService.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Services/RestroomIdentityService.swift) | Shared existing authenticated identity, profile recovery and Day 14 resolver boundary. |
| [RestRoomFinder/Services/ReviewService.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Services/ReviewService.swift) | Supabase paging, aggregates and owner-checked review writes. |
| [RestRoomFinder/ViewModels/ReviewsViewModel.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/ViewModels/ReviewsViewModel.swift) | Shared review state, mutations, batch summaries, paging and account isolation. |
| [RestRoomFinder/Components/StarRatingControl.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Components/StarRatingControl.swift) | Reusable accessible 1–5 input. |
| [RestRoomFinder/Components/ReviewRow.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Components/ReviewRow.swift) | Reusable public/private reviewer presentation and localized dates. |
| [RestRoomFinder/Views/Reviews/ReviewEditorView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Reviews/ReviewEditorView.swift) | Validated create/edit form. |
| [RestRoomFinder/Views/Reviews/RestroomReviewsSection.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Reviews/RestroomReviewsSection.swift) | Public page, auth gate, edit/delete entry and Load More. |
| [RestRoomFinder/Views/Reviews/MyReviewsView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Reviews/MyReviewsView.swift) | Current-user management list and existing-details navigation. |
| [supabase/migrations/202610150001_reviews.sql](/Users/wanghongwei/Desktop/BFAPP/supabase/migrations/202610150001_reviews.sql) | Constraints, normalization, public anchor/review policies, indexes and three invoker RPCs. |
| [supabase/tests/reviews.sql](/Users/wanghongwei/Desktop/BFAPP/supabase/tests/reviews.sql) | Database integrity, aggregates, paging and caller-role isolation tests. |
| [Tests/ReviewTests.swift](/Users/wanghongwei/Desktop/BFAPP/Tests/ReviewTests.swift) | Review state/validation/filter/privacy/paging regressions. |
| [Configuration/DAY15_REVIEWS.md](/Users/wanghongwei/Desktop/BFAPP/Configuration/DAY15_REVIEWS.md) | This implementation, setup, inventory and verification report. |

### Modified (17)

| File | Purpose |
| --- | --- |
| [RestRoomFinder/App/RootView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/App/RootView.swift) | Own/inject review state and refresh batched nearby ratings. |
| [RestRoomFinder/Models/Restroom.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Models/Restroom.swift) | Allow app-owned aggregate fields to update while retaining separate Google fields. |
| [RestRoomFinder/Models/RestroomFilter.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Models/RestroomFilter.swift) | Independent minimum cleanliness with unknown exclusion. |
| [RestRoomFinder/Services/FavoritesService.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Services/FavoritesService.swift) | Reuse extracted Day 14 identity/resolution helper; keep existing favorites behavior. |
| [RestRoomFinder/ViewModels/NearbyRestroomsViewModel.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/ViewModels/NearbyRestroomsViewModel.swift) | Apply summary batches and track successful discovery refreshes. |
| [RestRoomFinder/Views/RestroomDetailView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/RestroomDetailView.swift) | Live distinct scores, review count/section, review scroll and refresh. |
| [RestRoomFinder/Views/RestroomFilterView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/RestroomFilterView.swift) | Community cleanliness thresholds and explanatory copy. |
| [RestRoomFinder/Views/HomeView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/HomeView.swift) | CLEAN 4+ shortcut and rating-load retry. |
| [RestRoomFinder/Components/RestroomCard.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Components/RestroomCard.swift) | Prefer explicitly labelled community score without redesigning the card. |
| [RestRoomFinder/Views/Profile/ProfileView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Profile/ProfileView.swift) | Connect My Reviews and update feature/accessibility copy. |
| [RestRoomFinder/Views/Authentication/AuthenticationView.swift](/Users/wanghongwei/Desktop/BFAPP/RestRoomFinder/Views/Authentication/AuthenticationView.swift) | Update welcome copy now that reviews exist. |
| [Tests/NearbyDiscoveryTests.swift](/Users/wanghongwei/Desktop/BFAPP/Tests/NearbyDiscoveryTests.swift) | Run review regressions. |
| [Tests/run-nearby-tests.sh](/Users/wanghongwei/Desktop/BFAPP/Tests/run-nearby-tests.sh) | Compile review model/view-model/tests. |
| [Tests/run-backend-db-tests.sh](/Users/wanghongwei/Desktop/BFAPP/Tests/run-backend-db-tests.sh) | Include Day 15 SQL tests. |
| [supabase/tests/backend_foundation.sql](/Users/wanghongwei/Desktop/BFAPP/supabase/tests/backend_foundation.sql) | Make old valid fixtures supply required cleanliness; keep security assertions. |
| [Tests/ProfileUITestHost.swift](/Users/wanghongwei/Desktop/BFAPP/Tests/ProfileUITestHost.swift) | Isolated in-memory review UI fixture and navigation paths. |
| [Tests/build-profile-ui-host.sh](/Users/wanghongwei/Desktop/BFAPP/Tests/build-profile-ui-host.sh) | Compile production review UI into the isolated fixture host. |
