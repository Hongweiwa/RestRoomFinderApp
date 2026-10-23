#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TEST_BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/restroom-tests.XXXXXX")
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$TEST_BUILD_DIR/modules" \
    RestRoomFinder/Models/Restroom.swift \
    RestRoomFinder/Models/RestroomSubmission.swift \
    RestRoomFinder/ViewModels/AddRestroomViewModel.swift \
    RestRoomFinder/ViewModels/MySubmissionsViewModel.swift \
    Tests/SubmissionTests.swift \
    RestRoomFinder/Models/RestroomReport.swift \
    RestRoomFinder/ViewModels/ReportViewModel.swift \
    RestRoomFinder/ViewModels/MyReportsViewModel.swift \
    Tests/ReportTests.swift \
    RestRoomFinder/Models/RestroomReview.swift \
    RestRoomFinder/ViewModels/ReviewsViewModel.swift \
    Tests/ReviewTests.swift \
    RestRoomFinder/Models/RestroomFilter.swift \
    RestRoomFinder/Models/SearchLocation.swift \
    RestRoomFinder/Models/TravelMode.swift \
    RestRoomFinder/Models/AuthState.swift \
    RestRoomFinder/Services/AuthenticationServicing.swift \
    RestRoomFinder/Services/ProfileServicing.swift \
    RestRoomFinder/ViewModels/ProfileViewModel.swift \
    Tests/ProfileTests.swift \
    RestRoomFinder/Models/FavoriteRecord.swift \
    RestRoomFinder/ViewModels/FavoritesViewModel.swift \
    Tests/FavoritesTests.swift \
    RestRoomFinder/ViewModels/AuthViewModel.swift \
    RestRoomFinder/Services/LocationSearching.swift \
    RestRoomFinder/Utilities/LocationSearchConfiguration.swift \
    RestRoomFinder/Services/DirectionsService.swift \
    RestRoomFinder/Services/SupabaseConfiguration.swift \
    RestRoomFinder/Resources/SampleRestrooms.swift \
    RestRoomFinder/Services/RestroomService.swift \
    RestRoomFinder/Services/RestroomPlaceMapper.swift \
    RestRoomFinder/Utilities/NearbySearchConfiguration.swift \
    RestRoomFinder/ViewModels/NearbyRestroomsViewModel.swift \
    Tests/LocationSearchTests.swift \
    Tests/DirectionsTests.swift \
    Tests/SupabaseConfigurationTests.swift \
    Tests/AuthenticationTests.swift \
    Tests/NearbyDiscoveryTests.swift -o "$TEST_BUILD_DIR/nearby-tests"
"$TEST_BUILD_DIR/nearby-tests"
