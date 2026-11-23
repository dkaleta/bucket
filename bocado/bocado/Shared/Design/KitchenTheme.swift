import SwiftUI

enum KitchenTheme {
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let cream = Color(red: 1, green: 0.993, blue: 0.972)
    static let ink = Color(red: 0.15, green: 0.22, blue: 0.16)
    static let muted = Color(red: 0.34, green: 0.38, blue: 0.32)
    static let sage = Color(red: 0.89, green: 0.91, blue: 0.85)
    static let butter = Color(red: 0.97, green: 0.92, blue: 0.76)
    static let line = Color(red: 0.89, green: 0.87, blue: 0.82)
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
