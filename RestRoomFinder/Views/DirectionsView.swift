import SwiftUI

/// Shared by Details and quick actions; owns a value snapshot of the destination.
struct DirectionsView: View {
    let restroom: Restroom
    private let service = DirectionsService(opener: SystemNavigationAppOpener())
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TravelMode = .walking
    @State private var isOpening = false
    @State private var errorMessage: String?

    private var displayName: String {
        restroom.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Public restroom" : restroom.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.extraLarge) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        SectionHeader(title: "DESTINATION", isEyebrow: true)
                        Text(displayName).font(AppTheme.Typography.title)
                        if !restroom.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(restroom.address).font(AppTheme.Typography.secondary).foregroundStyle(AppTheme.secondary)
                        }
                    }
                    if DirectionsService.isValid(restroom.coordinate) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "TRAVEL MODE", isEyebrow: true)
                            Picker("Travel mode", selection: $mode) {
                                ForEach(TravelMode.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                            .accessibilityIdentifier("directions-travel-mode")
                        }
                        VStack(spacing: AppTheme.Spacing.medium) {
                            PrimaryButton(title: "Apple Maps", systemImage: "map") { open(.appleMaps) }
                                .accessibilityLabel("Open directions in Apple Maps")
                                .accessibilityIdentifier("directions-apple-maps")
                            SecondaryButton(title: service.isGoogleMapsInstalled ? "Google Maps" : "Google Maps on the web",
                                            systemImage: "arrow.up.right.square") { open(.googleMaps) }
                                .accessibilityLabel(service.isGoogleMapsInstalled ? "Open directions in Google Maps" : "Open directions in Google Maps on the web")
                                .accessibilityIdentifier("directions-google-maps")
                        }
                        Text("Your navigation app uses your current location as the starting point.")
                            .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                        if isOpening { ProgressView("Opening directions…") }
                    } else {
                        Text(DirectionsService.Failure.invalidDestination.localizedDescription)
                            .accessibilityIdentifier("directions-invalid-destination")
                    }
                }
                .padding(AppTheme.Spacing.extraLarge)
                .disabled(isOpening)
            }
            .appScreenStyle()
            .navigationTitle("Get Directions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isOpening) }
            }
            .alert("Unable to open directions", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isOpening)
    }

    private func open(_ app: DirectionsService.NavigationApp) {
        guard !isOpening else { return }
        isOpening = true
        Task { @MainActor in
            defer { isOpening = false }
            do {
                try await service.open(app, restroom: restroom, mode: mode)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
