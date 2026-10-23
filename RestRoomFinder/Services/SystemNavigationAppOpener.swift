import MapKit
import UIKit

@MainActor
struct SystemNavigationAppOpener: NavigationAppOpening {
    var isGoogleMapsInstalled: Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func openAppleMaps(item: MKMapItem, mode: TravelMode) async -> Bool {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
        return await withCheckedContinuation { continuation in
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode.appleDirectionsMode], from: scene) { success in
                continuation.resume(returning: success)
            }
        }
    }

    func openURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }
}
