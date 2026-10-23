# Day 9 — Location search and Autocomplete (New)

## Search architecture

The existing PlacesService now implements the LocationSearching protocol as well as NearbyRestroomSearching.
There is still one live Places service, NearbyRestroomsViewModel, LocationManager, and map screen.

SearchBar query → 300 ms debounce → PlacesService Autocomplete (New) → LocationPrediction rows
→ selected row → Place Details (New) coordinate → existing searchCenter + map camera
→ existing Nearby Search → allRestrooms → existing filters/sorting → filteredRestrooms → map/cards.

The search bar now searches geographic locations, not restroom names. Merely typing does not narrow
or replace existing restroom results. Search locations have their own lightweight model; they are
never represented as restrooms. There is no Text Search, geocoding backend, history, or authentication.

## Requests and session lifecycle

- Trim input, require at least 3 characters, wait 300 ms after the last edit. The delay is centralized
  in LocationSearchConfiguration and injectable for tests. Whitespace-only changes don't repeat calls.
- Only Autocomplete requests are made while typing. GMSAutocompleteRequest and
  fetchAutocompleteSuggestions(from:callback:) are the SDK's programmatic New API.
- Bias within 50 km of searchCenter, falling back to actual userLocation. This is not a restriction:
  no country or place-type filter is applied. Cities, addresses, neighborhoods, businesses and remote
  international places can be suggested.
- A logical UUID session is created at the first dispatched request. PlacesService associates it with
  one GMSAutocompleteSessionToken, reused across query changes and the selected Place Details request.
- Place Details is called only when a currently displayed prediction is tapped. Fields: placeID and
  coordinate only. The name and secondary address text already come from Google's prediction. No photos,
  reviews, website, phone, hours, or extra business fields are requested.
- A selected, canceled, or cleared session is ended; the next interaction receives a fresh token.
  Details errors also terminate that token. In-flight callbacks retain their captured token, and ending
  an older session cannot discard a newer one.
- Debounced tasks are canceled and query revisions checked after awaiting SDK callbacks. SDK requests
  already sent may finish, but stale success/error responses never update predictions or the chosen area.
- Repeated selection taps are ignored. Canceling or editing during coordinate resolution prevents a
  late Details response from moving the map or starting Nearby Search.
- Existing Nearby Search retains its 1,500-meter radius, 20-result limit, and fields. A same-area/radius
  request is suppressed while in flight or within the existing 50-meter/60-second successful-request
  window. A newer distinct-area request takes precedence over older responses, including failures.

Autocomplete and selected-place Details introduce additional Google API usage under the project's
billing configuration. Nearby fields and pricing tier are unchanged by this work. Local filters still
make no API calls. The existing key worked for live Autocomplete and coordinate lookup during testing;
no new SDK/package, secret file, service, or separate API key was added.

References:
- https://developers.google.com/maps/documentation/places/ios-sdk/place-autocomplete
- https://developers.google.com/maps/documentation/places/ios-sdk/place-session-tokens
- https://developers.google.com/maps/documentation/places/ios-sdk/session-pricing

## Location and map behavior

userLocation remains exclusively CoreLocation's actual fix. Selecting a destination updates the
existing searchCenter and requests one map focus at discovery zoom 15. It clears old marker selection
and opens the existing map sheet. New map instances honor their search-area center; a later GPS update
does not snap them back to the user. Restroom distances are always recalculated from userLocation,
never from the search center. Unknown user location yields nil distances, not fabricated short ones.

Manual location search also works without GPS permission. A later GPS fix supplies distances without
replacing the selected area. Distance filters can exclude all results when location is unknown or the
searched area is far away. Filters and sorting remain active across all searches.

Clear empties the query/predictions and cancels pending autocomplete while retaining the map/results.
Cancel does the same and dismisses field focus. Backgrounding ends the autocomplete interaction.
The map's existing location button and Home's current-location shortcut now focus the actual user and
run the same Nearby Search. Search this area continues to use the camera center, independent of GPS.

## Google attribution

The prediction panel displays the official, unmodified Google Maps logo in the same container, outside
its scrolling rows. Official dark-gray and white PNGs support light and dark appearance. The logo is
18 pt high with preserved aspect ratio and clear space. It has an accessibility label. A selected-area
summary is also attributed; any returned third-party attributed text is displayed with its links.
The Google Map's built-in attribution remains visible.

Asset source: https://developers.google.com/static/maps/documentation/images/Google_Maps_Attribution_Assets.zip
Policy: https://developers.google.com/maps/documentation/places/ios-sdk/policies

## Files created

- RestRoomFinder/Models/SearchLocation.swift — geographic prediction/destination models.
- RestRoomFinder/Services/LocationSearching.swift — SDK-independent interface implemented by PlacesService.
- RestRoomFinder/Utilities/LocationSearchConfiguration.swift — debounce, input threshold, bias, zoom.
- RestRoomFinder/Components/LocationSearchSuggestions.swift — prediction/error/loading UI, attribution, selected-area summary.
- RestRoomFinder/Resources/Assets.xcassets/GoogleMapsAttribution.imageset/Contents.json — light/dark asset metadata.
- RestRoomFinder/Resources/Assets.xcassets/GoogleMapsAttribution.imageset/google-maps-darkgray.png — official light-mode logo.
- RestRoomFinder/Resources/Assets.xcassets/GoogleMapsAttribution.imageset/google-maps-white.png — official dark-mode logo.
- Tests/LocationSearchTests.swift — deterministic autocomplete/session/concurrency/regression tests.
- Configuration/DAY9_LOCATION_SEARCH.md — this implementation and test guide.

## Files modified

- RestRoomFinder/Services/PlacesService.swift — New Autocomplete, minimal Details, SDK session token lifecycle.
- RestRoomFinder/ViewModels/NearbyRestroomsViewModel.swift — geographic query state, debounce, selection flow,
  session identity, current-location search, separate GPS/search state, and protection against stale nearby results.
- RestRoomFinder/Views/HomeView.swift — connect the existing search bar/panel and open the existing map after selection.
- RestRoomFinder/Views/RestroomMapView.swift — focus selected areas and reuse current-location search.
- RestRoomFinder/Components/SearchBar.swift — caller-requested keyboard dismissal; keep clear ready for input.
- RestRoomFinder/Components/GoogleMapView.swift — honor initial search center, camera revisions, current-location callback.
- RestRoomFinder/Components/DiscoveryStatusView.swift — location search works without GPS; remove obsolete name-search empty state.
- RestRoomFinder/App/RootView.swift — end autocomplete when the scene backgrounds.
- Tests/NearbyDiscoveryTests.swift — update former name-search assumptions and run new location-search tests.
- Tests/run-nearby-tests.sh — compile new models/protocol/configuration/tests in the existing runner.

## Validation

- Full iOS Simulator build succeeded. No new warnings; existing App Intents metadata extraction warning remains.
- bash Tests/run-nearby-tests.sh passed all previous discovery/filter tests and the new location-search tests.
- Tests cover short/empty input, debounce, repeated normalized text, out-of-order responses, sessions,
  selection-only Details, canceled Details, API failure, no predictions, bias priority, filter persistence,
  actual distances, late nearby responses, no-GPS selection, current-location return, and area search.
- Live iPhone 16 Plus/iOS 18: address suggestions for 1 Washington St Boston, neighborhood suggestions
  for Back Bay, and landmark suggestions for Boston Common. Google attribution visually checked.
- Selecting Boston Common opened its Google map and loaded 20 restroom markers/results, with distances
  about 187 miles from the simulated user in New York. Marker/card synchronization and Search this area
  worked after selection. Current-location button returned to New York with the active 4.0+ filter
  retained (9 matching results). Details remained correct and Directions opened Apple Maps.

- Final-build follow-up: Clear kept the field focused for immediate typing; Tokyo, Japan appeared
  despite the New York bias. Cancel removed predictions while retaining the New York restroom results.
- Offline and no-GPS edge cases were verified with injected service responses/state, not by changing
  device network or privacy settings. Physical map-panning gestures remain a manual check; Search this
  area was exercised after moving the map through card selection.

## Manual checks

1. Run with the existing API key and a simulated New York location (40.7536, -73.9832).
2. Type `1 Washington St Boston`; verify address predictions with secondary text and Google attribution.
3. Clear, type `Boston Common`, select its prediction. Verify map position, nearby results, and roughly
   187-mile distances from New York rather than distances from the searched point.
4. Close the map, search `Back Bay`, select the Boston neighborhood. Also try a remote city such as
   `Tokyo` to verify that bias is not a country restriction.
5. Type a query, press ×, and immediately type another. Query/predictions clear while current results
   stay. Cancel dismisses predictions and keyboard without a Nearby request or geographic reset.
6. Type B → Bo → Bos → Bost → Boston quickly. Confirm predictions correspond to the latest input.
   Deterministic tests additionally deliver deliberately reversed responses to verify stale protection.
7. Apply Google 4.0+ or Highest Rated, then search another place. Verify filters/sort persist. A small
   distance filter intentionally produces no matches for a remote search; Clear Filters restores results.
8. Pan after selection and tap Search this area. Verify new results and distances still based on GPS.
9. Tap a marker/card, open its Details arrow, then Navigate. Verify the selected restroom's destination.
10. Tap the map's current-location button. Verify the map and search area both return to the actual user.
11. With network unavailable, type/retry. Expect a subtle search error and retained restroom results.
    API error and no-prediction paths are covered by injected test responses.
12. Deny location permission, then select a geographic suggestion. Map/results should work, distances
    remain unavailable, and enabling GPS later must not replace the chosen search area.

## Remaining scope

No backend, saved searches, accounts, reviews, or navigation-screen redesign was added. The navigation
screenshot at `/Users/wanghongwei/Desktop/Screenshot 2026-10-02 at 17.20.11.png` is retained as the user's
reference for the next step, per their explicit instruction to finish Day 9 first. Route ETA, entrance
instructions, and accessible-route claims are not fabricated or implemented here.
