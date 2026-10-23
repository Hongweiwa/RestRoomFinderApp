import SwiftUI

struct RestroomListView: View {
    @ObservedObject var viewModel: RestroomListViewModel

    var body: some View {
        List {
            Section {
                ForEach(viewModel.restrooms) { restroom in
                    NavigationLink(value: AppRoute.restroomDetail(restroom.id)) {
                        RestroomRow(restroom: restroom)
                            .padding(.vertical, AppTheme.Spacing.medium)
                    }
                }
            } header: {
                SectionHeader(title: "Explore restrooms")
            } footer: {
                Text("Fictional development data. Nearby search and live ratings are not connected yet.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.secondary)
                    .padding(.top, AppTheme.Spacing.large)
            }
            .listRowBackground(AppTheme.background)
        }
        .listStyle(.plain)
        .appScreenStyle()
        .navigationTitle("2RSaver")
    }
}
