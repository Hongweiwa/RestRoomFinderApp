# Day 11 — Supabase foundation

Implemented October 8, 2026. The iOS foundation and database migration are ready. **No hosted project exists yet**, so the migration has only been applied to disposable local PostgreSQL/PostGIS, and a successful hosted iOS connection is still pending your setup below.

## 1. Create your Supabase project

1. Sign in at https://supabase.com/dashboard and select **New project**.
2. Choose your organization, name the project **RestRoom Finder**, select a suitable region, and choose your database password. Keep that password in your password manager; it does not belong in the iOS app.
3. Wait for the project to finish provisioning.
4. Open the project's **SQL Editor**, create a new query, paste the entire file `supabase/migrations/202610080001_backend_foundation.sql`, and run it once.
5. Confirm the eight tables appear in the `public` schema and all show RLS enabled. No example restroom/user data is inserted by the migration.
6. In **Settings → Data API**, ensure the Data API is enabled and `public` is exposed. Do **not** add `gis` or `app_private` to exposed schemas. Keep other pre-existing Supabase settings unless needed.
7. Run Database **Security Advisor** and review any findings. The local tests validate our tables, not every setting or other table in a hosted project.

The migration is atomic and additive. It deliberately fails on conflicting app objects rather than replacing data/policies. Apply to a new project; do not re-run after success. If you use the Supabase CLI later, reconcile its migration history with this manually applied migration before running `db push`.

PostGIS is installed by the migration into `gis`, so do not enable it manually in `public` first. If the extension already exists elsewhere, the migration stops for review; it does not relocate/drop existing extension data.

## 2. Set the iOS URL and publishable key

Open **Connect** in your Supabase project and copy the Project URL and publishable key. You can also find publishable keys under **Settings → API Keys**. Use the key starting with `sb_publishable_`, not a secret key or legacy JWT.

Edit the already-created local file:

`Configuration/Supabase.local.xcconfig`

Replace its two placeholders with:

```xcconfig
SUPABASE_URL = https:/$()/YOUR_PROJECT_REF.supabase.co
SUPABASE_PUBLISHABLE_KEY = YOUR_SUPABASE_PUBLISHABLE_KEY
```

In the first line replace only `YOUR_PROJECT_REF` with your real project reference. In the second line replace the placeholder with the complete `sb_publishable_...` key. **Keep `https:/$()/` exactly:** xcconfig otherwise treats `//` as a comment. Xcode expands this into normal `https://`.

The local file is gitignored. `Configuration/Supabase.local.xcconfig.example` is the shareable template for another developer. Debug and Release both include `Supabase.xcconfig` through the existing build configuration. `Info.plist` reads `SupabaseURL` and `SupabasePublishableKey` from those settings. No manual Xcode target/package change is necessary.

Publishable keys are intentionally readable from a shipped app; RLS/grants protect the database. No `sb_secret_` or service-role JWT belongs here. Configuration validates HTTPS and accepts only the publishable-key format, rejecting secret/legacy keys without logging their values. This guard cannot protect a secret mistakenly pasted elsewhere: never add administrator credentials to the project.

## 3. Verify the real iOS connection

1. Open `RestRoomFinder.xcodeproj` in Xcode. The official `Supabase` product is already linked, pinned to **2.55.3**. Let Swift Package Manager resolve dependencies. It needs Swift 6.1-capable Xcode; the project remains iOS 17+.
2. Choose **Product → Scheme → Edit Scheme → Run → Arguments**.
3. Add `--check-backend` under **Arguments Passed On Launch**, checked.
4. Run a **Debug** build after saving your local settings. Open the Xcode debug console and filter for `[Supabase]`.
5. Expected after successful setup:

   `[Supabase] Connection succeeded. 0 public restroom ID(s) sampled; an empty result is valid.`

   The count can be 1 if an allowed record exists. Do not add fake public data just to make the test succeed.
6. Uncheck the argument after testing. Normal launches make no Supabase request. The diagnostic is excluded from Release builds.

`Not configured` identifies a missing/placeholder URL or key. `Connection failed` means to check internet access, project provisioning, copied credentials, Data API exposure and whether the migration ran. The diagnostic reads at most one public `restrooms.id` through the official SDK. It never writes, creates accounts, calls Google APIs or logs keys/raw server errors.

**Not yet verified:** a successful request from iOS to your hosted Supabase project. You chose to create the project yourself; that test requires steps 1–3 above.

## Database tables and relationships

| Table | Purpose and key relationships |
|---|---|
| `profiles` | Private display name/avatar metadata. `id` references `auth.users.id`; no passwords. Day 12 can insert the signed-in user's own profile. |
| `restrooms` | App-owned UUID, optional unique Google Place ID, app-contributed location fields, controlled source/verification status, optional creator profile. |
| `restroom_features` | One row per restroom. Six nullable booleans preserve true/false/unknown. |
| `favorites` | Profile/restroom pair is the primary key, preventing duplicates. |
| `reviews` | Restroom and optional author; one review per account/restroom; overall rating 1–5, optional cleanliness rating 1–5 and comment. |
| `reports` | Restroom/author, controlled report type and moderation status. |
| `restroom_submissions` | Private proposals, coordinates, notes and controlled pending/approved/rejected status; never auto-published. |
| `photos` | Storage path metadata only, restroom/author and optional review. Review must belong to the same restroom. Pending until approved. |

Source: `google`, `user_submission`, `admin`. Verification: `unverified`, `pending`, `verified`, `rejected`. Reports use the requested type/status enums. Coordinates enforce valid ranges (also excluding NaN/infinity); paired coordinates cannot be partially populated. App-contributed non-Google restrooms require a name and coordinate. Google ID anchors can omit place fields, avoiding unnecessary external-data copies.

All timestamps are server-generated. Updates automatically refresh `updated_at` where present. Clients cannot directly edit IDs, ownership, timestamps or moderation state. PK/unique constraints and targeted foreign-key indexes support normal lookups; location has a GiST spatial index.

### Account and record deletion

- Deleting an Auth user cascades to their private profile and favorites.
- Restrooms, reviews, reports, submissions and photo metadata survive profile deletion with `created_by`/`user_id` set to NULL. This avoids destroying shared app data when an account is removed. A future account-deletion/privacy workflow must decide how to handle user-written text and Storage objects.
- Deleting a restroom cascades only dependent feature/favorite rows; reviews, reports or photos block deletion. Future moderation should normally change verification status rather than delete a place with contributions.
- Deleting a review sets only `photos.review_id` to NULL and keeps the photo's restroom association. No Storage file deletion is implemented.

## Security policies

| Actor/table | Allowed operations |
|---|---|
| Guests | Read verified restrooms, their features/reviews and approved photo metadata. No writes, profiles, favorites, reports or submissions. |
| Registered profile owner | Read/insert/update own display name/avatar; cannot edit anyone else's profile. No direct profile delete. |
| Favorite owner | Read/insert/delete own favorites; inserts require a verified restroom. |
| Review owner | Create own reviews for verified restrooms; update rating/comment or delete own reviews. Cannot transfer ownership or change another review. |
| Report/submission owner | Insert pending records as themselves and read their own records. No client updates/deletes/moderation today. |
| Ordinary signed-in user | No direct writes to official restrooms, features or photos. |
| Supabase anonymous Auth user | Remains a guest even though Supabase assigns the authenticated role; no account writes. |
| Trusted backend/database administrator | Can manage moderation and app records; privileged credentials stay off-device. |

All eight tables have RLS plus explicit grants. Policies compare against `auth.uid()`; UI-supplied ownership cannot impersonate another account. Column grants protect moderation/status fields as well as ownership. Profiles are private today; future public reviewer display names need a separate intentionally limited read design.

`app_private.is_registered_user()` uses signed Auth claims, not user metadata. Helper functions use a fixed empty search path and invoker privileges. Nothing today introduces a security-definer endpoint. Supabase service-role access intentionally bypasses RLS for future trusted server operations; it is never used by the iOS client.

Storage is intentionally not configured: photo metadata policies are not Storage object policies. No bucket, upload, public URL, or realtime subscription is created.

## Geographic and Google identity architecture

Google Places remains the discovery source; its services, view model, model and IDs were not rewritten. The existing `Restroom.googlePlaceID` is the exact join key for `restrooms.google_place_id`. Do not join by name. The app's derived UUID for Google navigation routes is **not** the database UUID; future repositories look up by Google Place ID and use the returned backend UUID for review/favorite foreign keys.

No nearby result is automatically inserted. A future trusted contribution flow can create an ID-only Google anchor when app data is needed. The schema does not contain a Google rating cache; name/address/coordinate fields are for app-owned contributions, not a bulk copy of Google's results. Non-Google rows may have NULL Google Place IDs.

PostGIS `gis.geography(Point,4326)` is generated from app coordinates (longitude first), with a GiST index. Later an RLS-respecting query can use `gis.ST_DWithin(location, target, 1609.344)` for one mile. Google-ID-only anchors have NULL geography. No spatial RPC or new nearby search is integrated today.

## iOS service architecture

Future flow: View → ViewModel → feature service/repository → `SupabaseManager.shared.client()` → SDK → Supabase.

Today only `BackendHealthService` uses that client, invoked explicitly by a Debug launch argument at the app composition root. `SupabaseManager` lazily creates one client. Missing configuration throws a controlled error and does not interrupt Google discovery. Views do not import Supabase or issue database calls. No unused Auth/Profile/Favorites service scaffolding was added.

## Tests and completed verification

Run from the project directory:

```sh
bash Tests/run-nearby-tests.sh
bash Tests/run-backend-db-tests.sh
```

The database script needs Docker Desktop running, pulls the PostGIS upstream image, and starts a disposable container with no published host ports. It applies the migration to a clean database, runs **66 assertions**, rolls back fixtures, and removes the container. On Apple Silicon the upstream amd64 image uses Docker emulation.

`supabase/tests/local_auth_stub.sql` models Auth roles/JWT accessors for plain local PostgreSQL only. **Never run that stub in Supabase.** To repeat SQL policy checks in a hosted development project, run only `supabase/tests/backend_foundation.sql` after migration, as the database owner. It inserts fixed test identities inside a transaction and rolls them back; use a development project. This validates PostgreSQL enforcement, not Auth sign-in or hosted gateway configuration.

Completed:
- Official SDK dependency resolution; Google Maps/Places stay at 11.1.0.
- Full iOS Simulator build passed, with only the existing AppIntents metadata warning.
- Configuration tests passed: placeholders, HTTPS URL shape, publishable keys, secret/legacy-key rejection.
- Existing Days 1–10 discovery, location, filtering/sorting, search/autocomplete, stale-selection and directions tests passed.
- Database migration executed successfully and 66 constraint/RLS/ownership/deletion/spatial assertions passed, including a repeat through the clean-container test runner.
- Source and built Info.plist scan found no administrator key; no SDK imports in Views.
- App launched with `--check-backend`, reported the missing local URL safely, and continued loading 20 real Google nearby results using the existing location. Details and the existing Apple/Google directions sheet also opened correctly.

Pending: your hosted project creation, migration deployment, URL/key entry and successful hosted iOS probe. No hosted migration or successful hosted connection is claimed.

## Exact files created

- `Configuration/Supabase.xcconfig` — empty shared defaults and optional local include.
- `Configuration/Supabase.local.xcconfig.example` — shareable placeholder template.
- `Configuration/Supabase.local.xcconfig` — gitignored local placeholder file to fill in.
- `Configuration/SUPABASE_SETUP.md` — this setup, security and architecture guide.
- `RestRoomFinder/Services/SupabaseConfiguration.swift` — validates bundle configuration and client-safe key format.
- `RestRoomFinder/Services/SupabaseManager.swift` — one lazy, shared SDK client.
- `RestRoomFinder/Services/BackendHealthService.swift` — read-only connection diagnostic.
- `supabase/migrations/202610080001_backend_foundation.sql` — schema, PostGIS, constraints, indexes, timestamps, grants and RLS.
- `supabase/tests/local_auth_stub.sql` — local-only Auth compatibility fixture.
- `supabase/tests/backend_foundation.sql` — rollback-only database/security tests.
- `Tests/run-backend-db-tests.sh` — disposable Docker database test runner.
- `Tests/SupabaseConfigurationTests.swift` — configuration validation tests.

## Exact files modified

- `.gitignore` — ignores local Supabase settings and CLI temporary state.
- `Configuration/Maps.xcconfig` — includes backend configuration; existing Google key handling retained.
- `Configuration/Info.plist` — adds Supabase URL/publishable-key build substitutions; existing entries retained.
- `RestRoomFinder.xcodeproj/project.pbxproj` — links the official Supabase Swift package/product, exact version 2.55.3.
- `RestRoomFinder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — locks Supabase/transitive packages; Google pins retained.
- `RestRoomFinder/App/RestRoomFinderApp.swift` — invokes the opt-in Debug diagnostic.
- `Tests/NearbyDiscoveryTests.swift` — invokes configuration tests.
- `Tests/run-nearby-tests.sh` — compiles the configuration source/tests with existing regression tests.

## Intentionally deferred

Day 12+ owns authentication/profile UI, profile creation flow, Sign in with Apple, repositories for favorites/reviews/reports/submissions, rating aggregation, moderation, Storage permissions/uploads, safe account deletion and app-owned nearby queries. No feature buttons or existing screen design changed today.

## Official references

- [Supabase Swift release 2.55.3](https://github.com/supabase/supabase-swift/releases/tag/v2.55.3)
- [Supabase Swift initialization](https://supabase.com/docs/reference/swift/initializing)
- [API keys and where to find them](https://supabase.com/docs/guides/getting-started/api-keys)
- [iOS quickstart](https://supabase.com/docs/guides/getting-started/quickstarts/ios-swiftui)
- [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [PostGIS in a dedicated schema](https://supabase.com/docs/guides/database/extensions/postgis)
