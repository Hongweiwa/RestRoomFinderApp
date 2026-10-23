import SwiftUI

struct ReportView: View {
    @StateObject private var viewModel: ReportViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editingDetails: Bool
    let onSubmitted: (RestroomReport) -> Void
    let placeAttributions: NSAttributedString?
    init(service: any ReportServicing,restroom: Restroom,userID: UUID,placeAttributions: NSAttributedString? = nil,onSubmitted: @escaping (RestroomReport) -> Void) {
        _viewModel = StateObject(wrappedValue: ReportViewModel(service: service,restroom: restroom,userID: userID))
        self.onSubmitted = onSubmitted; self.placeAttributions = placeAttributions
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading,spacing: AppTheme.Spacing.extraLarge) {
                        if case .success(let report) = viewModel.state { success(report) }
                        else { form.disabled(viewModel.isLocked) }
                    }.padding(AppTheme.Spacing.extraLarge).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
                if case .success = viewModel.state {} else {
                    VStack(spacing: AppTheme.Spacing.small) {
                        if case .error(let message) = viewModel.state {
                            Text(message).font(AppTheme.Typography.caption).accessibilityIdentifier("report-error")
                        }
                        PrimaryButton(title: "Submit Report",isLoading: viewModel.isBusy) {
                            editingDetails = false
                            Task { await viewModel.submit() }
                        }.disabled(viewModel.isLocked).accessibilityIdentifier("submit-report")
                    }.padding(AppTheme.Spacing.large).background(AppTheme.canvas)
                }
            }.appScreenStyle()
            .navigationTitle("Report a Problem").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancel(); dismiss() }.disabled(viewModel.isBusy)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingDetails = false } }
            }
        }
        .interactiveDismissDisabled(viewModel.isBusy)
        .onChange(of: viewModel.state) { _, state in if case .success(let report) = state { onSubmitted(report) } }
        .onChange(of: auth.state.user?.id) { _, id in if id != viewModel.userID { viewModel.cancel(); dismiss() } }
    }
    private var form: some View {
        VStack(alignment: .leading,spacing: AppTheme.Spacing.extraLarge) {
            VStack(alignment: .leading,spacing: AppTheme.Spacing.small) {
                SectionHeader(title: "Which restroom?")
                Text(viewModel.restroom.name).font(AppTheme.Typography.headline)
                Text(viewModel.restroom.address).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                if viewModel.restroom.googlePlaceID != nil {
                    GoogleMapsAttribution()
                    if let placeAttributions { Text(AttributedString(placeAttributions)).font(AppTheme.Typography.caption) }
                }
            }
            Text("Reports are private and reviewed before any possible correction. Reporting here does not update Google Maps.")
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
            VStack(alignment: .leading,spacing: AppTheme.Spacing.small) {
                SectionHeader(title: "What's wrong?")
                ForEach(ReportType.allCases) { type in
                    Button {
                        viewModel.draft.type = type
                    } label: {
                        HStack(spacing: AppTheme.Spacing.medium) {
                            Image(systemName: viewModel.draft.type == type ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                            Text(type.title).font(AppTheme.Typography.body)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity,minHeight: AppTheme.Metrics.minimumTapTarget,alignment: .leading)
                        .padding(.horizontal,AppTheme.Spacing.medium)
                        .background(AppTheme.surface,in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(type.title).accessibilityAddTraits(viewModel.draft.type == type ? [.isSelected] : [])
                        .accessibilityIdentifier("report-type-\(type.rawValue)")
                }
            }
            VStack(alignment: .leading,spacing: AppTheme.Spacing.small) {
                Text(viewModel.draft.type == .other ? "Additional Details (required)" : "Additional Details (optional)").font(AppTheme.Typography.headline)
                Text("Describe the problem. Avoid personal information. Other requires at least 10 characters.")
                    .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                TextField("Describe the problem…",text: $viewModel.draft.details,axis: .vertical)
                    .lineLimit(4...8).padding(AppTheme.Spacing.medium)
                    .background(AppTheme.surface,in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                    .focused($editingDetails).accessibilityLabel("Additional Details").accessibilityIdentifier("report-details")
                Text("\(viewModel.draft.normalizedDetails?.unicodeScalars.count ?? 0) / 1,000 characters")
                    .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
            }
        }
    }
    private func success(_ report: RestroomReport) -> some View {
        VStack(spacing: AppTheme.Spacing.extraLarge) {
            Image(systemName: "checkmark.circle").font(AppTheme.Typography.title).accessibilityHidden(true)
            Text("Report Submitted").font(AppTheme.Typography.title)
            Text("Thank you for helping improve RestRoom Finder.")
            Text(report.status.explanation)
            ReportStatusBadge(status: report.status)
            PrimaryButton(title: "Done") { dismiss() }
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }
}

struct ReportStatusBadge: View {
    let status: ReportStatus
    var body: some View {
        Label(status.title,systemImage: status == .pending ? "clock" : status == .inReview ? "magnifyingglass" : status == .resolved ? "checkmark.circle" : "xmark.circle")
            .font(AppTheme.Typography.caption).padding(AppTheme.Spacing.small)
            .background(AppTheme.surface,in: Capsule())
            .accessibilityElement(children: .ignore).accessibilityLabel("Status: \(status.title)")
    }
}
