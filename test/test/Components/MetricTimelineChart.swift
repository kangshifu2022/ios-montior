import Foundation
import SwiftUI

struct MetricTimelinePoint: Identifiable, Sendable {
    var id: Date { capturedAt }
    let capturedAt: Date
    let value: Double
}

struct MetricTimelineSeries: Identifiable {
    var id: String { title }
    let title: String
    let color: Color
    let points: [MetricTimelinePoint]
}

struct MetricTimelineChart: View {
    enum YAxisMode {
        case percent
        case adaptive(unitSuffix: String)
    }

    let series: [MetricTimelineSeries]
    let viewportWidth: CGFloat
    let emptyMessage: String
    let yAxisMode: YAxisMode

    private var visibleSeries: [MetricTimelineSeries] {
        series
            .map { series in
                MetricTimelineSeries(
                    title: series.title,
                    color: series.color,
                    points: series.points.sorted { $0.capturedAt < $1.capturedAt }
                )
            }
            .filter { !$0.points.isEmpty }
    }

    var body: some View {
        if visibleSeries.isEmpty {
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if visibleSeries.count > 1 {
                    legend
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    MetricTimelineChartPlot(
                        series: visibleSeries,
                        yAxisMode: yAxisMode
                    )
                    .frame(width: plotWidth, height: 228)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(visibleSeries) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)

                        Text(item.title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var plotWidth: CGFloat {
        let maxPointCount = visibleSeries.map { $0.points.count }.max() ?? 0
        let stepWidth = CGFloat(max(maxPointCount - 1, 1)) * 34
        return max(viewportWidth - 24, stepWidth + 92)
    }
}

private struct MetricTimelineChartPlot: View {
    let series: [MetricTimelineSeries]
    let yAxisMode: MetricTimelineChart.YAxisMode

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"
        return formatter
    }()

    private var allPoints: [MetricTimelinePoint] {
        series.flatMap(\.points)
    }

    private var yDomain: ClosedRange<Double> {
        let values = allPoints.map(\.value)

        switch yAxisMode {
        case .percent:
            return 0 ... 100
        case .adaptive:
            guard let minValue = values.min(), let maxValue = values.max() else {
                return 0 ... 1
            }

            let padding = max(2, (maxValue - minValue) * 0.18)
            let lowerBound = max(0, minValue - padding)
            let upperBound = max(lowerBound + 1, maxValue + padding)
            return lowerBound ... upperBound
        }
    }

    private var xDomain: ClosedRange<TimeInterval> {
        guard let firstDate = allPoints.map(\.capturedAt).min(),
              let lastDate = allPoints.map(\.capturedAt).max() else {
            let now = Date().timeIntervalSinceReferenceDate
            return now ... (now + 1)
        }

        let lowerBound = firstDate.timeIntervalSinceReferenceDate
        let upperBound = max(lastDate.timeIntervalSinceReferenceDate, lowerBound + 1)
        return lowerBound ... upperBound
    }

    private var yTickValues: [Double] {
        let lowerBound = yDomain.lowerBound
        let upperBound = yDomain.upperBound
        let step = (upperBound - lowerBound) / 4

        return (0...4).map { index in
            lowerBound + (Double(index) * step)
        }
    }

    private var xTickDates: [Date] {
        let start = xDomain.lowerBound
        let end = xDomain.upperBound
        let step = (end - start) / 4

        return (0...4).map { index in
            Date(timeIntervalSinceReferenceDate: start + (Double(index) * step))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let plotRect = CGRect(
                x: 46,
                y: 12,
                width: max(size.width - 58, 120),
                height: max(size.height - 42, 120)
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.03))

                grid(in: plotRect)

                ForEach(Array(yTickValues.enumerated()), id: \.offset) { entry in
                    let value = entry.element

                    Text(yAxisLabel(for: value))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .position(
                            x: 20,
                            y: yPosition(for: value, in: plotRect)
                        )
                }

                ForEach(Array(xTickDates.enumerated()), id: \.offset) { entry in
                    let tickDate = entry.element

                    Text(Self.timeFormatter.string(from: tickDate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .position(
                            x: xPosition(for: tickDate, in: plotRect),
                            y: plotRect.maxY + 14
                        )
                }

                ForEach(series) { item in
                    seriesPath(for: item, in: plotRect)
                        .stroke(
                            item.color,
                            style: StrokeStyle(
                                lineWidth: 2.1,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    pointMarkers(for: item, in: plotRect)
                }
            }
        }
    }

    private func grid(in plotRect: CGRect) -> some View {
        ZStack {
            ForEach(Array(yTickValues.enumerated()), id: \.offset) { entry in
                let value = entry.element
                Path { path in
                    let y = yPosition(for: value, in: plotRect)
                    path.move(to: CGPoint(x: plotRect.minX, y: y))
                    path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                }
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1))
            }

            ForEach(Array(xTickDates.enumerated()), id: \.offset) { entry in
                let tickDate = entry.element
                Path { path in
                    let x = xPosition(for: tickDate, in: plotRect)
                    path.move(to: CGPoint(x: x, y: plotRect.minY))
                    path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                }
                .stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 1))
            }
        }
    }

    private func seriesPath(for series: MetricTimelineSeries, in plotRect: CGRect) -> Path {
        let points = chartPoints(for: series, in: plotRect)
        guard let firstPoint = points.first else { return Path() }

        var path = Path()
        path.move(to: firstPoint)

        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }

    @ViewBuilder
    private func pointMarkers(for series: MetricTimelineSeries, in plotRect: CGRect) -> some View {
        let points = chartPoints(for: series, in: plotRect)

        if points.count == 1, let firstPoint = points.first {
            Circle()
                .fill(series.color)
                .frame(width: 7, height: 7)
                .position(firstPoint)
        } else if let lastPoint = points.last {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(series.color, lineWidth: 2.5)
                )
                .position(lastPoint)
        }
    }

    private func chartPoints(for series: MetricTimelineSeries, in plotRect: CGRect) -> [CGPoint] {
        series.points.map { point in
            CGPoint(
                x: xPosition(for: point.capturedAt, in: plotRect),
                y: yPosition(for: point.value, in: plotRect)
            )
        }
    }

    private func xPosition(for date: Date, in plotRect: CGRect) -> CGFloat {
        let domain = xDomain
        let total = max(domain.upperBound - domain.lowerBound, 1)
        let progress = (date.timeIntervalSinceReferenceDate - domain.lowerBound) / total
        return plotRect.minX + (CGFloat(progress) * plotRect.width)
    }

    private func yPosition(for value: Double, in plotRect: CGRect) -> CGFloat {
        let domain = yDomain
        let total = max(domain.upperBound - domain.lowerBound, 0.0001)
        let progress = (value - domain.lowerBound) / total
        return plotRect.maxY - (CGFloat(progress) * plotRect.height)
    }

    private func yAxisLabel(for value: Double) -> String {
        switch yAxisMode {
        case .percent:
            return "\(Int(value.rounded()))%"
        case .adaptive(let unitSuffix):
            return String(format: "%.0f%@", value, unitSuffix)
        }
    }
}
