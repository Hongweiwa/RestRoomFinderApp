# Day 10 — External directions

Implemented 2026-10-05. No in-app routing, backend or Day 11 features.

## Architecture and behavior

`RestroomDetailView` / existing Home and map card buttons → `DirectionsView` → `DirectionsService` → `SystemNavigationAppOpener` → Apple Maps or Google Maps.

The sheet holds the passed Restroom value. Directions use that snapshot's coordinate, never the view model's current selection, search center, user coordinate, address geocoding, or a new Place Details lookup. Home's existing floating directions button uses the selected restroom or asks the user to select one.

Walking is the default each time the sheet opens. Driving is also available. The shared TravelMode enum centralizes mode values. The sheet reuses the existing monochrome theme/buttons, scrolls for longer text, offers medium/large heights, and disables repeated launch actions while opening. Native segmented selection supports the platform's selected-state semantics. Card and Detail directions buttons have destination-specific accessibility labels.

Apple Maps: builds MKMapItem from the restroom coordinate and assigns its actual nonempty name. Uses MKMapItem.openInMaps(launchOptions:from:completionHandler:), with MKLaunchOptionsDirectionsModeKey for walking/driving. Uses the iOS 26 location initializer when available and MKPlacemark on older supported versions. No source item is supplied; Maps chooses the origin. Existing Apple Maps URL generation remains for sharing.

Google Maps: checks UIApplication.canOpenURL(comgooglemaps://). If installed, opens comgooglemaps://?daddr=LAT,LNG&directionsmode=walking (or driving). If unavailable or app opening fails, opens https://www.google.com/maps/dir/?api=1&destination=LAT,LNG&travelmode=walking (or driving). No origin or API key is sent. Google coordinates are the destination; the coordinate-based URL does not support a separate display-name label, so the website may display coordinates. Google Place IDs remain unchanged and are not required.

Both providers handle their own GPS permissions and route availability. A successful launch means the OS accepted the handoff, not that the external app calculated a route.

## API/configuration impact

Opening directions adds zero Places, Nearby Search, Autocomplete or Place Details calls. No Routes/Directions API, billing configuration, SDK dependency, key or project-setting changes are needed. Existing user-triggered search behavior is unchanged.

Configuration/Info.plist was NOT modified. Its pre-existing LSApplicationQueriesSchemes already includes comgooglemaps, which the installation check requires. Existing googlemaps and comgooglemaps-x-callback entries were retained.

References:
- Apple MKMapItem: https://developer.apple.com/documentation/mapkit/mkmapitem
- Google iOS URL scheme: https://developers.google.com/maps/documentation/urls/ios-urlscheme
- Google cross-platform Maps URLs: https://developers.google.com/maps/documentation/urls/get-started

## Errors

- Non-finite or out-of-range latitude/longitude: sheet displays “Directions are currently unavailable for this restroom,” with no launch action. The current model requires both coordinates; NaN can represent invalid/missing test data.
- Empty name/address: generic sheet title or omitted address; coordinates still work. No invented destination name is sent to Maps.
- Apple launch failure: alert offers retry or the Google choice.
- Google missing: clearly labeled “Google Maps on the web.” Google app launch failure also retries the website automatically.
- Google web launch failure: alert offers retry or Apple Maps.
- Cancel returns to the existing screen. Successful opening dismisses only the directions sheet; it does not clear the search/filter/selection state.

## Exact created files

- RestRoomFinder/Models/TravelMode.swift — walking/driving names and provider mode mapping.
- RestRoomFinder/Services/SystemNavigationAppOpener.swift — UIApplication availability/opening and native Apple Maps handoff.
- RestRoomFinder/Views/DirectionsView.swift — reusable destination/mode/provider sheet and launch feedback.
- Tests/DirectionsTests.swift — deterministic provider, destination, validation and fallback tests with a fake app opener.
- Configuration/DAY10_DIRECTIONS.md — this implementation and testing guide.

## Exact modified files

- RestRoomFinder/Services/DirectionsService.swift — extends existing sharing URL helper with validation, native map item creation, provider URL construction and fallback orchestration.
- RestRoomFinder/Views/RestroomDetailView.swift — prominent Get Directions button opens the shared sheet using its displayed restroom.
- RestRoomFinder/Views/HomeView.swift — connects existing card/floating directions actions and presents destination snapshots.
- RestRoomFinder/Views/RestroomMapView.swift — connects existing card directions actions, replaces placeholder alert with sheet.
- RestRoomFinder/Components/NearbyRestroomCards.swift — passes the tapped card's Restroom into the directions callback.
- RestRoomFinder/Components/RestroomCard.swift — destination-specific quick-directions accessibility label/identifier.
- Tests/NearbyDiscoveryTests.swift — invokes directions tests alongside existing regression tests.
- Tests/run-nearby-tests.sh — includes TravelMode and DirectionsTests in the standalone test build.

## Verification completed

- Full iOS Simulator Xcode build passed. Only existing AppIntents metadata warning: no AppIntents.framework dependency. No new compiler warnings.
- `bash Tests/run-nearby-tests.sh` passed: destinations A/B, names, no fixed origin, walking/driving mapping, installed Google path, absent Google fallback, failed app→web fallback, failed Apple/web handoffs, missing name/Google ID, coordinate bounds, NaN/infinity.
- Existing discovery, location availability, map/list selection, Search this area, debounce/autocomplete sessions, stale responses, distance/rating filtering and sorting tests passed.
- Manual iPhone 16 Plus / iOS 18 simulator: Details→sheet shows correct Bryant Park restroom and Walking selected; native Apple Maps opens; returning retains Details.
- Manual Google-not-installed case: Google web opens with Bryant Park coordinates (40.7540581, -73.9826742).
- Manual search for Harvard University: live autocomplete and nearby markers/cards loaded. Map card directions for Portland Loo opened Google web with the different restroom coordinate (42.3749331, -71.1189684), not the Harvard search center or previous New York restroom. Returning retained the Harvard map/search context.
- Manual marker selection and card selection remained usable. Google rating 3+ reduced both list and map to the same single matching restroom.

## Exact manual test checklist

1. Run RestRoomFinder in Xcode with the existing key configuration. Set a simulator location or use an iPhone with location permission. Wait for nearby results.
2. Open restroom A using its Details arrow. Tap Get Directions. Check its name/address and default Walking selection. Tap Apple Maps. Verify destination pin/name and walking mode in Maps. Return to RestRoom Finder and verify Details A remains.
3. Reopen directions, select Driving and launch Apple Maps. Confirm driving mode. Cancel the sheet on a separate attempt; existing state must remain.
4. On an iPhone with Google Maps installed, choose Google Maps in both Walking and Driving modes. Verify destination/mode. The button should say Google Maps, not Google Maps on the web.
5. On a simulator/device without Google Maps, use the web option. Confirm the correct coordinate and no crash. The website may show an app promotion; choose Go back to web. Check/reselect its own walking/driving control if the website overrides the requested mode.
6. Return and open restroom B. Repeat directions. Verify B's coordinate, not A's. Try both existing quick card buttons and Details on the map and Home.
7. Search Harvard University (or another neighborhood), select a result, and open one of its restrooms. Confirm the external destination matches that restroom, not your GPS or search-center coordinate.
8. For invalid coordinates, use an Xcode preview `DirectionsView(restroom: ...)` with a Restroom whose latitude is `.nan`, then `91`, or longitude `181`. Verify the unavailable message and Cancel. Empty name/address with valid coordinates should still open. Automated tests cover all these cases without editing production data.
9. Run `bash Tests/run-nearby-tests.sh` to simulate installed/uninstalled apps and failed openings reliably. Real handoff rejection is OS-dependent; the fake opener asserts the failure paths and sheet displays localized errors.
10. Smoke-test current location, markers→cards, cards→markers, autocomplete, Search this area, distance/rating filters and sorting. Availability/amenity filters remain disabled as before because the current data does not verify them.
11. Check VoiceOver labels, Walking/Driving selected state, larger Dynamic Type and light/dark appearance on your device.

## Remaining external/device verification

Google Maps is not installed on this simulator. Its installed-app path and both modes were tested with the fake opener; real Google Maps on-device verification is still needed.

Apple Maps launched but its simulator location services are off, causing Choose Start. Native destination/name/mode were verified in automated tests; full Apple route calculation still needs device verification with Maps location access.

Google's mobile website showed the correct destinations but displayed its default driving route despite receiving travelmode=walking. We use the documented parameter; the external website controls its final UI and may require selecting Walking there. It also used an approximate location and displayed an app-install promotion. RestRoom Finder does not control those external screens.

The simulator automation bridge did not expose the segmented control's children or accept coordinate taps. Walking was visually verified; switching modes is covered in code tests and remains a manual device/UI check. No custom ETA, entrance guidance, accessibility routing or turn-by-turn screen was built.
