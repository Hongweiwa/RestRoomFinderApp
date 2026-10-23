import CoreLocation
import GoogleMaps
import SwiftUI

/// One persistent map; stable marker objects are updated only when data changes.
struct GoogleMapView: UIViewRepresentable {
    let restrooms: [Restroom]
    let location: CLLocation?
    let showsUserLocation: Bool
    let selectedRestroomID: UUID?
    let initialCenter: CLLocation?
    let recenterRequest: Int
    let onSelect: (UUID?) -> Void
    let onCameraIdle: (CLLocationCoordinate2D) -> Void

    /// Optional focused coordinate selection; Explore behavior stays on the existing callbacks.
    var onLocationPick: ((CLLocationCoordinate2D) -> Void)? = nil
    var isPreview = false
    var onUseCurrentLocation: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        let fallback = initialCenter?.coordinate ?? location?.coordinate ?? CLLocationCoordinate2D(latitude: 40.7536, longitude: -73.9832)
        options.camera = GMSCameraPosition(target: fallback, zoom: 15)
        let map = GMSMapView(options: options)
        map.delegate = context.coordinator
        map.settings.compassButton = !isPreview
        map.settings.myLocationButton = !isPreview && onLocationPick == nil
        map.settings.setAllGesturesEnabled(!isPreview)
        map.isUserInteractionEnabled = !isPreview
        if isPreview {
            map.mapStyle = try? GMSMapStyle(jsonString: "[{\"stylers\":[{\"saturation\":-100}]}]")
        }
        map.accessibilityElementsHidden = false
        context.coordinator.hasCentered = initialCenter != nil || location != nil
        context.coordinator.recenterRequest = recenterRequest
        updateUIView(map, context: context)
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        map.isMyLocationEnabled = showsUserLocation
        if coordinator.restrooms != restrooms {
            let ids = Set(restrooms.map(\.id))
            for id in Array(coordinator.markers.keys) where !ids.contains(id) {
                coordinator.markers.removeValue(forKey: id)?.map = nil
            }
            for restroom in restrooms {
                let marker = coordinator.markers[restroom.id] ?? GMSMarker(position: restroom.coordinate)
                marker.position = restroom.coordinate
                marker.title = restroom.name
                marker.snippet = restroom.address
                marker.userData = restroom.id
                marker.icon = coordinator.markerIcon
                marker.accessibilityLabel = "\(restroom.name), public restroom, \(restroom.distanceDescription)"
                marker.map = map
                coordinator.markers[restroom.id] = marker
            }
            coordinator.restrooms = restrooms
        }
        if coordinator.recenterRequest != recenterRequest, let target = initialCenter ?? location {
            map.animate(to: GMSCameraPosition(target: target.coordinate, zoom: LocationSearchConfiguration.discoveryZoom))
            coordinator.hasCentered = true
            coordinator.recenterRequest = recenterRequest
        } else if let location, !coordinator.hasCentered {
            map.animate(toLocation: location.coordinate)
            coordinator.hasCentered = true
        }
        if coordinator.selectedID != selectedRestroomID {
            coordinator.selectedID = selectedRestroomID
            if let id = selectedRestroomID, let marker = coordinator.markers[id] {
                map.selectedMarker = marker
                map.animate(toLocation: marker.position) // Keep the user's chosen zoom.
            } else {
                map.selectedMarker = nil
            }
        }
        for (id, marker) in coordinator.markers { marker.zIndex = id == selectedRestroomID ? 1 : 0 }
    }

    static func dismantleUIView(_ map: GMSMapView, coordinator: Coordinator) {
        map.delegate = nil
        map.isMyLocationEnabled = false
        coordinator.markers.values.forEach { $0.map = nil }
        coordinator.markers = [:]
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        var restrooms: [Restroom] = []
        var markers: [UUID: GMSMarker] = [:]
        let markerIcon = GMSMarker.markerImage(with: .black)
        var selectedID: UUID?
        var hasCentered = false
        var recenterRequest = 0
        var pickerInteracted = false

        init(parent: GoogleMapView) { self.parent = parent }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let id = marker.userData as? UUID else { return false }
            selectedID = id // Marker taps don't need an extra camera animation.
            mapView.selectedMarker = marker
            parent.onSelect(id)
            return true
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            if let pick = parent.onLocationPick {
                pickerInteracted = true
                pick(coordinate)
                mapView.animate(toLocation: coordinate)
                return
            }
            selectedID = nil
            mapView.selectedMarker = nil
            parent.onSelect(nil)
        }

        func didTapMyLocationButton(for mapView: GMSMapView) -> Bool {
            guard let action = parent.onUseCurrentLocation else { return false }
            action()
            return true
        }

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture, parent.onLocationPick != nil { pickerInteracted = true }
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            // This callback only records the center; never fetches Places.
            parent.onCameraIdle(position.target)
            if pickerInteracted { parent.onLocationPick?(position.target) }
        }
    }
}
