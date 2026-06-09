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

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(ChartTab.allCases) { tab in
                    Button {
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.75)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tabTitle(tab))
                            .font(.caption.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                Group {
                                    if selectedTab == tab {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.primary.opacity(0.16))
                                            .shadow(color: Color.black.opacity(0.10), radius: 1.5, x: 0, y: 1)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                            )
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            
            if selectedTab == .day24 {
                let points = remainingPercentPoints
                if points.isEmpty {
                    emptyStateView
                } else {
                    Chart(points) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Percent", point.value)
                        )
                        .foregroundStyle(by: .value("Type", point.type))
                        .interpolationMethod(.monotone)
                        
                        AreaMark(
                            x: .value("Time", point.time),
                            y: .value("Percent", point.value)
                        )
                        .foregroundStyle(by: .value("Type", point.type))
                        .opacity(0.08)
                        .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: 0...100)
                    .chartForegroundStyleScale([
                        store.t("5小时额度", "5h Quota"): Color.quotaNormal,
                        store.t("周额度", "Weekly Quota"): Color.blue
                    ])
                    .frame(height: 120)
                }
            } else {
                let limit = selectedTab == .day7 ? 7 : 30
                let points = consumptionPoints(limit: limit)
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
                    }
                    .chartForegroundStyleScale([
                        store.t("5小时额度", "5h Quota"): Color.quotaNormal,
                        store.t("周额度", "Weekly Quota"): Color.blue
                    ])
                    .frame(height: 120)
                }
            }
        }
    }

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
                points.append(RemainingPercentPoint(time: record.capturedAt, value: Double(fiveHour), type: store.t("5小时额度", "5h Quota")))
            }
            if let weekly = record.weeklyPercentRemaining {
                points.append(RemainingPercentPoint(time: record.capturedAt, value: Double(weekly), type: store.t("周额度", "Weekly Quota")))
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
            
            points.append(ConsumptionBarPoint(dayKey: shortKey, value: d.fiveHourConsumed, type: store.t("5小时额度", "5h Quota")))
            points.append(ConsumptionBarPoint(dayKey: shortKey, value: d.weeklyConsumed, type: store.t("周额度", "Weekly Quota")))
        }
        return points
    }

    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 24))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(store.t("暂无足够的数据记录", "No enough data recorded yet"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }
}
