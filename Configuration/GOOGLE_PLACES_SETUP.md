# Day 5: Nearby public restroom discovery

## Data flow
Existing LocationManager → NearbyRestroomsViewModel → PlacesService → Google Nearby Search (New) → RestroomPlaceMapper → Restroom → existing GoogleMapView markers.

Home owns the discovery view model so closing/reopening its map sheet retains results. The initial valid authorized fix starts one request per Home lifetime. Camera movement and recentering never trigger additional searches. Explicit retries use the current fix. Successful searches (including empty results) within 50 meters, the same radius, and 60 seconds reuse results; failed requests can retry immediately. No disk cache or background location tracking is introduced.

The radius (1,500 meters), request limits, and duplicate thresholds live in NearbySearchConfiguration. Requests include public_bathroom, distance ranking, and at most 20 results. Fields: place ID, name, coordinate, formatted address, types, business status, Google rating and Google rating count. Ratings/count trigger the Nearby Search Enterprise SKU; remove both from the service field list if you do not need them. No photos, reviews, phone, website, opening hours, or Place Details are requested.

Google Place IDs are preserved and used to deduplicate. A deterministic UUID adapter maintains existing app routes. Distances are straight-line CoreLocation distances from the search origin, not walking routes. Cleanliness, verified accessibility, baby changing, gender neutrality, free entry, app reviews, and opening status remain unknown. Operational business status does not imply currently open.

## Manual Google Cloud configuration
1. Open https://console.cloud.google.com/ and select the project that owns the existing app key.
2. Open Billing. Verify this project is linked to an active billing account. If necessary, choose Link a billing account or create one and complete Google's payment setup yourself.
3. Open APIs & Services → Library. Verify Maps SDK for iOS is enabled.
4. Search for **Places API (New)** and click Enable. The legacy Places API alone does not enable Nearby Search (New). GooglePlaces is the installed iOS client SDK; this implementation needs the New API in Cloud.
5. Open APIs & Services → Credentials → the existing API key. Under Application restrictions choose iOS apps and add the exact bundle identifier shown in Xcode. The current project uses `com.example.RestRoomFinder`.
6. Under API restrictions choose Restrict key and allow both Maps SDK for iOS and Places API (New). Save and allow propagation time.
7. Keep the key in your ignored Configuration/Secrets.xcconfig as GOOGLE_MAPS_API_KEY. No second key or view changes are needed. Rebuild after changing the local key. An embedded iOS key is extractable: bundle/API restrictions provide protection.

No Google Cloud changes were performed by the implementation.

Official references:
- https://developers.google.com/maps/documentation/places/ios-sdk/nearby-search
- https://developers.google.com/maps/documentation/places/ios-sdk/get-api-key

## Xcode / simulator testing
1. Open RestRoomFinder.xcodeproj, let Swift Package Manager resolve GoogleMaps and GooglePlaces 11.1.0, choose the RestRoomFinder scheme and an iOS 17+ simulator, then Run.
2. Set a simulated location (for example 40.7536, -73.9832 in Midtown Manhattan) using the simulator Location controls or Xcode Debug → Simulate Location with a GPX fixture.
3. From Home choose MAP and allow location access. Expect locating → searching → real markers or a genuine empty state. Tap a black marker for its name/address. Home remains a clearly labeled sample preview until Day 6.
4. Pan/zoom and close/reopen the map: results remain and camera movement causes no Places requests. Recenter only refreshes the location.
5. Deny location permission in a fresh permission test (or use simulated Settings → Privacy & Security → Location Services → RestRoomFinder → Never). Reopen the map: the permission message should appear without a crash or an initial Places request. Restore While Using the App afterward.
6. Disable simulated location to exercise location unavailable and retry. A valid fix is required before any Places request.
7. On a fresh launch, test without network access for API failure and Try again after reconnecting. Do not expect a new request from merely panning. A successful empty response is cached for 60 seconds; after that Try again can make a fresh request.
8. Run `bash Tests/run-nearby-tests.sh` from the project directory for deterministic mapping, unique ID, distance, missing-location, loading, loaded, empty, error, retry, cache and in-flight protection tests. These tests use an injected service and never spend API quota.

## Physical iPhone
Select your signing team in Xcode and run on the phone. Match Cloud's bundle restriction to the signed app's bundle ID. Enable Location Services and grant While Using the App. The phone uses its real location instead of the simulator fixture; approximate location can affect results. Test denied permission and restored permission through iOS Settings. No background permission is required.

## Limits
Google's public_bathroom coverage may be sparse; this does not find every restroom inside restaurants or other businesses. Only up to 20 results are returned. No larger-area automatic fallback, Search This Area UI, list/map synchronization, live distance updates after movement, opening-hours verification, or custom reviews are implemented. The initial search occurs once per Home lifetime; restart the app to start a fresh initial search. A real-device test is still required.

## Verification performed
- Xcode simulator build succeeded with GoogleMaps and GooglePlaces 11.1.0.
- All deterministic tests passed using `bash Tests/run-nearby-tests.sh`.
- Live simulator search at synthetic 40.7536, -73.9832 returned 20 restrooms; map markers appeared and a selected marker displayed its Google name/address.
- Simulator location-unavailable state and successful retry were observed.
- Simulator location permission was temporarily denied: Settings guidance appeared without a crash. Permission was restored afterward.
- Empty/error behavior was tested through the injected fake service, not by changing Google Cloud settings. Physical iPhone testing remains manual.
