import SwiftUI

/// Preview-only catalog; not a destination in the app.
private struct DesignSystemPreview: View {
    @State private var query = ""
    @State private var selected = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "Design system", subtitle: "Monochrome components")
                PrimaryButton(title: "Primary action", systemImage: "arrow.right") {}
                PrimaryButton(title: "Loading", isLoading: true) {}
                PrimaryButton(title: "Disabled") {}.disabled(true)
                SecondaryButton(title: "Secondary action") {}
                SecondaryButton(title: "Disabled") {}.disabled(true)
                SearchBar(text: $query)
                SearchBar(text: .constant("Sample query"))
                FilterChip(title: "Wheelchair accessible", isSelected: $selected)
                FilterChip(title: "Unselected", isSelected: .constant(false))
                FilterChip(title: "Disabled", isSelected: .constant(false)).disabled(true)
                RatingView(rating: 4.7, reviewCount: 128)
                RatingView(rating: 0, reviewCount: 0)
                RestroomCard(restroom: SampleRestrooms.all[0])
            }
            .padding(AppTheme.Spacing.large)
        }
        .appScreenStyle()
    }
}

#Preview("Light") {
    DesignSystemPreview().preferredColorScheme(.light)
}

#Preview("Dark") {
    DesignSystemPreview().preferredColorScheme(.dark)
}

#Preview("Accessibility text") {
    DesignSystemPreview().environment(\.dynamicTypeSize, .accessibility3)
}
