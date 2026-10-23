#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROFILE_UI_DIR=$(mktemp -d "${TMPDIR:-/tmp}/restroom-profile-ui.XXXXXX")
PROFILE_UI_APP="$PROFILE_UI_DIR/ProfileUITests.app"
mkdir -p "$PROFILE_UI_APP"
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
SDKROOT="$SDK_PATH" xcrun --sdk iphonesimulator swiftc -parse-as-library -sdk "$SDK_PATH" -target arm64-apple-ios17.0-simulator \
    -module-cache-path "$PROFILE_UI_DIR/modules" \
    RestRoomFinder/Models/AuthState.swift \
    RestRoomFinder/Models/RestroomReport.swift \
    RestRoomFinder/ViewModels/ReportViewModel.swift \
    RestRoomFinder/ViewModels/MyReportsViewModel.swift \
    RestRoomFinder/Components/ReportRestroomButton.swift \
    RestRoomFinder/Views/Reports/*.swift \
    RestRoomFinder/Models/RestroomSubmission.swift \
    RestRoomFinder/ViewModels/AddRestroomViewModel.swift \
    RestRoomFinder/ViewModels/MySubmissionsViewModel.swift \
    RestRoomFinder/Components/AddRestroomButton.swift \
    RestRoomFinder/Components/SubmissionFeaturePicker.swift \
    RestRoomFinder/Views/Submissions/*.swift \
    RestRoomFinder/Models/Restroom.swift \
    RestRoomFinder/Models/RestroomReview.swift \
    RestRoomFinder/ViewModels/ReviewsViewModel.swift \
    RestRoomFinder/Components/StarRatingControl.swift \
    RestRoomFinder/Components/ReviewRow.swift \
    RestRoomFinder/Views/Reviews/*.swift \
    RestRoomFinder/Models/FavoriteRecord.swift \
    RestRoomFinder/ViewModels/FavoritesViewModel.swift \
    RestRoomFinder/Components/FavoriteButton.swift \
    RestRoomFinder/Components/RestroomCard.swift \
    RestRoomFinder/Components/RatingView.swift \
    RestRoomFinder/Views/Saved/SavedRestroomsView.swift \
    RestRoomFinder/Services/AuthenticationServicing.swift \
    RestRoomFinder/Services/ProfileServicing.swift \
    RestRoomFinder/ViewModels/AuthViewModel.swift \
    RestRoomFinder/ViewModels/ProfileViewModel.swift \
    RestRoomFinder/Utilities/AppTheme.swift \
    RestRoomFinder/Components/PrimaryButton.swift \
    RestRoomFinder/Components/SecondaryButton.swift \
    RestRoomFinder/Components/AuthFields.swift \
    RestRoomFinder/Components/AppBottomBar.swift \
    RestRoomFinder/Components/SectionHeader.swift \
    RestRoomFinder/Components/ProfileComponents.swift \
    RestRoomFinder/Views/Authentication/*.swift \
    RestRoomFinder/Views/Profile/*.swift \
    Tests/ProfileUITestHost.swift -o "$PROFILE_UI_APP/ProfileUITests"
cat > "$PROFILE_UI_APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.RestRoomFinder.ProfileUITests</string>
<key>CFBundleExecutable</key><string>ProfileUITests</string>
<key>CFBundleName</key><string>Profile UI Tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UILaunchScreen</key><dict/>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
</dict></plist>
PLIST
codesign --force --sign - "$PROFILE_UI_APP" >/dev/null
printf '%s\n' "$PROFILE_UI_APP"
