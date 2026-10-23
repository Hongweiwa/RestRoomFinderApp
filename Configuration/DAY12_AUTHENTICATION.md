# Day 12 — Authentication implementation and setup

Implemented email/password account creation, login, current-device logout, session restoration, and guest access. Open **Profile** on Home or Restroom Details to access the account sheet. This is a minimal account entry/status panel; the full Profile feature remains deferred.

## Required setup before your first signup

1. Open your existing Supabase project → **SQL Editor** → **New query**.
2. Copy and run `supabase/migrations/202610090001_auth_profiles.sql` once, after the already-applied Day 11 foundation. Do not rerun the Day 11 migration. This new migration was tested locally but **has not been applied to your hosted database** from this task.
3. Open **Authentication → Sign In / Providers → Email** (some dashboard versions label this Providers). Confirm Email/Password sign-in is enabled. **Confirm Email: Enabled**, verified using your project's read-only Auth settings endpoint on October 9, 2026. Signup is enabled. No provider or confirmation settings were changed.
4. Keep Confirm Email enabled. In the email/password settings, check the project's password policy. The app requires at least eight characters and displays server-enforced stronger-policy failures safely. If you configure a stronger minimum/complexity rule, align the form guidance and `AuthValidation` with that policy; do not weaken an existing policy merely to match the app.
5. Open **Authentication → URL Configuration → Redirect URLs → Add URL**. Add exactly `restroomfinder://auth/callback`, then save. Signup explicitly supplies this redirect. Keep your existing Site URL; the app redirect belongs in the redirect allowlist.
6. Use the standard signup confirmation email template containing the Supabase confirmation link. A custom template must preserve the supplied redirect rather than hard-code a different destination. Email delivery/SMTP limits still apply to your project; configure a verified SMTP service in Supabase before broader testing if the built-in service cannot deliver to your test address. Do not put SMTP credentials in the app.

Xcode already has the `restroomfinder` URL scheme in `Configuration/Info.plist`. Verify the RestRoomFinder target still uses that Info.plist. No new package, capability, or service-role key is required. Existing `Configuration/Supabase.local.xcconfig` continues to supply only the project URL and publishable key. Choose the RestRoomFinder scheme and an iOS simulator/device, then build/run.

## Architecture and state

`SwiftUI → AuthViewModel → AuthenticationServicing / AuthService → shared SupabaseManager client → Supabase Auth`

The root creates one auth view model and shares it with the existing navigation hierarchy. Account forms use the existing theme, PrimaryButton and SecondaryButton. Core navigation remains available independently of authentication.

- `loading`: checking or refreshing the stored session. The account sheet shows progress; users can continue browsing.
- `guest`: no verified current session. Public map/search/filter/details/directions remain available. Guest mode does not create an anonymous Supabase user.
- `authenticated(AuthUser)`: SDK-derived UUID/email from a valid, non-anonymous session. The minimal panel loads the durable profile name and offers logout.

`requireAuthentication()` refreshes through the SDK and returns whether an account-required action can proceed. Future callers can present AuthenticationView when it returns false. RLS remains the actual database authorization boundary. No favorites or other protected features were added.

## Signup, profiles and login

Signup trims name/email and validates a nonempty name of at most 80 Unicode scalars, reasonable email formatting, at least eight password characters, and exact confirmation. Invalid forms do not call the service. Submission is disabled while an auth operation runs.

The installed Supabase Swift SDK remains **2.55.3**. `auth.signUp(email:password:data:redirectTo:)` sends the display name as signup metadata. With Confirm Email enabled, a successful signup can return a user without a session: the app stays guest and shows Check your email. The wording accommodates Supabase's account-enumeration protection. If confirmation is disabled, the returned session is restored and the app signs in. The app never changes that setting.

The new **database trigger** runs transactionally after insertion into `auth.users` and creates `public.profiles.id = auth.users.id`. This works even before email confirmation, without an iOS insert or authenticated client session. It copies only a sanitized display name. Anonymous Auth users are excluded. The migration backfills missing profiles for existing non-anonymous accounts and preserves existing profile rows/names. The narrow security-definer function has an empty search path and no client execution permission. Existing RLS and column grants remain intact.

In **Authentication → Users**, locate your test email and copy its user UUID. In **Table Editor → profiles**, verify a row with that exact `id` and the entered display name. If signup says it cannot save the new user, inspect the Supabase Auth/database logs and confirm both migrations were applied successfully. A failed transactional trigger prevents a partially created new account. If an existing signed-in account's profile cannot be read, the app displays a retry action without pretending the profile loaded.

Login uses the actual Swift SDK method `auth.signIn(email:password:)`. Incorrect credentials, unconfirmed email, weak passwords, rate limits, connection failures and expired sessions map to readable app-owned messages. Debug diagnostics contain a fixed error category only.

## Persistence, events, logout and links

Supabase's built-in Apple Keychain storage persists sessions. App code does not store passwords, tokens or a separate logged-in flag. Configuration explicitly enables `emitLocalSessionAsInitialSession: true` and PKCE. Since INITIAL_SESSION may be expired, the view model re-reads `auth.session`, which can refresh via the SDK, and checks expiry before authenticating. A stored token alone is insufficient. An expired session that cannot refresh produces guest state and an explanation. A valid unexpired session can still be restored while offline.

INITIAL_SESSION, SIGNED_IN, TOKEN_REFRESHED and user updates synchronize UI with the SDK. SIGNED_OUT clears account/profile state. Foregrounding and the session expiry deadline trigger another validity check. Revision checks and cancelled profile tasks prevent late results from reviving stale identity/profile data.

Logout explicitly calls `auth.signOut(scope: .local)`: **current device/session only**, not all devices, and no account/profile deletion. SDK 2.55.3 removes the local session before its network revocation request. If that request fails offline, the UI still becomes guest and explains that server revocation could not be confirmed.

The root handles only `restroomfinder://auth/callback` auth links. `AuthService` validates the route and uses the SDK's async `auth.session(from:)` PKCE exchange. No callback URLs/codes/tokens are logged. For automatic return/sign-in, open the confirmation email on the same installation where signup began. Opening on another device can verify the email but cannot complete that installation's PKCE exchange; return and log in manually. Expired or malformed links show a readable error. Password-reset links are not implemented today.

## Verification completed

- Entire simulator Xcode project: **BUILD SUCCEEDED**. No new Swift compiler warnings; Xcode reports only its existing AppIntents metadata extraction warning.
- `bash Tests/run-nearby-tests.sh`: passed auth state/validation tests and existing discovery, filter, autocomplete, directions and configuration regressions.
- Auth tests use an injected fake service: confirmation enabled/disabled, success/failure login, incorrect credentials, unconfirmed email, network failure, duplicate submission prevention, SDK-style local logout while offline, valid session restoration, signed-out restoration, expired initial-session refresh, expired/offline rejection, profile retry, late profile cancellation, callback routing and events.
- `bash Tests/run-backend-db-tests.sh`: passed on a disposable local PostGIS database. Applies both migrations and checks existing RLS plus profile creation, UUID linkage, metadata edge cases, anonymous exclusion, ownership, function permissions and deletion relationships. The local Auth table is a test stub; this is not a hosted signup/delivery test.
- Simulator: guest Home still loads 20 nearby Google results; Profile opens the new account sheet; signup/login controls render in the existing black-and-white style; empty name and invalid email show local errors; Continue as Guest dismisses account entry; Forgot Password explicitly states that no reset email is sent; an invalid confirmation callback shows safe feedback.

**Still requires your real-account test:** no hosted test user was created, no real confirmation email was sent, and no live successful login/logout or Keychain relaunch with a real account is claimed. These need the migration/redirect setup above and an email you control. Do not share your password in chat.

## Manual end-to-end test

1. Apply the migration and dashboard setup above. Run the app. Confirm Home remains usable before signing in. Open Profile → Create Account.
2. Submit an empty name and invalid email. Then enter a valid test email and deliberately mismatched passwords. Expect local errors and no signup. Use a new email you control for the actual signup; enter your own password (eight or more characters, plus project policy).
3. Tap Create Account repeatedly while it loads. Expect one request, then Check your email and guest access. Check Authentication → Users and Table Editor → profiles for matching UUID/name. Do not expect an authenticated session before verification.
4. Try logging in before confirming: expect the verify-email message. Open the confirmation link on the same device/installation, allow opening RestRoom Finder, and expect authenticated state. For Simulator, its Mail app may be unavailable: open your webmail in simulator Safari, or copy the confirmation link into simulator Safari yourself. Do not paste the link into chat. If verification occurs elsewhere, use Log In after confirmation.
5. Open Profile and verify Signed in, your durable display name, and email. Log out. Try the wrong password: expect a readable error while remaining guest. Enter the correct password: expect the account sheet to dismiss and Profile to show the authenticated account when reopened.
6. Terminate and relaunch the app while signed in (do not uninstall). Open Profile; expect the stored valid session to restore without another login. Repeat after logout; expect guest entry. With an expired session and no network, the app must not grant account-required access.
7. Tap Log Out. Expect guest entry and no profile deletion in Supabase. Confirm another device remains signed in. Repeat with networking unavailable: local guest state must still be correct even if server revocation cannot be confirmed.
8. As guest, exercise current location, map, area search, filters, a restroom's details and directions. Repeat while signed in; the same core screens should work. Test offline login for a readable connection error, and rapid taps for single submission.

## Exact Day 12 file inventory

Paths below are relative to `/Users/wanghongwei/Desktop/BFAPP`.

### Created

| File | Purpose |
| --- | --- |
| `RestRoomFinder/Models/AuthState.swift` | Auth identity/state, safe session snapshot/events, profile DTO, errors, validation, callback route. |
| `RestRoomFinder/Services/AuthenticationServicing.swift` | Injectable auth service interface for the view model/tests. |
| `RestRoomFinder/Services/AuthService.swift` | Shared SDK adapter for signup, login, local logout, session events/restoration, callback exchange and profile reads. |
| `RestRoomFinder/ViewModels/AuthViewModel.swift` | App-level auth state, operations, expiry handling, profile loading and future protected-action helper. |
| `RestRoomFinder/Components/AuthFields.swift` | Reusable themed text/password fields with autofill and show/hide support. |
| `RestRoomFinder/Views/Authentication/AuthenticationView.swift` | Welcome/check-email/minimal account sheet with guest exit. |
| `RestRoomFinder/Views/Authentication/LoginView.swift` | Login form and explicit password-reset placeholder. |
| `RestRoomFinder/Views/Authentication/CreateAccountView.swift` | Validated account creation form. |
| `supabase/migrations/202610090001_auth_profiles.sql` | Transactional profile creation trigger and missing-profile backfill. |
| `supabase/tests/auth_profiles.sql` | Profile trigger and ownership/security database checks. |
| `Tests/AuthenticationTests.swift` | Deterministic auth state, validation and concurrency tests. |
| `Configuration/DAY12_AUTHENTICATION.md` | This completion report and setup/test guide. |

### Modified

| File | Change |
| --- | --- |
| `RestRoomFinder/Services/SupabaseManager.swift` | Explicit initial-session emission, PKCE and default redirect configuration. |
| `RestRoomFinder/App/RootView.swift` | Shared auth state, startup/foreground checks and auth callback handling. |
| `RestRoomFinder/Views/HomeView.swift` | Profile button opens the account sheet. |
| `RestRoomFinder/Views/RestroomDetailView.swift` | Profile button opens the same account sheet; preview receives auth dependency. |
| `Configuration/Info.plist` | Registered the confirmation callback URL scheme. |
| `supabase/tests/local_auth_stub.sql` | Added Auth metadata/anonymous columns needed by trigger tests. |
| `supabase/tests/backend_foundation.sql` | Made profile fixtures compatible with automatic trigger creation. |
| `Tests/run-backend-db-tests.sh` | Applies all migrations and runs the added profile tests. |
| `Tests/run-nearby-tests.sh` | Compiles auth types, view model and tests into the existing test runner. |
| `Tests/NearbyDiscoveryTests.swift` | Invokes the authentication regression suite. |

The synchronized Xcode source folder includes the new Swift files automatically. No package version, project file, local API-key value, Google service, or Day 11 production RLS policy was changed. No service-role/admin credential was added. Passwords exist only transiently in secure form/request memory and are cleared when forms leave; app logs never include them.

## Remaining work

Run the real-account checks above after manual configuration. Password recovery is an explicitly labelled placeholder. Day 13's full Profile screen, editing and activity/history are not started. Favorites, reviews, submissions, reports, photos, social login and account deletion remain outside today's scope.

SDK references: [Swift signup](https://supabase.com/docs/reference/swift/auth-signup), [Swift login](https://supabase.com/docs/reference/swift/auth-signinwithpassword), [Swift logout](https://supabase.com/docs/reference/swift/auth-signout), [native mobile deep linking](https://supabase.com/docs/guides/auth/native-mobile-deep-linking).
