# Google Maps setup

The app target already links Google's official `GoogleMaps` Swift package, pinned to 11.1.0. Both Debug and Release use `Maps.xcconfig`. Xcode 26 or later is required by the current SDK; the app deployment target remains iOS 17. No Google Places dependency is installed.

## Google Cloud Console

1. Select or create your Google Cloud project and enable billing.
2. Enable **Maps SDK for iOS**. You do not need Places, geocoding, directions, or navigation APIs for this task.
3. Create an API key. Under **Application restrictions**, select **iOS apps** and add the bundle identifier from the app target. The current project identifier is `com.example.RestRoomFinder`; if you change it, update the restriction to match.
4. Under **API restrictions**, restrict the key to **Maps SDK for iOS**.

Google's setup instructions: https://developers.google.com/maps/documentation/ios-sdk/config
Key setup and restrictions: https://developers.google.com/maps/documentation/ios-sdk/get-api-key

## Xcode / local configuration

1. Copy `Configuration/Secrets.xcconfig.example` to `Configuration/Secrets.xcconfig` next to it.
2. Replace `YOUR_API_KEY` with your key. Do not add this file to target membership. It is ignored by Git and included by `Maps.xcconfig` at build time. Do not put the key in Swift source.
3. Open `RestRoomFinder.xcodeproj`. Allow Swift Package Manager to resolve GoogleMaps. Both target configurations already use the correct base configuration; do not replace it with Secrets.xcconfig.
4. For a physical device, choose your signing team and an appropriate unique bundle identifier. Keep the Cloud restriction in sync.
5. Build and run. Tap the existing **MAP** control (or location control) on Home. On first use, choose **Allow While Using App** or **Allow Once**.

The generated Info.plist already includes the When-In-Use permission description, the API key build-setting substitution, and Google's URL query schemes. No background location capability or Always permission is needed. API keys are necessarily present in the compiled client app; Cloud application and API restrictions protect usage, while the ignored file keeps keys out of source control.

## Runtime behavior

- `LocationManager` is a main-actor observable, foreground-only provider. It is retained by the map screen, requests a one-shot fix, and stops on dismissal or inactivity. Failed/invalid fixes time out after 15 seconds and can be retried.
- Opening the configured map requests permission if undecided. Denied access offers Settings; restricted access explains the restriction; unavailable location offers Retry. Returning from Settings refreshes authorization.
- The map displays Google's current-location indicator when authorized, centers on the first fresh fix, and supports explicit recentering. Other SwiftUI updates do not reset a user's pan. Approximate location is accepted.
- Restroom markers use the existing filtered mock data, not Places. Without a user fix the initial camera uses the first sample coordinate (or Midtown fallback). Mock locations may be far from your real location; pan back to New York to find them.
- The key-missing screen prevents constructing GMSMapView without configuration. A nonempty but invalid/restricted key can still be accepted locally by the SDK; Google validates it over the network. Check Xcode's SDK diagnostics and Cloud settings if tiles do not load.
- The Home layout and its sample-location label remain unchanged; live location belongs to the map only. Directions remain unimplemented.

## Verify manually

- With no key: Home still opens; Map presents setup instructions without crashing.
- Fresh permission: tap Map, allow access, simulate a location in Xcode (Debug > Simulate Location) or use a real device; confirm the location dot and camera position.
- Deny access: confirm sample markers still appear and Settings opens. Grant permission in Settings and return to the map.
- Unavailable: select no simulated location or disable Location Services; confirm the failure message and retry behavior. Restore location and retry.
- Recenter: pan away, tap the toolbar location button, and confirm it returns to the current fix.
- Markers: pan to New York, inspect mock restroom names, dismiss/reopen, and verify no duplicate pins.
- Lifecycle: dismiss the sheet or background the app, then return; check no repeated permission prompts after authorization and no background tracking.

Verified during implementation: package resolution, simulator compilation/linking, and bundled Info.plist configuration. Live tile rendering and device permission/location flows require your configured Google key and manual verification.
