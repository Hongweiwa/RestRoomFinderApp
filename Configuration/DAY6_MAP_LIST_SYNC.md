# Day 6 — Map and list synchronization

## State and ownership
RootView owns one NearbyRestroomsViewModel (PlacesService) and the existing LocationManager. Home and the existing map sheet observe those same instances. No sample service is used by the live navigation flow; the older sample list remains available only as an isolated development scaffold.

- `restrooms`: one deduplicated collection, ordered by distance from the actual user.
- `visibleRestrooms`: the same local search/filter projection consumed by Home cards, map cards and map markers. Local filtering never calls Places; unknown amenities do not match enabled filters.
- `selectedRestroomID`: stable UUID derived from Google Place ID. `selectedRestroom` resolves from current visible results. Selection clears if the result disappears or is filtered out.
- `selectionRevision`: lets repeated taps on the same marker scroll its card back into view.
- `userLocation`: actual valid CoreLocation fix; never assigned from map movement. Distance is recalculated only for new results or changed user coordinates.
- `mapCenter`: most recent idle camera target; updating it does not make a request.
- `searchCenter`: the coordinate of the last requested search, separate from actual location. Retry uses this center, not whichever place the map has subsequently moved to.
- `state`: existing idle/loading/loaded/empty/error states. Previous data remains visible during loading and API failure; a successful empty response replaces it with an empty collection.

## Interactions
Marker tap → shared selection → ScrollViewReader scrolls to the stable card ID → monochrome selection border. Card tap → shared selection → matching Google marker callout and camera movement that preserves zoom. The separate 44-point arrow opens the existing Details destination without another Nearby Search.

Map objects stay alive during state updates. Marker objects are keyed by stable ID and retained when their restroom remains in a new result set. Camera movements only happen for initial location, a changed card selection, the recenter button or direct map controls. UI updates never continuously recenter.

## Exactly when Places is called
1. Once per scene/ViewModel lifetime after the first valid authorized location arrives (now on Home, without first opening the map).
2. Explicit Search this area. It becomes available when camera center differs by at least 50 meters from the requested search center.
3. Explicit Try again after an API error; it retries the failed center.

Panning, zooming, marker/card selection, opening Details, local text/filter changes, reopening the map, and subsequent location fixes do not fetch Places. In-flight requests are guarded. Successful same-radius searches within 50 meters and 60 seconds reuse the previous result set. Existing radius/type/field selection and API key configuration are unchanged.

## Manual tests
1. In Xcode Run on an iOS 17+ simulator. In Device Hub choose Device → Location → Custom Coordinates and set 40.7536, -73.9832. Restart the app for a fresh initial search. Allow location. Home should show real Google results, nearest first.
2. Open MAP. Confirm markers and cards show the same results. Select a marker farther down the result list: its card should scroll into view with a stronger monochrome border.
3. Tap another card's name/body. Its marker callout should appear; the camera moves toward it without resetting zoom. Details should not open.
4. Tap the arrow: confirm the name/address match the selected card. Navigate back; selection should remain.
5. Pan/zoom. Existing results should remain, with Search this area appearing after sufficient center movement. There should be no loading indication just from panning.
6. Tap Search this area. New markers and cards should replace the old set together. Distances must still be relative to the blue user dot. Close the sheet: Home should have the same updated results.
7. For a real empty-state check, move the map offshore and explicitly search. Actual results depend on Google coverage. The map must remain usable when no results are returned.
8. For API failure, disconnect the test device's network, move to a new area, and explicitly search. Previous data should remain with an error and Try again. Reconnect and retry. Do not change Cloud permissions merely to test failure.
9. Run `bash Tests/run-nearby-tests.sh` for deterministic empty/error responses, retry center, stale selection, duplicate IDs, user-versus-map distance, no requests on camera movement, and in-flight/cache checks.
10. On an iPhone, use actual GPS and verify card/marker taps and scrolling. Select the signing team and ensure the signed bundle ID matches the existing Google key restriction.

## Verification completed
- Xcode simulator build passed. Only the existing App Intents metadata-skipped warning remains.
- Focused command-line tests passed, including Day 5 checks and Day 6 synchronization cases.
- Live simulator: Home loaded 20 real results; marker selection scrolled/highlighted Herald Square Toilet; tapping Public Atrium bathroom's card selected its marker; the Details arrow opened the matching name/address/Google rating.
- Explicit area search at the selected map center replaced the marker set, including new Rockefeller Concourse results, while reusing marker objects for unchanged IDs.
- Automated UI drag attempts were blocked by the computer-control tool's noWindowsAvailable error. No-fetch-on-pan is verified in the state tests and delegate wiring; physical pan/zoom remains a manual check.
- Empty/error replacements and retention were tested with an injected service, without modifying Google Cloud or disrupting network settings.

## Limits
Google may have missing or misclassified public_bathroom entries. Maximum 20 results per 1,500-meter request remains. Distances are straight-line, not walking routes. Operational status does not mean currently open. Custom cleanliness/amenities remain unknown. Existing unsupported amenity filters can therefore yield no matches. Directions, reviews, accounts and backend functionality remain outside this task. Physical-device testing remains manual.
