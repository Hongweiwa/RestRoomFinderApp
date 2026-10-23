import SwiftUI

struct ProfileAvatar: View {
    var name: String?
    var isGuest = false
    @ScaledMetric(relativeTo: .title) private var diameter = 88.0
    var body: some View {
        Group {
            if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(Self.initials(name)).font(AppTheme.Typography.title)
            } else {
                Image(systemName: isGuest ? "person.crop.circle" : "person.fill").font(AppTheme.Typography.title)
            }
        }
        .frame(width: diameter, height: diameter)
        .foregroundStyle(AppTheme.background)
        .background(AppTheme.foreground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isGuest ? "Guest avatar" : "Profile avatar\(name.map { " for \($0)" } ?? "")")
    }
    private static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        return [words.first?.first, words.count > 1 ? words.last?.first : nil]
            .compactMap { $0 }.map(String.init).joined().uppercased()
    }
}

struct ProfileMenuRow: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: AppTheme.Spacing.large) {
            Image(systemName: symbol).font(AppTheme.Typography.symbol)
                .frame(width: AppTheme.Metrics.minimumTapTarget).accessibilityHidden(true)
            Text(title).font(AppTheme.Typography.body).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.secondary).accessibilityHidden(true)
        }
        .padding(AppTheme.Spacing.large)
        .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
        .contentShape(Rectangle()).foregroundStyle(AppTheme.foreground)
    }
}

struct ProfileSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            SectionHeader(title: title, isEyebrow: true)
            VStack(spacing: 0) { content }
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
        }
    }
}
