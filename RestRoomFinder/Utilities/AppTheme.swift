import SwiftUI
import UIKit

/// Shared monochrome palette that follows the device's appearance.
enum AppTheme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let extraLarge: CGFloat = 24
    }

    enum Radius {
        static let compact: CGFloat = 3
        static let control: CGFloat = 12
        static let card: CGFloat = 20
    }

    enum Typography {
        static let statusDot = Font.system(size: 7)
        static let detailTitle = Font.title2.weight(.black)
        static let detailScore = Font.title.weight(.heavy)
        static let cardTitle = Font.headline.weight(.semibold)
        static let eyebrow = Font.caption.weight(.bold)
        static let compactButton = Font.footnote.weight(.bold)
        static let badge = Font.caption2.weight(.bold)
        static let title = Font.title2.weight(.semibold)
        static let headline = Font.headline
        static let body = Font.body
        static let secondary = Font.subheadline
        static let caption = Font.footnote
        static let button = Font.headline
        static let symbol = Font.title3.weight(.medium)
    }

    enum Metrics {
        static let detailMapHeight: CGFloat = 140
        static let detailTileHeight: CGFloat = 100
        static let heroHeight: CGFloat = 230
        static let amenitySize: CGFloat = 26
        static let minimumTapTarget: CGFloat = 44
        static let symbolSize: CGFloat = 48
        static let borderWidth: CGFloat = 1
        static let disabledOpacity: Double = 0.45
        static let pressedOpacity: Double = 0.70
    }

    static let canvas = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 0.02 : 0.98, alpha: 1)
    })
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
    static let foreground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : .black
    })
    static let secondary = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 0.70 : 0.35, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 0.10 : 0.96, alpha: 1)
    })
}

private struct AppScreenStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTheme.Typography.body)
            .foregroundStyle(AppTheme.foreground)
            .tint(AppTheme.foreground)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func appScreenStyle() -> some View {
        modifier(AppScreenStyle())
    }
}
