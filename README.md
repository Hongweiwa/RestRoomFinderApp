# RestRoom Finder

A native SwiftUI architecture scaffold using MVVM, MapKit, and CoreLocation. Requires Xcode 16 or later and iOS 17 or later. There are no package dependencies or backend connections.

## Files and responsibilities

| File | Purpose |
| --- | --- |
| `RestRoomFinder/App/RestRoomFinderApp.swift` | SwiftUI application entry point. |
| `RestRoomFinder/App/RootView.swift` | Scene-owned view model, dependency creation, navigation stack, and destination resolution. |
| `RestRoomFinder/App/AppRoute.swift` | Typed, ID-based navigation destinations. |
| `RestRoomFinder/Models/Restroom.swift` | Identifiable, Codable value model containing all requested fields and a computed CoreLocation coordinate. |
| `RestRoomFinder/Views/RestroomListView.swift` | Minimal sample list used to exercise navigation. |
| `RestRoomFinder/Views/RestroomDetailView.swift` | Read-only detail placeholder; it needs no separate view model yet. |
| `RestRoomFinder/ViewModels/RestroomListViewModel.swift` | Main-actor observable list state and sample data loading through an injected service. |
| `RestRoomFinder/Services/RestroomService.swift` | Data service protocol and in-memory implementation. |
| `RestRoomFinder/Services/LocationService.swift` | Observable foreground location authorization and one-shot requests; intentionally not connected to the placeholder UI yet. Create and use on the main thread. |
| `RestRoomFinder/Components/RestroomRow.swift` | Reusable sample list row. |
| `RestRoomFinder/Utilities/MapDefaults.swift` | MapKit fallback region for a future map screen. |
| `RestRoomFinder/Resources/SampleRestrooms.swift` | Three fictional fixtures with stable IDs and varied amenities. |
| `RestRoomFinder/Resources/Assets.xcassets/Contents.json` | Asset catalog metadata. |
| `RestRoomFinder/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` | Shared accent color. |
| `RestRoomFinder.xcodeproj/project.pbxproj` | App target, synchronized source folders, deployment settings, and generated Info.plist configuration including location permission text. |
| `RestRoomFinder.xcodeproj/xcshareddata/xcschemes/RestRoomFinder.xcscheme` | Shared build/run/archive scheme. |
| `.gitignore` | Excludes local Xcode state and build output. |
| `README.md` | Architecture notes and manual verification checklist. |

Flow: App → RootView → List View → List ViewModel → RestroomService → sample models. Detail views receive an immutable model. Keep future data access in services and presentation logic in view models.

Ratings are on a 0–5 scale. `distance` is optional and expressed in meters; fixtures use `nil` because no actual user location is available. `accessibility` currently means wheelchair access. `openingHours` is display text, not a schedule engine. `imageName` currently refers to an SF Symbol. Fixture names, addresses, ratings, and facilities are fictional.

The map region and location service provide integration foundations only. Map rendering, nearby search, distance calculation, reviews, filters, persistence, and networking are left for future feature work. Location is not requested at launch. No background location capability is needed.

## Test in Xcode

1. Complete Xcode's first-launch setup and review/accept its license if prompted. Open `RestRoomFinder.xcodeproj` and select the shared `RestRoomFinder` scheme.
2. Choose an installed iPhone simulator and run with Command-R. Confirm the title and three sample rows appear.
3. Tap each row. Confirm its name, address, rating, and hours match its fixture. Test Back and the swipe-back gesture.
4. Open the `RootView` preview. Verify the same list loads without a network connection.
5. Try light/dark appearance, larger text, landscape, and an iPad simulator. Check that rows remain readable and navigation works.
6. Confirm launching does not show a location prompt. The location service is not wired to UI yet. When that flow is implemented, test Allow, Deny, simulated location, and permission changes in Settings.
7. To run on a physical device, set your development team and a unique bundle identifier under Signing & Capabilities. The current identifier is a placeholder.

## Verification in this workspace

The project plist and Swift syntax were checked locally. A simulator build was attempted with the installed Xcode, but Xcode stopped because its license has not been accepted. Compilation, previews, and runtime behavior still need verification in Xcode after first-launch setup.
