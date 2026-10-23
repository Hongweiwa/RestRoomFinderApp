import SwiftUI

struct SubmissionFeaturePicker: View {
    let title: String
    @Binding var selection: SubmissionFeature
    var body: some View {
        VStack(alignment: .leading,spacing: AppTheme.Spacing.small) {
            Text(title).font(AppTheme.Typography.headline)
            Picker(title,selection: $selection) {
                ForEach(SubmissionFeature.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity,minHeight: AppTheme.Metrics.minimumTapTarget,alignment: .leading)
            .padding(.horizontal,AppTheme.Spacing.medium)
            .background(AppTheme.surface,in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
            .accessibilityLabel(title).accessibilityValue(selection.rawValue)
        }
    }
}

struct SubmissionStatusBadge: View {
    let status: SubmissionStatus
    var body: some View {
        Label(status.title,systemImage: status.symbol)
            .font(AppTheme.Typography.caption)
            .padding(.horizontal,AppTheme.Spacing.medium).padding(.vertical,AppTheme.Spacing.small)
            .background(AppTheme.surface,in: Capsule())
            .accessibilityLabel("Submission status: \(status.title)")
    }
}
