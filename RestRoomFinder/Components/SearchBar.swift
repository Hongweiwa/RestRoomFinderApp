import SwiftUI

/// Text entry only. The caller owns search behavior and results.
struct SearchBar: View {
    @Binding var text: String
    var placeholder = "Search restrooms"
    var focusRequest: UUID? = nil
    var surface: Color = AppTheme.surface
    var compact = false
    var dismissFocusRequest = 0
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .font(compact ? AppTheme.Typography.secondary : AppTheme.Typography.body)
                .foregroundStyle(AppTheme.foreground)
                .tint(AppTheme.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onChange(of: focusRequest) { _, _ in isFocused = true }
                .onChange(of: dismissFocusRequest) { _, _ in isFocused = false }
                .onSubmit(onSubmit)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: AppTheme.Metrics.minimumTapTarget,
                               height: AppTheme.Metrics.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, AppTheme.Spacing.medium)
        .padding(.trailing, text.isEmpty ? AppTheme.Spacing.medium : 0)
        .padding(.vertical, AppTheme.Spacing.xs)
        .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
        .background(surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
        .opacity(isEnabled ? 1 : AppTheme.Metrics.disabledOpacity)
    }
}
