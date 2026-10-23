# Day 8 — Filters and sorting

## Implemented

The filter sheet follows the supplied screenshot: close/title/reset header, availability tiles,
Google rating buttons, distance slider, feature tiles, and a pinned Apply Filters button.
A Sort By menu supplies the requested sorting without changing unrelated screens.

- Distance: Any, or 0.5–5 miles in 0.5-mile steps, including 1 and 2 miles.
- Google rating: Any, 3.0+, 3.5+, 4.0+, 4.5+. Not an app or cleanliness score.
- Sort: Nearest (default), Highest Rated (Google), Most Reviewed (Google rating count).
- Both Home and Map expose an icon plus visible Filter text and active-filter count.
- Draft changes apply only when Apply Filters is pressed. Closing/swiping dismisses the draft.
- Reset is an explicit immediate action: active and draft filters return to defaults, including Nearest.
- Clear Filters restores the original results without a request. Independent search text is preserved;
  Clear Search is offered separately when text also excludes results.

## Data flow

Google Places → allRestrooms → RestroomFilter + searchText → filteredRestrooms → map + cards.

NearbyRestroomsViewModel owns original results, the active filter, the cached filtered results,
and selection. RestroomFilter owns all matching/sorting rules. Distance is measured only when
results or the user's actual location change, using the existing CoreLocation mapper. Moving
or searching the map never changes the distance origin. Filters remain active across new area
searches and location updates. A removed selected ID is cleared; a retained selection stays selected.

Missing/invalid distances cannot match a distance limit. Unrated/invalid Google ratings cannot
match a rating threshold. Unknown ratings/counts sort last; ties use distance then stable ID.
With Any, missing data remains included. No-match filters are distinguished from a Places response
containing zero restrooms. Errors keep the existing results and active filters.

## Available data and API usage

No service fields, SDK dependencies, requests, search radius, or result limit changed.
Local Apply, Reset, text matching, and sorting never call Google Places.
The current request still includes placeID, name, coordinate, formattedAddress, types,
businessStatus, rating, and userRatingsTotal. Existing searches retain their existing API usage;
this work adds no fields that change the billing tier.

Open Now is disabled: businessStatus=operational is not current opening status, and the current
request does not retrieve opening hours. The domain rule is prepared and tested for true/false/nil
but is not advertised as working with live data. It includes only confirmed true, excluding known
permanent/temporary closures. Unknown remains unknown, not closed.

Accessibility, baby care, gender-neutral, touchless, and free entry are disabled and visibly labeled
Not available yet. Cleanliness, app ratings, verification, and other amenities await reliable future
data/backend work. No values were fabricated and no backend/review submission was added.

The current Nearby Search loads up to 20 results within 1,500 meters of its search center. A five-mile
local filter does not fetch a complete five-mile result set. Filters are retained during the session,
not persisted across app relaunches.

## Files created

- RestRoomFinder/Models/RestroomFilter.swift — filter state, sort options, centralized domain rules.
- RestRoomFinder/Views/RestroomFilterView.swift — screenshot-based draft filter sheet.
- Configuration/DAY8_FILTERS_AND_SORTING.md — behavior, limitations, and verification guide.

## Files modified

- RestRoomFinder/ViewModels/NearbyRestroomsViewModel.swift — original/filtered collections, filter application and selection reconciliation.
- RestRoomFinder/Views/HomeView.swift — shared sheet, active count, disable unsupported quick chips.
- RestRoomFinder/Views/RestroomMapView.swift — shared filtered markers/cards and labeled Filter control.
- RestRoomFinder/Components/NearbyRestroomCards.swift — consume the shared filtered collection.
- RestRoomFinder/Components/DiscoveryStatusView.swift — actual result count/sort, filter-empty state and Clear actions.
- RestRoomFinder/App/RootView.swift — resolve Details from the renamed original-results collection.
- RestRoomFinder/Components/PrimaryButton.swift — configurable shared horizontal padding for compact rating buttons.
- Tests/NearbyDiscoveryTests.swift — domain and ViewModel filter regression coverage; collection naming updates.
- Tests/run-nearby-tests.sh — include the new filter model in the existing standalone test runner.

## Validation completed

- Full iOS Simulator xcodebuild: BUILD SUCCEEDED.
- No new compiler warnings; existing App Intents metadata extraction warning remains.
- bash Tests/run-nearby-tests.sh: all checks passed. Covers distance boundary/invalid/nil values,
  Google thresholds and unknowns, tri-state open logic, all sorts, combined filters, reset,
  draft isolation, active counts, selection removal/preservation, unchanged original results,
  location loss/recovery, area-search persistence, error/empty handling, API call counts, and directions URLs.
- iPhone 16 Plus / iOS 18 simulator: live Google results and current-location display; Google 4.0+
  reduced 20 to 9 results with 9 map markers. Combined 4.5+ and 1.5-mile filters produced 7 markers/cards.
  Highest Rated displayed descending scores. Card/marker synchronization, Details, and Apple Maps
  launch worked. Search this area after centering on another card returned 6 results with filters/sort
  retained. Cancel discarded the draft; Reset restored 20 results with Nearest. Final sheet and labeled
  map Filter control visually inspected; rating-button wrapping fixed.
- Direct simulated drag gestures were unavailable through desktop automation. Slider drag and physical
  map-panning gestures still need a manual touch check; area-search flow and domain distance logic were tested.

## Manual checks in Xcode

1. Run the app with a simulator location in an area containing public restrooms (e.g. Bryant Park,
   latitude 40.7536, longitude -73.9832). Allow location and wait for Google results.
2. One filter: open Filter, choose Google 4.0+, Apply. Confirm the badge reads Filter (1), unrated/lower
   scores disappear, and count agrees between Home and Map.
3. Multiple: keep 4.0+, drag Max Distance to 0.5 mi, Apply. Every result must satisfy both conditions.
   Open a retained card's Details and Navigate to confirm the same destination.
4. Draft cancel: change a threshold without applying, close the sheet, reopen. Original settings remain.
5. Reset: press Reset, then close. Badge disappears; all loaded results return in Nearest order. If text
   search is nonempty, clear it separately to see the entire original collection.
6. Sorting: with Any filters, apply each sort. Nearest has ascending distances, Highest Rated descending
   Google scores with unrated last, Most Reviewed descending Google counts with unknown counts last.
7. Area search: enable a filter, open Map, pan to another neighborhood, tap Search this area. Active
   settings remain; distances still refer to the user's location, not the new map center.
8. No matches: keep the user at Bryant Park, set a 0.5-mi maximum, then search an area more than a mile
   away that returns restrooms. Expect No restrooms match your filters and zero markers/cards. Clear
   Filters restores the loaded results. A genuinely empty Places response has the separate area-empty message.
9. Selection: select a low-rated marker, apply 4.5+ to exclude it. Its card highlight and map selection clear.
   Apply a filter that retains it and verify selection remains.
10. Check smaller devices, larger accessibility text, and VoiceOver. The sheet scrolls, action remains
    reachable, selected options are announced, and unavailable tiles cannot be enabled.
