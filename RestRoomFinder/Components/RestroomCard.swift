import SwiftUI

/// Each card exposes a dedicated 44-point details link, separate from directions.
struct RestroomCard: View {
    let restroom: Restroom
    var style: Style = .standard
    var onDirections: () -> Void = {}
    var isSelected = false
    var onSelect: (() -> Void)? = nil
    var onOpenDetails: (() -> Void)? = nil
    enum Style { case featured, standard, compact }

    private var distance: String {
        guard let meters = restroom.distance else { return "Distance unavailable" }
        return "\((meters / 1609.344).formatted(.number.precision(.fractionLength(1)))) mi"
    }

    private var cleanliness: String {
        guard let rating = restroom.cleanlinessRating else { return "Cleanliness unknown" }
        return "Cleanliness \(rating.formatted(.number.precision(.fractionLength(1))))/5"
    }

    var body: some View {
        Group {
            if style == .featured { featured } else { regular }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                .strokeBorder(isSelected ? AppTheme.foreground : AppTheme.secondary.opacity(0.12), lineWidth: AppTheme.Metrics.borderWidth * (isSelected ? 2 : 1))
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control))
        .onTapGesture { onSelect?() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Select restroom") { onSelect?() }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("restroom-card-\(restroom.id.uuidString)")
    }

    private var detailsLink: some View {
        Group {
            if let onOpenDetails { Button(action: onOpenDetails) { detailsArrow } }
            else { NavigationLink(value: AppRoute.restroomDetail(restroom.id)) { detailsArrow } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View details for \(restroom.name)")
        .accessibilityIdentifier("restroom-details-\(restroom.id.uuidString)")
    }

    private var detailsArrow: some View {
        Image(systemName: "chevron.right").font(AppTheme.Typography.headline)
            .frame(width: AppTheme.Metrics.minimumTapTarget, height: AppTheme.Metrics.minimumTapTarget)
            .contentShape(Rectangle())
    }

    private var regular: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.xs) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text(restroom.name).font(AppTheme.Typography.cardTitle)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppTheme.Spacing.small) { ratingAndDistance }
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) { ratingAndDistance }
                    }
                }
                Spacer(minLength: 0)
                if style != .compact { amenities }
                detailsLink.foregroundStyle(AppTheme.secondary)
            }
            if restroom.googlePlaceID != nil {
                Text(restroom.address).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
            }
            Text("\(cleanliness) · \(restroom.accessibilityDescription)")
                .font(AppTheme.Typography.badge)
                .foregroundStyle(AppTheme.secondary)
            if style != .compact {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.medium) { status; directions }
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) { status; directions }
                }
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(restroom.isOpenNow == true ? AppTheme.surface : AppTheme.canvas)
    }

    @ViewBuilder private var ratingAndDistance: some View {
        if let rating = restroom.overallRating {
            HStack(spacing: AppTheme.Spacing.xs) {
                RatingView(rating: rating, reviewCount: restroom.reviewCount)
                Text("RestRoom Finder").font(AppTheme.Typography.badge)
            }
        } else if let rating = restroom.googleRating {
            HStack(spacing: AppTheme.Spacing.xs) {
                RatingView(rating: rating)
                Text("Google").font(AppTheme.Typography.badge)
            }
        } else { Text("Not rated").font(AppTheme.Typography.caption) }
        Text("· \(restroom.distanceDescription)").font(AppTheme.Typography.caption)
    }

    private var amenities: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            if restroom.accessibility == true {
                amenity("figure.roll", label: "Wheelchair accessible")
            }
            if restroom.cleanlinessRating != nil { amenity("checkmark.shield.fill", label: cleanliness) }
        }
    }

    private func amenity(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol)
            .font(AppTheme.Typography.caption)
            .frame(width: AppTheme.Metrics.amenitySize, height: AppTheme.Metrics.amenitySize)
            .background(AppTheme.secondary.opacity(0.08), in: Circle())
            .accessibilityLabel(label)
    }

    private var status: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "circle.fill").font(AppTheme.Typography.statusDot)
                .accessibilityHidden(true)
            Text(restroom.availabilityDescription.uppercased())
        }
        .font(AppTheme.Typography.badge)
        .foregroundStyle(restroom.isOpenNow == true ? AppTheme.foreground : AppTheme.secondary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var directions: some View {
        Group {
            if restroom.isOpenNow == true {
                PrimaryButton(title: "GET DIRECTIONS", systemImage: "location.fill", cornerRadius: AppTheme.Radius.compact, iconAtEnd: true, compact: true, action: onDirections)
            } else {
                SecondaryButton(title: "GET DIRECTIONS", systemImage: "location.fill", cornerRadius: AppTheme.Radius.compact, iconAtEnd: true, compact: true, action: onDirections)
            }
        }
        .accessibilityLabel("Get directions to \(restroom.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "this restroom" : restroom.name)")
        .accessibilityIdentifier("restroom-directions-\(restroom.id.uuidString)")
    }

    private var featured: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Spacer(minLength: 100)
            Text("BEST MATCH BASED ON DISTANCE\nAND SELECTED FILTERS")
                .font(AppTheme.Typography.badge)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(.white, in: Capsule())
                .foregroundStyle(.black)
            HStack(alignment: .bottom, spacing: AppTheme.Spacing.xs) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(restroom.name).font(AppTheme.Typography.title)
                    Text("\(restroom.address.uppercased()) · \(distance.uppercased())")
                        .font(AppTheme.Typography.caption)
                    Text("\(cleanliness) · \(restroom.accessibilityDescription)")
                        .font(AppTheme.Typography.badge)
                }
                Spacer(minLength: 0)
                VStack(spacing: AppTheme.Spacing.xs) {
                    detailsLink
                    if let rating = restroom.overallRating {
                        RatingView(rating: rating, tint: .white)
                            .padding(AppTheme.Spacing.xs)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact))
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(AppTheme.Spacing.large)
        .frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.heroHeight, alignment: .bottomLeading)
        .background {
            GeometryReader { geometry in
                // The Figma asset is flattened. Show only its upper artwork;
                // exclude baked-in text and render all card content accessibly above.
                Image("HomeHero").resizable()
                    .accessibilityHidden(true)
                    .frame(width: geometry.size.width, height: geometry.size.height * 1.85)
                    .frame(height: geometry.size.height, alignment: .top)
                    .clipped()
            }
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
        }
    }
}
