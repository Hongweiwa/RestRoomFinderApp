import SwiftUI

/// A draft is committed only by Apply. Reset explicitly restores the active defaults.
struct RestroomFilterView: View {
    @ObservedObject var viewModel: NearbyRestroomsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: RestroomFilter

    init(viewModel: NearbyRestroomsViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.filter)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.medium),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.extraLarge) {
                    LazyVGrid(columns: columns, spacing: AppTheme.Spacing.medium) {
                        unavailableTile("Open Now", symbol: "clock.fill", large: true)
                        unavailableTile("Accessibility", symbol: "figure.roll", large: true)
                    }
                    cleanlinessSection
                    ratingSection
                    distanceSection
                    sortSection
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                        heading("FEATURES")
                        LazyVGrid(columns: columns, spacing: AppTheme.Spacing.medium) {
                            unavailableTile("Baby Care", symbol: "figure.and.child.holdinghands")
                            unavailableTile("Gender Neutral", symbol: "person.2")
                            unavailableTile("Touchless", symbol: "hand.raised")
                            unavailableTile("Free Entry", symbol: "banknote")
                        }
                        Text("Opening status and amenities aren't available in the current results. Cleanliness uses RestRoom Finder community reviews only.")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.secondary)
                    }
                }
                .padding(AppTheme.Spacing.extraLarge)
            }
            .background(AppTheme.canvas)
            .appScreenStyle()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: AppTheme.Spacing.medium) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .frame(width: AppTheme.Metrics.minimumTapTarget, height: AppTheme.Metrics.minimumTapTarget)
                        }
                        .accessibilityLabel("Cancel filters")
                        Text("Filters").font(AppTheme.Typography.title).accessibilityAddTraits(.isHeader)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("RESET") {
                        draft = RestroomFilter()
                        viewModel.resetFilters()
                    }
                    .font(AppTheme.Typography.eyebrow)
                    .tracking(2)
                    .accessibilityLabel("Reset filters and sorting")
                    .accessibilityIdentifier("reset-filters")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton(title: "APPLY FILTERS", cornerRadius: AppTheme.Radius.card) {
                    viewModel.updateFilter(draft)
                    dismiss()
                }
                .accessibilityIdentifier("apply-filters")
                .padding(AppTheme.Spacing.extraLarge)
                .background(AppTheme.canvas)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var cleanlinessSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            heading("CLEANLINESS RATING")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 65))]) {
                ForEach([0.0, 3.0, 3.5, 4.0, 4.5], id: \.self) { value in
                    let rating: Double? = value == 0 ? nil : value
                    Button(value == 0 ? "Any" : "\(value.formatted(.number.precision(.fractionLength(1))))+") {
                        draft.minimumCleanlinessRating = rating
                    }
                    .buttonStyle(AppButtonStyle(isPrimary: draft.minimumCleanlinessRating == rating,
                                                cornerRadius: AppTheme.Radius.compact, compact: true,
                                                horizontalPadding: AppTheme.Spacing.small))
                    .accessibilityLabel(value == 0 ? "Any cleanliness rating" : "Cleanliness \(value.formatted()) or higher")
                    .accessibilityAddTraits(draft.minimumCleanlinessRating == rating ? .isSelected : [])
                }
            }
            Text("Based on RestRoom Finder reviews. Unknown cleanliness is excluded when a minimum is selected.")
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            heading("GOOGLE RATING")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 100 : 60),
                                        spacing: AppTheme.Spacing.small)], spacing: AppTheme.Spacing.small) {
                ratingOption(nil)
                ForEach([3.0, 3.5, 4.0, 4.5], id: \.self) { ratingOption($0) }
            }
            Text("Google place ratings are a reference, not a cleanliness score. Unrated places are excluded when a minimum is selected.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.secondary)
        }
    }

    private func ratingOption(_ rating: Double?) -> some View {
        let selected = draft.minimumGoogleRating == rating
        let title = rating.map { "\($0.formatted(.number.precision(.fractionLength(1))))+" } ?? "Any"
        return Button(title) { draft.minimumGoogleRating = rating }
            .buttonStyle(AppButtonStyle(isPrimary: selected, cornerRadius: AppTheme.Radius.compact,
                                       compact: true, horizontalPadding: AppTheme.Spacing.small))
            .accessibilityLabel(rating.map { "Google rating \($0.formatted()) or higher" } ?? "Any Google rating")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            HStack {
                heading("MAX DISTANCE")
                Spacer()
                Text(draft.maximumDistanceMiles.map { "\($0.formatted(.number.precision(.fractionLength(1)))) mi" } ?? "Any")
                    .font(AppTheme.Typography.detailScore)
            }
            FilterChip(title: "Any distance", isSelected: Binding(
                get: { draft.maximumDistanceMiles == nil },
                set: { draft.maximumDistanceMiles = $0 ? nil : 1.5 }))
            Slider(value: Binding(get: { draft.maximumDistanceMiles ?? 1.5 },
                                  set: { draft.maximumDistanceMiles = $0 }), in: 0.5...5, step: 0.5)
                .accessibilityLabel("Maximum distance in miles")
                .accessibilityValue(draft.maximumDistanceMiles.map { "\($0.formatted()) miles" } ?? "Any distance")
                .accessibilityIdentifier("distance-filter")
            HStack {
                Text("0.5 MI")
                Spacer()
                Text("5.0 MI")
            }
            .font(AppTheme.Typography.badge)
            .foregroundStyle(AppTheme.secondary)
            Text(viewModel.userLocation == nil
                 ? "Location unavailable. A distance limit will exclude places until your location is available."
                 : "From your current location. Filters only narrow the results already loaded; they don't expand the map search area.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.secondary)
        }
        .padding(AppTheme.Spacing.extraLarge)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            heading("SORT BY")
            Picker("Sort by", selection: $draft.sortOption) {
                ForEach(RestroomSortOption.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.minimumTapTarget, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
            .accessibilityIdentifier("sort-restrooms")
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(AppTheme.Typography.eyebrow).tracking(2).accessibilityAddTraits(.isHeader)
    }

    private func unavailableTile(_ title: String, symbol: String, large: Bool = false) -> some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Image(systemName: symbol).font(large ? AppTheme.Typography.title : AppTheme.Typography.symbol)
                Text(title).font(large ? AppTheme.Typography.headline : AppTheme.Typography.caption)
                Text("Not available yet").font(AppTheme.Typography.badge)
            }
            .frame(maxWidth: .infinity, minHeight: large ? AppTheme.Metrics.detailTileHeight : 0, alignment: .leading)
            .padding(AppTheme.Spacing.large)
            .foregroundStyle(AppTheme.secondary)
            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: large ? AppTheme.Radius.card : AppTheme.Radius.control))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel("\(title), not available yet")
    }
}
