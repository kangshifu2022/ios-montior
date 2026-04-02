import SwiftUI

struct UsageRing: View {
    let title: String
    let value: Double?
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    private var clampedValue: Double {
        min(max(value ?? 0, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: 6)

            Circle()
                .trim(from: 0, to: clampedValue)
                .stroke(
                    (value == nil ? Color(.systemGray4) : color).gradient,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(valueText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(.primary)

                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 60, height: 60)
        .animation(.easeInOut(duration: 0.35), value: clampedValue)
    }

    private var trackColor: Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.30, green: 0.32, blue: 0.35)
        case .light:
            return Color(.systemGray5)
        @unknown default:
            return Color(.systemGray5)
        }
    }

    private var valueText: String {
        guard let value else {
            return "--"
        }
        return "\(Int(min(max(value, 0), 1) * 100))%"
    }
}
