import SwiftUI

/// Shared card collection for Home and the map. Both use the same filtered results and stable IDs.
struct NearbyRestroomCards: View {
    @ObservedObject var viewModel: NearbyRestroomsViewModel
    var onDirections: (Restroom) -> Void = { _ in }

    var body: some View {
        ForEach(viewModel.filteredRestrooms) { restroom in
            RestroomCard(restroom: restroom, style: .standard, onDirections: { onDirections(restroom) },
                         isSelected: viewModel.selectedRestroomID == restroom.id,
                         onSelect: { viewModel.select(restroom.id) })
                .id(restroom.id)
        }
    }
}
