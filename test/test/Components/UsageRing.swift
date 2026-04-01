import SwiftUI

struct UsageRing: View {
    let title: String
    let value: Double?
    let color: Color

    private var clampedValue: Double {
        min(max(value ?? 0, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 6)

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
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.35), value: clampedValue)
    }

    private var valueText: String {
        guard let value else {
            return "--"
        }
        return "\(Int(min(max(value, 0), 1) * 100))%"
    }
}
