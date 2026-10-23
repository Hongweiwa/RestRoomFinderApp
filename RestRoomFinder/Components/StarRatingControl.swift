import SwiftUI

/// One VoiceOver-adjustable rating, with five large direct-touch targets.
struct StarRatingControl: View {
    let title: String
    @Binding var rating: Int
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(title).font(AppTheme.Typography.headline)
            HStack(spacing: AppTheme.Spacing.xs) {
                ForEach(1...5, id: \.self) { value in
                    Button { rating = value } label: {
                        Image(systemName: value <= rating ? "star.fill" : "star")
                            .font(AppTheme.Typography.title)
                            .frame(minWidth: AppTheme.Metrics.minimumTapTarget, minHeight: AppTheme.Metrics.minimumTapTarget)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("\(title)-star-\(value)")
                }
            }
            Text(rating == 0 ? "Choose a rating" : "\(rating) out of 5")
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) rating")
        .accessibilityValue(rating == 0 ? "Not selected" : "\(rating) out of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(1, rating - 1)
            @unknown default: break
            }
        }
    }
}
