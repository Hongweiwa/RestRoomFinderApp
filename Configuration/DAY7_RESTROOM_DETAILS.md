# Day 7 — Restroom Details

## Scope and files
Created:
- RestRoomFinder/Components/RestroomFeatureRow.swift: reusable yes/no/unverified attribute row with Dynamic Type fallback and an explicit accessibility label.
- RestRoomFinder/Services/DirectionsService.swift: validated Apple Maps walking-directions URL using only destination coordinates.
- Configuration/DAY7_RESTROOM_DETAILS.md: implementation and verification notes.

Modified:
- RestRoomFinder/Views/RestroomDetailView.swift: completes the existing detail screen, directions, disabled Save, report-information placeholder, and known/missing-data previews.
- RestRoomFinder/Models/Restroom.swift: rejects negative or non-finite distances when formatting the existing distance description.
- Tests/NearbyDiscoveryTests.swift: focused directions destination, no-Google-ID, missing-distance and business-status assertions.
- Tests/run-nearby-tests.sh: includes DirectionsService in the existing test harness.

No Google field-mask, request, location manager, selection, or navigation architecture changes were needed.

## Data and navigation
The existing AppRoute.restroomDetail(UUID) is resolved against shared results in RootView or RestroomMapView. The resolved Restroom renders immediately without a new Nearby Search, Place Details call, or loading spinner. Returning preserves the existing shared map/list state.

Google currently supplies name, address, coordinate, Place ID, types, business status, and optional Google rating/count. The screen uses the existing user-relative CoreLocation distance; it never measures from the map search center. Actual opening hours, current open status, accessibility, baby changing, gender-neutral access, entry cost, cleanliness, and RestRoom Finder ratings are not requested from Google and remain unavailable for current live results. Local/mock records can supply their own optional attributes and separately labeled app ratings/cleanliness. They are not mixed into the live results.

Missing/invalid ratings display Rating unavailable. Google rating and count are kept separate from RestRoom Finder ratings and cleanliness. Blank addresses display Address unavailable; blank names display Public restroom. Missing/non-finite/negative distances display Distance unavailable. Operational business status does not imply Open now. Known permanent/temporary closure is displayed accurately. Optional Boolean features distinguish Available, Unavailable and Not yet verified; entry cost distinguishes Free, Paid and Not yet verified.

## Directions, Save and reporting
Get Directions in Details opens `https://maps.apple.com/` with destination latitude/longitude (`daddr`) and walking mode (`dirflg=w`). No source coordinate is sent; Apple Maps chooses its current location. No Google key or Google Place ID is needed. Invalid destinations disable the button. A rejected URL handoff shows an alert; route availability/network errors after the handoff are handled by Apple Maps.

Apple reference: https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html

Save is visibly disabled and labeled coming soon. Report incorrect information navigates within the current stack to a clear placeholder that does not submit anything. No favorites, reporting backend, account, or review submission was added. Existing list-card directions previews remain outside this Details-only change.

## Verification performed
- Entire iOS simulator project build passed (Xcode). The existing App Intents metadata-skipped warning remains; no new compiler warnings/errors.
- `bash Tests/run-nearby-tests.sh` passed, including existing nearby discovery and map/list synchronization checks.
- Live Home discovery returned 20 results. Bryant Park Details showed its correct name, address, distance, Google 4.7 rating and 624 ratings at test time.
- Female Bathroom with no Google rating showed Rating unavailable and unverified features without crashing. Visually inspected layout on iPhone 16 Plus simulator.
- Save was disabled; report placeholder showed the correct restroom name and explicitly said no report had been submitted. Back navigation returned to the live list.
- Marker selection scrolled to Herald Square Toilet; tapping Public Atrium bathroom's card selected its marker. Search this area refreshed results, including Rockefeller Concourse entries. A Bathroom card in the refreshed map results opened the correct name/address/distance detail screen.
- Get Directions launched Apple Maps. Apple Maps prompted for a starting point and then displayed No Internet Connection in this simulator, so a completed route and destination display could not be verified there. Destination URL coordinates and walking mode passed deterministic tests. Verify a full route on an online physical iPhone.

## Manual testing
1. Run RestRoomFinder in Xcode. Set simulator location using Device Hub → Device → Location → Custom Coordinates (e.g. 40.7536, -73.9832). Allow location access.
2. Tap a card's arrow, not its body. Check the name/address/distance against the card. A card-body tap should still only select it.
3. Open both a rated and unrated result. Verify Google rating/count are labeled separately and unknown features do not claim availability.
4. Tap Get Directions. On an online iPhone with Apple Maps location access, confirm walking directions lead to that restroom. Return to RestRoom Finder and verify Back returns to the same usable list/map.
5. Open MAP, select a marker, tap its card arrow, then go Back. Pan and explicitly tap Search this area; open a result from that new set. Selection/details never trigger a Nearby Search themselves.
6. Scroll to Save and Report incorrect information. Save must remain disabled; reporting must open only the named placeholder. Back should work from both levels.
7. In Xcode previews for RestroomDetailView, inspect Local record with known features and Missing information • Large text. The latter covers blank address, absent ratings/distance/features and missing Google ID. Feature rows stack vertically when needed.
8. On a device, enable a larger text size and VoiceOver. Confirm button targets and labels (especially directions, Google rating, and unverified accessibility).
9. Run `bash Tests/run-nearby-tests.sh` to repeat the deterministic checks without spending API quota.

## Remaining limits
A full route requires working Apple Maps networking and location access; test on a physical device. Simulator launch of Maps succeeded but route completion was blocked as described above. No detail map preview or extra Places enrichment was added. Google coverage/accuracy and the existing search limits remain. Save and report submission intentionally remain unavailable.

## Screenshot layout revision (October 1)
Details now follows the supplied screenshot: a 4:3 monochrome hero, uppercase name, rating/cleanliness panel, grayscale location preview, Hours and Features tiles, Save/Report buttons, fixed Navigate action, and the existing Find/Saved/Profile navigation strip. Home and Details now reuse AppBottomBar rather than duplicating tab styling. Features opens the existing reusable tri-state rows; Report remains a placeholder; Share opens the system share sheet.

The new bundled DetailHero asset is an AI-generated illustration of a fictional park restroom, explicitly labeled ILLUSTRATION. It is not represented as a photo of the selected Google place. No Places photos/reviews/hours enrichment calls were added. The preview reuses GoogleMapView with gestures disabled and a grayscale style, centered on the selected result. Google attribution remains visible. Real Google ratings and missing cleanliness/hours remain honest instead of copying the example screenshot's sample values.

Revision files: RestroomDetailView.swift, GoogleMapView.swift (preview mode), AppTheme.swift (detail metrics/fonts), HomeView.swift (shared navigation component), new AppBottomBar.swift, new DetailHero.imageset/Contents.json and hero.png, and these notes.

Revision verification: simulator screenshots checked for both the upper hero/rating panel and lower map/tiles/Save/Report layout. Features and Report navigation worked; the Navigate control stayed fixed while content scrolled. Final simulator build passed.
