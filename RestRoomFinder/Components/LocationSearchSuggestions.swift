import SwiftUI

/// Google's suggestions stay beside the existing search field; the ViewModel owns all requests.
struct LocationSearchSuggestions: View {
    @ObservedObject var viewModel: NearbyRestroomsViewModel
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 72

    var body: some View {
        if !viewModel.searchText.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                HStack {
                    Text("SEARCH LOCATIONS").font(AppTheme.Typography.eyebrow)
                    Spacer()
                    Button("Cancel") { viewModel.cancelLocationSearch() }
                        .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                        .accessibilityIdentifier("cancel-location-search")
                }
                switch viewModel.locationSearchState {
                case .idle: Text("Type at least 3 characters.")
                case .waiting: Text("Searching locations…")
                case .loading: HStack { ProgressView(); Text("Finding locations…") }
                case .resolving: HStack { ProgressView(); Text("Finding this location…") }
                case .empty: Text("No locations found.")
                case .error(let message):
                    Text(message)
                    Button("Try again") { viewModel.retryLocationSearch() }
                        .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                case .suggestions:
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.predictions) { prediction in
                                Button {
                                    Task { await viewModel.selectLocationPrediction(prediction) }
                                } label: {
                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                        Text(prediction.primaryText).font(AppTheme.Typography.headline)
                                        if let secondary = prediction.secondaryText, !secondary.isEmpty {
                                            Text(secondary).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.minimumTapTarget, alignment: .leading)
                                    .padding(.vertical, AppTheme.Spacing.small)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("location-prediction-\(prediction.id)")
                                Divider()
                            }
                        }
                    }
                    .frame(height: min(rowHeight * CGFloat(viewModel.predictions.count), rowHeight * 3))
                    GoogleMapsAttribution()
                }
            }
            .font(AppTheme.Typography.caption)
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
        }
    }
}

/// Official, unmodified light/dark assets; fixed clear space keeps attribution visible.
struct GoogleMapsAttribution: View {
    var body: some View {
        Image("GoogleMapsAttribution")
            .resizable()
            .scaledToFit()
            .frame(height: 18)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.top, AppTheme.Spacing.medium)
            .padding(.bottom, AppTheme.Spacing.small)
            .accessibilityLabel("Google Maps")
    }
}

struct SearchAreaSummary: View {
    let location: SearchLocation

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Label("Searching near \(location.name)", systemImage: "mappin.and.ellipse")
                .font(AppTheme.Typography.caption)
            if let attributions = location.attributions {
                Text(AttributedString(attributions)).font(AppTheme.Typography.caption)
            }
            GoogleMapsAttribution()
        }
    }
}
