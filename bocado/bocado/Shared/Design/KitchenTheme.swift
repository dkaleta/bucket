import SwiftUI

enum KitchenTheme {
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let cream = Color(red: 1, green: 0.993, blue: 0.972)
    static let ink = Color(red: 0.15, green: 0.22, blue: 0.16)
    static let muted = Color(red: 0.34, green: 0.38, blue: 0.32)
    static let sage = Color(red: 0.89, green: 0.91, blue: 0.85)
    static let butter = Color(red: 0.97, green: 0.92, blue: 0.76)
    static let line = Color(red: 0.89, green: 0.87, blue: 0.82)

    // Redesign palette: neutral surfaces with one warm accent. Pantry uses it first.
    static let accent = Color(red: 0.878, green: 0.043, blue: 0.255)
    static let surface = Color.white
    static let fill = Color(red: 0.965, green: 0.965, blue: 0.965)
    static let text = Color(red: 0.133, green: 0.133, blue: 0.133)
    static let secondary = Color(red: 0.416, green: 0.416, blue: 0.416)
    static let hairline = Color(red: 0.92, green: 0.92, blue: 0.92)
}

struct KitchenHeading: View {
    let title: Text
    let subtitle: String

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 47

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            title
                .font(.system(size: titleSize, weight: .medium, design: .serif))
                .tracking(-1.9)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(KitchenTheme.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
