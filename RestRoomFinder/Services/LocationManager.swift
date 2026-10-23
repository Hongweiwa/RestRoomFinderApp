import Combine
import CoreLocation

/// Reusable foreground-only location provider. Initialization never prompts.
@MainActor
final class LocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    enum State: Equatable {
        case notDetermined, locating, available, denied, restricted, unavailable
    }

    @Published private(set) var state: State = .notDetermined
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var location: CLLocation?
    private let manager: CLLocationManager
    private var isActive = false
    private var timeout: Task<Void, Never>?

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
        // CoreLocation delivers callbacks on the run loop where this manager
        // was created (the main actor); preconcurrency bridges its legacy delegate.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
    }

    /// Called when the map becomes visible or the user taps recenter/retry.
    func requestLocation() {
        isActive = true
        timeout?.cancel()
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            state = .notDetermined
            manager.requestWhenInUseAuthorization()
        case .denied:
            finishWithoutLocation(.denied)
        case .restricted:
            finishWithoutLocation(.restricted)
        case .authorizedWhenInUse, .authorizedAlways:
            state = .locating
            manager.requestLocation()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self, self.isActive, self.state == .locating else { return }
                self.finishWithoutLocation(.unavailable)
            }
        @unknown default:
            finishWithoutLocation(.unavailable)
        }
    }

    func stop() {
        isActive = false
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if !isAuthorized { location = nil }
        if isActive { requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isActive, isAuthorized else { return }
        guard let fix = locations.last(where: {
            $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 60
        }) else {
            finishWithoutLocation(.unavailable)
            return
        }
        timeout?.cancel()
        location = fix
        state = .available
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isActive else { return }
        // locationUnknown can be transient; leave the bounded request pending.
        if (error as? CLError)?.code == .locationUnknown { return }
        let status = manager.authorizationStatus
        finishWithoutLocation(status == .denied ? .denied : (status == .restricted ? .restricted : .unavailable))
    }

    private func finishWithoutLocation(_ newState: State) {
        timeout?.cancel()
        manager.stopUpdatingLocation()
        location = nil
        state = newState
    }
}
