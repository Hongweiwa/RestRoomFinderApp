import SwiftUI

struct ReviewRow: View {
    let review: RestroomReview
    var isOwn = false
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(isOwn ? "You" : review.reviewerName).font(AppTheme.Typography.headline)
            Label("Restroom overall: \(review.overallRating) / 5", systemImage: "star.fill")
                .font(AppTheme.Typography.secondary)
            Text(review.cleanlinessRating.map { "Cleanliness: \($0) / 5" } ?? "Cleanliness: Not rated")
                .font(AppTheme.Typography.secondary)
            if let comment = review.comment { Text(comment).textSelection(.enabled) }
            Text(review.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.large)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
        .accessibilityElement(children: .contain)
    }
}
