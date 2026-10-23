import SwiftUI

struct AddRestroomView: View {
    @StateObject private var viewModel: AddRestroomViewModel
    let onSaved: (RestroomSubmission) -> Void
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var submissions: MySubmissionsViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var showMap = false
    init(service: any RestroomSubmissionServicing,userID: UUID,existing: RestroomSubmission? = nil,onSaved: @escaping (RestroomSubmission) -> Void) {
        _viewModel = StateObject(wrappedValue: AddRestroomViewModel(service: service,userID: userID,existing: existing)); self.onSaved = onSaved
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                if case .success(let submission) = viewModel.state { success(submission) }
                else {
                    VStack(alignment: .leading,spacing: AppTheme.Spacing.extraLarge) {
                        VStack(alignment: .leading,spacing: AppTheme.Spacing.extraLarge) {
                            Text("Your contribution stays private and pending until it is reviewed.").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                            input("Restroom Name",text: $viewModel.draft.name,prompt: "Name or a clear description",identifier: "submission-name")
                            locationSection
                            input("Address (optional)",text: $viewModel.draft.address,prompt: "Street address or entrance",identifier: "submission-address")
                            VStack(alignment: .leading,spacing: AppTheme.Spacing.large) {
                                SectionHeader(title: "Restroom Features")
                                Text("Choose Unknown when you are not sure.").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                                SubmissionFeaturePicker(title: "Wheelchair Accessibility",selection: $viewModel.draft.accessible)
                                SubmissionFeaturePicker(title: "Baby Changing Station",selection: $viewModel.draft.babyChanging)
                                SubmissionFeaturePicker(title: "Gender Neutral",selection: $viewModel.draft.genderNeutral)
                                SubmissionFeaturePicker(title: "Free to Use",selection: $viewModel.draft.free)
                                SubmissionFeaturePicker(title: "Family Restroom",selection: $viewModel.draft.family)
                                SubmissionFeaturePicker(title: "Open 24 Hours",selection: $viewModel.draft.allDay)
                            }
                            VStack(alignment: .leading,spacing: AppTheme.Spacing.small) {
                                Text("Additional Notes (optional)").font(AppTheme.Typography.headline)
                                Text("Describe how to find the entrance. Avoid personal information.").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                                TextEditor(text: $viewModel.draft.notes).frame(minHeight: 120)
                                    .padding(AppTheme.Spacing.small).scrollContentBackground(.hidden)
                                    .background(AppTheme.surface,in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                                    .accessibilityLabel("Additional notes").accessibilityIdentifier("submission-notes")
                                Text("\(SubmissionDraft.optional(viewModel.draft.notes)?.unicodeScalars.count ?? 0) / 1,000 characters")
                                    .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                            }
                        }.disabled(viewModel.isLocked)

                    }.padding(AppTheme.Spacing.extraLarge)
                }
            }
            .scrollDismissesKeyboard(.interactively).appScreenStyle()
            .navigationTitle(viewModel.existing == nil ? "Add a Restroom" : "Edit Submission").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if case .success = viewModel.state {} else {
                    VStack(spacing: AppTheme.Spacing.small) {
                        if case .error(let message) = viewModel.state {
                            Text(message).font(AppTheme.Typography.caption).accessibilityIdentifier("submission-error")
                        }
                        if viewModel.state == .checking { Text("Checking for possible duplicates…").font(AppTheme.Typography.caption) }
                        PrimaryButton(title: viewModel.existing == nil ? "Submit Restroom" : "Save Pending Submission",isLoading: viewModel.isBusy) {
                            Task { await viewModel.submit(knownRestrooms: submissions.knownRestrooms) }
                        }
                        .disabled(viewModel.isLocked || viewModel.state == .locating)
                        .accessibilityIdentifier("submit-restroom")
                    }.padding(AppTheme.Spacing.large).background(AppTheme.canvas)
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { viewModel.cancel(); dismiss() }.disabled(viewModel.isBusy)
            } }
        }
        .interactiveDismissDisabled(viewModel.isBusy)
        .sheet(isPresented: $showMap) { SubmissionLocationPicker(initial: viewModel.draft.coordinate,onConfirm: viewModel.choose) }
        .sheet(isPresented: Binding(get: { if case .warning = viewModel.state { return true }; return false },set: { if !$0 { viewModel.cancelWarning() } })) {
            if case .warning(let candidates,let failed) = viewModel.state {
                SubmissionDuplicateWarning(candidates: candidates,checkFailed: failed,
                    onContinue: { Task { await viewModel.submitAnyway() } },onCancel: viewModel.cancelWarning)
            }
        }
        .onReceive(locationManager.$state) { state in
            guard viewModel.state == .locating else { return }
            switch state {
            case .available:
                if let coordinate = SubmissionCoordinate.current(locationManager.location) { viewModel.choose(coordinate) }
                else { viewModel.locationUnavailable("Location unavailable. Choose a location on the map instead.") }
            case .denied: viewModel.locationUnavailable("Location permission is denied. Choose on Map, or enable location in iOS Settings.")
            case .restricted: viewModel.locationUnavailable("Location access is restricted. Choose a location on the map instead.")
            case .unavailable: viewModel.locationUnavailable("Location unavailable. Try again or choose on the map.")
            default: break
            }
        }
        .onChange(of: viewModel.state) { _, state in if case .success(let saved) = state { onSaved(saved) } }
        .onChange(of: auth.state.user?.id) { _, id in if id != viewModel.userID { viewModel.cancel(); dismiss() } }
    }
    private var locationSection: some View {
        VStack(alignment: .leading,spacing: AppTheme.Spacing.medium) {
            Text("Location").font(AppTheme.Typography.headline)
            SecondaryButton(title: viewModel.state == .locating ? "Finding Location…" : "Use Current Location",systemImage: "location") {
                if locationManager.isAuthorized, let coordinate = SubmissionCoordinate.current(locationManager.location) { viewModel.choose(coordinate) }
                else { viewModel.requestLocation(); locationManager.requestLocation() }
            }.disabled(viewModel.state == .locating)
            SecondaryButton(title: "Choose on Map",systemImage: "map") { showMap = true }
            if let coordinate = viewModel.draft.coordinate {
                Text("Selected: \(coordinate.description)").font(AppTheme.Typography.caption).monospacedDigit()
                Text("Confirm this is the restroom entrance. Device location can be approximate.").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
            } else { Text("Choose an exact coordinate. An address alone cannot be submitted.").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary) }
        }
    }
    private func input(_ title: String,text: Binding<String>,prompt: String,identifier: String) -> some View {
        VStack(alignment: .leading,spacing: AppTheme.Spacing.small) {
            Text(title).font(AppTheme.Typography.headline)
            TextField(prompt,text: text).textFieldStyle(.roundedBorder)
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
        }
    }
    private func success(_ record: RestroomSubmission) -> some View {
        VStack(spacing: AppTheme.Spacing.extraLarge) {
            Image(systemName: "checkmark.circle").font(AppTheme.Typography.title).accessibilityHidden(true)
            Text(viewModel.existing == nil ? "Restroom Submitted" : "Submission Updated").font(AppTheme.Typography.title)
            Text(record.status == .pending ? "Thanks for contributing. Your submission will be reviewed before it appears publicly." : "Your earlier submission was received and reviewed. Check its current status in My Submissions.")
            Text(record.name).font(AppTheme.Typography.headline)
            SubmissionStatusBadge(status: record.status)
            PrimaryButton(title: "Done") { dismiss() }
        }.multilineTextAlignment(.center).padding(AppTheme.Spacing.extraLarge)
    }
}
