import SwiftUI
import Charts

enum ChartTab: String, CaseIterable, Identifiable {
    case day24 = "24h"
    case day7 = "7d"
    case day30 = "30d"

    var id: String { rawValue }
}

struct RemainingPercentPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
    let type: String
}

struct DailyConsumption: Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let date: Date
    let fiveHourConsumed: Double
    let weeklyConsumed: Double
}

struct ConsumptionBarPoint: Identifiable {
    let id = UUID()
    let dayKey: String
    let value: Double
    let type: String
}

struct QuotaChartView: View {
    @EnvironmentObject private var store: QuotaStore
    @State private var selectedTab: ChartTab = .day24

    private var fiveHourLabel: String { store.t("5小时额度", "5h Quota") }
    private var weeklyLabel: String { store.t("周额度", "Weekly Quota") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabBar

            if selectedTab == .day24 {
                remainingChart
            } else {
                consumptionChart
            }
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(ChartTab.allCases) { tab in
                Button {
                    withAnimation(OS27.Motion.interactive) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tabTitle(tab))
                        .font(.caption.weight(selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            ZStack {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(.regularMaterial)
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(LinearGradient(
                                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ), lineWidth: 0.5)
                                        .blendMode(.plusLighter)
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(OS27.Stroke.hairline, lineWidth: 0.5)
            }
        )
    }

    // MARK: - Legend

    private struct LegendItem: View {
        let color: Color
        let label: String
        var dashed: Bool = false

        var body: some View {
            HStack(spacing: 5) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: 14, height: 4)
                    .opacity(dashed ? 0.65 : 1)
                    .overlay(alignment: .center) {
                        if dashed {
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Rectangle()
                                        .fill(Color.white.opacity(0.5))
                                        .frame(width: 1.5, height: 4)
                                }
                            }
                        }
                    }
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            LegendItem(color: Color.quotaLow, label: fiveHourLabel)
            LegendItem(color: Color.quotaNormal, label: weeklyLabel, dashed: true)
            Spacer()
            if let current = store.snapshot.percentRemaining {
                HStack(spacing: 4) {
                    Text(store.t("当前", "Now"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(current)%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.menuColor)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Remaining (24h) chart

    private var remainingChart: some View {
        let points = remainingPercentPoints
        return VStack(alignment: .leading, spacing: 8) {
            legend
            if points.isEmpty {
                emptyStateView
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Percent", point.value)
                        )
                        .foregroundStyle(by: .value("Type", point.type))
                        .lineStyle(StrokeStyle(
                            lineWidth: point.type == fiveHourLabel ? 1.7 : 1.4,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: point.type == weeklyLabel ? [4, 3] : []
                        ))
                        .interpolationMethod(.monotone)
                    }

                    RuleMark(y: .value("Threshold", Double(store.lowThreshold)))
                        .foregroundStyle(Color.quotaLow.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("\(store.lowThreshold)%")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.quotaLow.opacity(0.85))
                                .monospacedDigit()
                                .padding(.trailing, 2)
                        }
                }
                .chartForegroundStyleScale([
                    fiveHourLabel: Color.quotaLow,
                    weeklyLabel: Color.quotaNormal
                ])
                .chartLegend(.hidden)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(OS27.Stroke.hairline)
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(OS27.Stroke.hairline.opacity(0.6))
                        AxisValueLabel()
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 132)
                .padding(10)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.primary.opacity(0.04), Color.primary.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                        RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                            .stroke(OS27.Stroke.hairline, lineWidth: 0.5)
                    }
                )
            }
        }
    }

    // MARK: - Consumption (7d / 30d) chart

    private var consumptionChart: some View {
        let limit = selectedTab == .day7 ? 7 : 30
        let points = consumptionPoints(limit: limit)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                LegendItem(color: Color.quotaLow, label: fiveHourLabel)
                LegendItem(color: Color.quotaNormal, label: weeklyLabel)
                Spacer()
            }
            if points.isEmpty {
                emptyStateView
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", point.dayKey),
                        y: .value("Consumed", point.value)
                    )
                    .foregroundStyle(by: .value("Type", point.type))
                    .position(by: .value("Type", point.type))
                    .cornerRadius(3)
                }
                .chartForegroundStyleScale([
                    fiveHourLabel: LinearGradient(
                        colors: [Color.quotaLow, Color.quotaLow.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    weeklyLabel: LinearGradient(
                        colors: [Color.quotaNormal, Color.quotaNormal.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                ])
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(OS27.Stroke.hairline)
                        AxisValueLabel()
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: selectedTab == .day7 ? 7 : 6)) { _ in
                        AxisValueLabel()
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 132)
                .padding(10)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.primary.opacity(0.04), Color.primary.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                        RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                            .stroke(OS27.Stroke.hairline, lineWidth: 0.5)
                    }
                )
            }
        }
    }

    // MARK: - Helpers

    private func tabTitle(_ tab: ChartTab) -> String {
        switch tab {
        case .day24:
            return store.t("24小时余量", "24h Remainder")
        case .day7:
            return store.t("7天消耗", "7d Consumption")
        case .day30:
            return store.t("30天消耗", "30d Consumption")
        }
    }

    private var remainingPercentPoints: [RemainingPercentPoint] {
        var points: [RemainingPercentPoint] = []
        for record in store.historyData {
            if let fiveHour = record.fiveHourPercentRemaining {
                points.append(RemainingPercentPoint(time: record.capturedAt, value: Double(fiveHour), type: fiveHourLabel))
            }
            if let weekly = record.weeklyPercentRemaining {
                points.append(RemainingPercentPoint(time: record.capturedAt, value: Double(weekly), type: weeklyLabel))
            }
        }
        return points
    }

    private var dailyConsumptionData: [DailyConsumption] {
        var groups: [String: (fiveHour: Double, weekly: Double)] = [:]
        for bucket in store.usageBuckets {
            let key = bucket.dayKey
            groups[key, default: (0, 0)].fiveHour += bucket.fiveHourConsumedPercent
            groups[key, default: (0, 0)].weekly += bucket.weeklyConsumedPercent
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return groups.map { key, value in
            let date = formatter.date(from: key) ?? Date()
            return DailyConsumption(
                dayKey: key,
                date: date,
                fiveHourConsumed: value.fiveHour,
                weeklyConsumed: value.weekly
            )
        }
        .sorted { $0.dayKey < $1.dayKey }
    }

    private func consumptionPoints(limit: Int) -> [ConsumptionBarPoint] {
        let daily = dailyConsumptionData.suffix(limit)
        var points: [ConsumptionBarPoint] = []
        for d in daily {
            let components = d.dayKey.split(separator: "-")
            let shortKey = components.count >= 3 ? "\(components[1])-\(components[2])" : d.dayKey

            points.append(ConsumptionBarPoint(dayKey: shortKey, value: d.fiveHourConsumed, type: fiveHourLabel))
            points.append(ConsumptionBarPoint(dayKey: shortKey, value: d.weeklyConsumed, type: weeklyLabel))
        }
        return points
    }

    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(store.t("暂无足够的数据记录", "No enough data recorded yet"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 132)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                RoundedRectangle(cornerRadius: OS27.Radius.button, style: .continuous)
                    .stroke(OS27.Stroke.hairline, lineWidth: 0.5)
            }
        )
    }
}
