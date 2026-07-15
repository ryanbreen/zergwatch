import Charts
import SwiftUI

struct DashboardActions {
    let openAccessibilitySettings: () -> Void
    let openInputMonitoringSettings: () -> Void
    let openDataFolder: () -> Void
    let resetToday: () -> Void
    let togglePause: () -> Void
    let showMenu: () -> Void
    let quit: () -> Void
}

struct DashboardView: View {
    @ObservedObject var store: APMStore
    let actions: DashboardActions

    @State private var chartMode: ChartMetricMode = .both

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                permissionStatus
                header
                statGrid
                chartSection
                RecentActivityView(items: store.recentActivity())

                HStack(alignment: .top, spacing: 12) {
                    TopCombosView(rows: store.topCombos())
                    TopAppsView(rows: store.topApps())
                }

                footer
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var permissionStatus: some View {
        if !store.accessibilityTrusted {
            AccessibilityPermissionBanner(openSettings: actions.openAccessibilitySettings)
        } else if !store.inputMonitoringGranted {
            InputMonitoringPermissionBanner(openSettings: actions.openInputMonitoringSettings)
        } else {
            TrackingActiveIndicator()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Zerg Watch")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(store.displayDate)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: actions.showMenu) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Menu")
        }
    }

    private var statGrid: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                StatTile(title: "Actions", value: store.totalActions, tint: .orange)
                StatTile(title: "Hotkeys", value: store.totalHotkeys, tint: .cyan)
                StatTile(title: "Live APM", value: store.liveAPM, tint: .green)
                StatTile(title: "Peak", value: store.day.peak60APM, tint: .pink)
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Per-Hour Pace")
                    .font(.headline)
                Spacer()
                Picker("Metric", selection: $chartMode) {
                    ForEach(ChartMetricMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .frame(minWidth: 230)
            }

            HourlyChart(
                points: store.chartPoints(mode: chartMode),
                currentHour: store.currentHour
            )
            .frame(height: 180)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.yellow)
            Text(store.playstyleFlavor)
                .font(.callout.weight(.medium))
            Spacer()
            if store.isPaused {
                Text("Paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}

private struct AccessibilityPermissionBanner: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text("Accessibility permission needed - Zerg Watch can't count keystrokes until you enable it")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open Accessibility Settings", action: openSettings)
        }
        .padding(12)
        .background(Color.orange.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InputMonitoringPermissionBanner: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "keyboard.badge.eye")
                .foregroundStyle(.white)
            Text("Input Monitoring needed — Zerg Watch can't see keyboard shortcuts until you enable it")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open Input Monitoring", action: openSettings)
        }
        .padding(12)
        .background(Color.red.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TrackingActiveIndicator: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            Text("Tracking active")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

private struct StatTile: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.formatted(.number))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HourlyChart: View {
    let points: [HourChartPoint]
    let currentHour: Int

    var body: some View {
        Chart {
            RuleMark(x: .value("Current hour", currentHour))
                .foregroundStyle(Color.yellow.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .annotation(position: .top, alignment: .center) {
                    Text("now")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }

            ForEach(points) { point in
                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Count", point.value)
                )
                .position(by: .value("Metric", point.metric))
                .foregroundStyle(by: .value("Metric", point.metric))
                .opacity(point.hour == currentHour ? 1.0 : 0.64)
                .cornerRadius(3)
            }
        }
        .chartForegroundStyleScale([
            "Actions": Color.orange,
            "Hotkeys": Color.cyan
        ])
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0, 4, 8, 12, 16, 20, 23]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text("\(hour)")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
}

private struct RecentActivityView: View {
    let items: [RecentActivity]

    private var visibleItems: [RecentActivity] {
        Array(items.prefix(20))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(.headline)
            if visibleItems.isEmpty {
                EmptyState(text: "No activity yet")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(visibleItems) { item in
                            RecentActivityRow(item: item)
                        }
                    }
                }
                .frame(height: 168)
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RecentActivityRow: View {
    let item: RecentActivity

    var body: some View {
        HStack {
            Text(item.label)
                .font(.system(.callout, design: .rounded).weight(item.kind == .chord ? .medium : .regular))
                .foregroundStyle(item.kind == .chord ? Color.cyan : Color.secondary)
                .lineLimit(1)
            Spacer()
            Text(RecentActivityRow.relativeTime(for: item.at))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(height: 22)
        .padding(.vertical, 2)
    }

    private static func relativeTime(for date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        switch seconds {
        case 0:
            return "now"
        case 1..<60:
            return "\(seconds)s"
        case 60..<3600:
            return "\(seconds / 60)m"
        default:
            return "\(seconds / 3600)h"
        }
    }
}

private struct TopCombosView: View {
    let rows: [ComboDisplay]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Combos")
                .font(.headline)
            if rows.isEmpty {
                EmptyState(text: "No hotkeys yet")
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.label)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer()
                            Text("×\(row.count.formatted(.number))")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(12)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TopAppsView: View {
    let rows: [AppDisplay]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Apps")
                .font(.headline)
            if rows.isEmpty {
                EmptyState(text: "No actions yet")
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Text(row.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text(row.actions.formatted(.number))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(12)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
    }
}
