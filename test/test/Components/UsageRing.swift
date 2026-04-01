import SwiftUI

struct UsageRing: View {
    let title: String
    let value: Double?
    let color: Color

    private var clampedValue: Double {
        min(max(value ?? 0, 0), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: clampedValue)
                    .stroke(
                        (value == nil ? Color(.systemGray4) : color).gradient,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Text(valueText)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundColor(.primary)

                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 72, height: 72)
        }
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
