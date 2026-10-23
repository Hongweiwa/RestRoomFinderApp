# Favorites save failure — October 15, 2026

The configured hosted project's API returned `PGRST202` (function not found in schema cache) for `ensure_current_profile()`. The Day 14 `resolve_google_restroom(text)` function exists: its anonymous request was correctly rejected with `42501`. These were read-only checks; they did not create profiles, restrooms or favorites.

Previously, FavoritesService called profile recovery on every save, even for accounts whose profile already existed. This unnecessarily blocked those accounts when the Day 13 function was missing. It now reads the authenticated user's profile first, matching ProfileService, and only calls recovery for a missing row. All identity checks and RLS remain unchanged.

Errors now include a bounded reference such as `profile-recovery/PGRST202` or `save/42501`. Server messages, database records, emails, tokens and API keys are not logged. Missing recovery/resolver errors identify Day 13/Day 14 respectively.

## Complete hosted setup

1. In the same Supabase project as `Configuration/Supabase.local.xcconfig`, open SQL Editor.
2. Check whether recovery exists with this read-only query:

   ```sql
   select to_regprocedure('public.ensure_current_profile()') as profile_recovery;
   ```

3. If it is NULL, run the entire existing file `supabase/migrations/202610090002_profile_recovery.sql` once. Do not rerun the foundation or Day 14 migration.
4. If the function already exists but the API still reports `PGRST202`, refresh the API schema cache:

   ```sql
   notify pgrst, 'reload schema';
   ```

5. Run the updated app in Xcode. Log in, open a real restroom and tap Save. It should change to SAVED. Open Saved, then restart the app and verify it remains there.
6. If it fails, report the new reference shown in the alert. Do not disable RLS or put a service-role/secret key in the app.

An existing profile can save with the updated app without invoking recovery, but completing Day 13 remains necessary for accounts whose profile row is missing. No hosted migration was applied by this fix.

## Verification

- The full iOS Simulator app build succeeded; only the existing AppIntents metadata warning remained.
- `bash Tests/run-nearby-tests.sh` passed, including missing-migration feedback and retry-state coverage.
- The final fixed build was installed and launched in the simulator.
- Authenticated cloud Save remains unverified: the simulator required login after installation and the user could not log in during this check. No live favorite was created or deleted.
