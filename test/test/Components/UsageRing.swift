import SwiftUI

struct UsageRing: View {
    let title: String
    let value: Double?
    let color: Color

    private var clampedValue: Double {
        min(max(value ?? 0, 0), 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: clampedValue)
                    .stroke(
                        (value == nil ? Color(.systemGray4) : color).gradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
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
            .frame(width: 92, height: 92)

            Text("实时占用")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.35), value: clampedValue)
    }

    private var valueText: String {
        guard let value else {
            return "--"
        }
        return "\(Int(min(max(value, 0), 1) * 100))%"
    }
}
