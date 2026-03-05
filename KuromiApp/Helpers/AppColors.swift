import SwiftUI

extension Color {
    // Backgrounds — computed vars ensure SwiftUI re-evaluates on appearance change
    static var appBackground: Color { Color(uiColor: .systemBackground) }
    static var appSheetBackground: Color { Color(uiColor: .secondarySystemBackground) }
    static var appFieldBackground: Color { Color(uiColor: .tertiarySystemBackground) }

    // Text — SwiftUI-native adaptive colors (guaranteed reactive to color scheme)
    static var appLabel: Color { .primary }
    static var appSecondaryLabel: Color { .secondary }

    // Borders
    static var appBorder: Color { Color(uiColor: .separator) }

    // Accent (stays purple in both modes)
    static let appAccent = Color.purple
}
