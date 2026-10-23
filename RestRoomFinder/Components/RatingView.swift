import SwiftUI

/// A single star and numeric score remain compact at large text sizes.
struct RatingView: View {
    let rating: Double
    var tint: Color = AppTheme.foreground
    var reviewCount: Int? = nil

    private var score: Double { rating.isFinite ? min(max(rating, 0), 5) : 0 }
    private var formattedScore: String {
        score.formatted(.number.precision(.fractionLength(1)))
    }
    private var accessibilitySummary: String {
        let base = "\(formattedScore) out of 5 stars"
        guard let reviewCount else { return base }
        return base + ", \(max(reviewCount, 0)) reviews"
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "star.fill")
            Text(formattedScore).monospacedDigit()
            if let reviewCount {
                Text("(\(max(reviewCount, 0)))")
                    .foregroundStyle(AppTheme.secondary)
            }
        }
        .font(AppTheme.Typography.secondary)
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}
