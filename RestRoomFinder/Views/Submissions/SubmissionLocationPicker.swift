import SwiftUI

/// Uses GoogleMapView's optional coordinate-selection mode. No Places or geocoding requests.
struct SubmissionLocationPicker: View {
    let initial: SubmissionCoordinate?
    let onConfirm: (SubmissionCoordinate) -> Void
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SubmissionCoordinate?
    @State private var mapCenter: SubmissionCoordinate?
    @State private var recenterRequest = 0
    @State private var latitudeText: String
    @State private var longitudeText: String
    @State private var error: String?
    init(initial: SubmissionCoordinate?,onConfirm: @escaping (SubmissionCoordinate) -> Void) {
        self.initial = initial; self.onConfirm = onConfirm
        _selected = State(initialValue: initial)
        _mapCenter = State(initialValue: initial)
        _latitudeText = State(initialValue: initial.map { String($0.latitude) } ?? "")
        _longitudeText = State(initialValue: initial.map { String($0.longitude) } ?? "")
    }
    private var canConfirm: Bool {
        guard let selected, selected.isValid,
              let latitude = Double(SubmissionDraft.trimmed(latitudeText).replacingOccurrences(of: ",",with: ".")),
              let longitude = Double(SubmissionDraft.trimmed(longitudeText).replacingOccurrences(of: ",",with: ".")) else { return false }
        return latitude == selected.latitude && longitude == selected.longitude
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: AppTheme.Spacing.large) {
                    Text("Move the map beneath the pin, or tap a location. Confirm the exact restroom entrance.")
                        .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                    if GoogleMapsConfiguration.isConfigured {
                        GoogleMapView(restrooms: [],location: nil,showsUserLocation: false,selectedRestroomID: nil,
                            initialCenter: mapCenter?.location ?? SubmissionCoordinate.current(locationManager.location)?.location,
                            recenterRequest: recenterRequest,onSelect: { _ in },onCameraIdle: { _ in },onLocationPick: { coordinate in
                                choose(.init(latitude: coordinate.latitude,longitude: coordinate.longitude))
                            })
                            .frame(height: 300)
                            .overlay { Image(systemName: "mappin").font(AppTheme.Typography.title).offset(y: -15).accessibilityHidden(true).allowsHitTesting(false) }
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                            .accessibilityLabel("Restroom location picker. Move map to position the pin.")
                    } else {
                        Text("Map unavailable. Enter coordinates below or use your current location in the form.")
                            .foregroundStyle(AppTheme.secondary)
                    }
                    if let selected { Text("Selected location: \(selected.description)").font(AppTheme.Typography.caption).monospacedDigit() }
                    Text("Coordinates").font(AppTheme.Typography.headline)
                    Text("You can also enter exact coordinates. Latitude −90 to 90; longitude −180 to 180.")
                        .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                    VStack(alignment: .leading,spacing: AppTheme.Spacing.small) {
                        Text("Latitude")
                        TextField("Latitude",text: $latitudeText).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).accessibilityIdentifier("submission-latitude")
                        Text("Longitude")
                        TextField("Longitude",text: $longitudeText).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).accessibilityIdentifier("submission-longitude")
                    }
                    SecondaryButton(title: "Use Entered Coordinates") {
                        guard let latitude = Double(SubmissionDraft.trimmed(latitudeText).replacingOccurrences(of: ",",with: ".")),
                              let longitude = Double(SubmissionDraft.trimmed(longitudeText).replacingOccurrences(of: ",",with: ".")),
                              SubmissionCoordinate(latitude: latitude,longitude: longitude).isValid else {
                            error = "Enter valid latitude and longitude values."; return
                        }
                        choose(.init(latitude: latitude,longitude: longitude),recenter: true)
                    }
                    if let error { Text(error).font(AppTheme.Typography.caption) }
                }.padding(AppTheme.Spacing.extraLarge)
            }
            .appScreenStyle().scrollDismissesKeyboard(.interactively)
            .navigationTitle("Choose Location").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Confirm Location") {
                    if let selected, canConfirm { onConfirm(selected); dismiss() }
                }.disabled(!canConfirm).padding(AppTheme.Spacing.large).background(AppTheme.canvas)
            }
        }
    }
    private func choose(_ value: SubmissionCoordinate,recenter: Bool = false) {
        guard value.isValid else { return }
        if recenter { mapCenter = value; recenterRequest += 1 }
        selected = value; latitudeText = String(value.latitude); longitudeText = String(value.longitude); error = nil
    }
}
