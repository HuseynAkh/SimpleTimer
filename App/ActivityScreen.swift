import SwiftUI
import Charts

struct ActivityScreen: View {
    @EnvironmentObject private var store: TimerStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                StatisticsView(records: store.state.records(at: context.date), now: context.date)
            }
            .background { AppBackground() }
            .navigationTitle("Activity").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(scheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ExportScreen() } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Export activity")
                }
            }
        }
    }
}

private struct StatisticsView: View {
    let records: [SessionRecord]
    let now: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .largeTitle) private var totalSize = 38.0
    @State private var period: ReportPeriod = .week
    @State private var anchor = Date()
    @State private var selectedDate: Date?
    @State private var kind: SessionKind?
    private var calendar: Calendar { .current }
    private var interval: DateInterval { period.interval(containing: anchor) }
    private var filtered: [SessionRecord] { records.filter { kind == nil || $0.preset.kind == kind } }
    private var report: SessionStatistics { SessionStatistics(records: filtered, interval: interval) }
    private var buckets: [TimeBucket] { report.buckets(unit: period == .day ? .hour : .day) }
    private var selectedBucket: TimeBucket? { guard let selectedDate else { return nil }; return buckets.first { selectedDate >= $0.start && selectedDate < $0.end } }
    private var shownInterval: DateInterval { selectedBucket.map { DateInterval(start: $0.start, end: $0.end) } ?? interval }
    private var shown: SessionStatistics { SessionStatistics(records: filtered, interval: shownInterval) }
    private var kinds: [Preset] { uniquePresets(records) }
    private var previous: SessionStatistics {
        let priorAnchor = calendar.date(byAdding: period.component, value: -1, to: anchor)!
        let prior = period.interval(containing: priorAnchor)
        let comparisonEnd = interval.contains(now) ? min(prior.end, calendar.date(byAdding: period.component, value: -1, to: now)!) : prior.end
        return SessionStatistics(records: filtered, interval: DateInterval(start: prior.start, end: max(prior.start, comparisonEnd)))
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                rangeNavigation
                summaryCard
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    metric("Sessions", value: "\(shown.sessions.count)")
                    metric("Completion rate", value: shown.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")

                }
                if !shown.sessions.isEmpty {
                    DisclosureGroup("Session breakdown") {
                        VStack(spacing: 16) {
                            LabeledContent("Average", value: activityDuration(shown.averageSession))
                            LabeledContent("Longest", value: activityDuration(shown.longest))
                            breakdown
                        }.padding(.top, 12)
                    }.activityCard()
                }
                NavigationLink {
                    HistoryView(records: shown.sessions).navigationTitle("Sessions").background { AppBackground() }
                } label: {
                    HStack { Label("View sessions", systemImage: "clock.arrow.circlepath"); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                        .font(.subheadline).padding(18).contentShape(Rectangle())
                }.buttonStyle(.plain).modifier(ContentSurface())
                recentSessions
                if records.isEmpty {
                    Text("Your sessions will appear here as you use the timer.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.vertical, 12)
                } else {
                    Text("\(SessionStatistics.streak(records: records, now: now)) day focus streak · Pauses excluded")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
                }
            }.padding(.horizontal, 20).padding(.bottom, 28)
        }
    }
    @ViewBuilder private var rangeNavigation: some View {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Previous \(period.rawValue.lowercased())")
                    Spacer(minLength: 0)
                    Menu {
                        periodPicker
                        Button("Return to today") { anchor = now; selectedDate = nil }
                    } label: {
                        HStack { Text(periodLabel); Image(systemName: "chevron.down").font(.caption) }
                            .font(.subheadline.weight(.medium)).foregroundStyle(.primary).frame(minHeight: 44)
                    }.accessibilityLabel("Time range, \(period.rawValue), \(periodLabel)")
                        .onChange(of: period) { _, _ in selectedDate = nil }
                    Spacer(minLength: 0)
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .disabled(interval.end > now).accessibilityLabel("Next \(period.rawValue.lowercased())")
                }.buttonStyle(.plain)
    }
    @ViewBuilder private var summaryCard: some View {
                VStack(alignment: .leading, spacing: 16) {
                    let headerLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
                    headerLayout {
                        Text(selectedBucket == nil ? "Tracked time" : bucketLabel).font(.subheadline).foregroundStyle(.secondary)
                        if !typeSize.isAccessibilitySize { Spacer() }
                        Menu {
                            Button("All sessions") { kind = nil; selectedDate = nil }
                            ForEach(kinds, id: \.kind) { preset in Button(preset.name) { kind = preset.kind; selectedDate = nil } }
                        } label: {
                            HStack(spacing: 4) { Text(kind.flatMap { selected in kinds.first { $0.kind == selected }?.name } ?? "All sessions"); Image(systemName: "chevron.down").font(.caption2) }
                                .font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
                        }
                    }
                    Text(activityDuration(shown.total)).font(.system(size: totalSize, weight: .medium)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    if selectedBucket == nil {
                        Text(comparisonLabel).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Button("Show full period") { selectedDate = nil }.font(.subheadline).frame(minHeight: 44)
                    }
                    if !typeSize.isAccessibilitySize { chart }
                    let totalsLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
                    totalsLayout {
                        Label("Focus \(activityDuration(shown.focus))", systemImage: "circle.fill").foregroundStyle(.primary)
                        Label("Break \(activityDuration(shown.rest))", systemImage: "circle").foregroundStyle(.secondary)
                    }.font(.subheadline)
                    chartData
                }.activityCard()
    }
    @ViewBuilder private var recentSessions: some View {
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Recent sessions").font(.headline)
                            Spacer()
                            NavigationLink("All history") { HistoryView(records: records).navigationTitle("History").background { AppBackground() } }
                        }.padding(.horizontal, 16).padding(.top, 16)
                        ForEach(Array(records.sorted { $0.startedAt > $1.startedAt }.prefix(3))) { record in
                            NavigationLink { SessionDetail(record: record) } label: { HistoryRow(record: record) }.buttonStyle(.plain)
                        }
                    }.modifier(ContentSurface())
                }
    }
    private var chart: some View {
        Chart {
            ForEach(buckets) { bucket in
                ForEach(kinds, id: \.kind) { preset in
                    let seconds = filtered.filter { $0.preset.kind == preset.kind }.reduce(0) { $0 + $1.duration(in: DateInterval(start: bucket.start, end: bucket.end)) }
                    BarMark(x: .value("Date", bucket.start, unit: period == .day ? .hour : .day), y: .value("Minutes", seconds / 60))
                        .foregroundStyle(Palette.chartColor(preset.color)).cornerRadius(3)
                        .opacity(selectedBucket == nil || selectedBucket?.id == bucket.id ? 1 : 0.65)
                        .accessibilityLabel("\(bucket.start.formatted(date: .abbreviated, time: period == .day ? .shortened : .omitted)), \(preset.name)")
                        .accessibilityValue(activityDuration(seconds))
                }
            }
            if let selectedBucket {
                RuleMark(x: .value("Selected", selectedBucket.start, unit: period == .day ? .hour : .day))
                    .foregroundStyle(Color.primary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...max(1, (buckets.map(\.total).max() ?? 0) / 60 * 1.15))
        .chartXAxis {
            AxisMarks(values: .stride(by: period == .day ? .hour : .day, count: period == .day ? 6 : period == .month ? 7 : 1)) { _ in
                AxisValueLabel(format: period == .day ? .dateTime.hour(.defaultDigits(amPM: .abbreviated)) : period == .week ? .dateTime.weekday(.narrow) : .dateTime.day())
            }
        }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Color(UIColor.separator))
            AxisValueLabel { if let minutes = value.as(Double.self) { Text(activityDuration(minutes * 60)).font(.caption2) } }
        } }
        .chartXSelection(value: $selectedDate)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle()).onTapGesture { location in
                    if let plot = proxy.plotFrame {
                        let frame = geometry[plot]
                        guard frame.contains(location) else { return }
                        selectedDate = proxy.value(atX: location.x - frame.minX, as: Date.self)
                    }
                }
            }
        }.frame(height: 175)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tracked time chart")
        .accessibilityValue(activityDuration(report.total))
        .accessibilityHint("Open Chart data below to explore each time period")
    }
    private var periodPicker: some View {
        Picker("Time range", selection: $period) { ForEach(ReportPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
    }
    private var chartData: some View {
        DisclosureGroup("Chart data") {
            VStack(spacing: 0) {
                ForEach(buckets) { bucket in
                    Button { selectedDate = bucket.start } label: {
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
                        layout {
                            Text(bucket.start.formatted(date: period == .day ? .omitted : .abbreviated, time: period == .day ? .shortened : .omitted))
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Text(activityDuration(bucket.total)).monospacedDigit()
                            if selectedBucket?.id == bucket.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityElement(children: .combine)
                        .accessibilityAddTraits(selectedBucket?.id == bucket.id ? .isSelected : [])
                    Divider()
                }
            }.padding(.top, 8)
        }.font(.subheadline).padding(.top, 4)
    }
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("By session").font(.headline)
            ForEach(kinds.sorted { duration(for: $0) > duration(for: $1) }, id: \.kind) { preset in
                let seconds = duration(for: preset)
                if seconds > 0 {
                    VStack(spacing: 8) {
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
                        layout {
                            Image(systemName: preset.kind.symbol).foregroundStyle(Palette.chartColor(preset.color)).accessibilityHidden(true)
                            Text(preset.name).fixedSize(horizontal: false, vertical: true)
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Text(activityDuration(seconds)).monospacedDigit().foregroundStyle(.secondary)
                        }.font(.subheadline)
                        ProgressView(value: seconds, total: max(1, shown.total)).tint(Palette.chartColor(preset.color))
                    }.accessibilityElement(children: .combine)
                }
            }
        }.activityCard()
    }
    private func duration(for preset: Preset) -> Double { shown.sessions.filter { $0.preset.kind == preset.kind }.reduce(0) { $0 + $1.duration(in: shownInterval) } }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.subheadline).foregroundStyle(.secondary); Text(value).font(.title2.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true) }
            .frame(maxWidth: .infinity, alignment: .leading).activityCard().accessibilityElement(children: .combine)
    }
    private func move(_ offset: Int) { anchor = calendar.date(byAdding: period.component, value: offset, to: anchor)!; selectedDate = nil }
    private var periodLabel: String {
        if period == .day { return calendar.isDateInToday(anchor) ? "Today" : anchor.formatted(.dateTime.month(.abbreviated).day().year()) }
        if period == .month { return anchor.formatted(.dateTime.month(.wide).year()) }
        return interval.start.formatted(.dateTime.month(.abbreviated).day()) + " – " + interval.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day())
    }
    private var bucketLabel: String { selectedBucket?.start.formatted(date: .abbreviated, time: period == .day ? .shortened : .omitted) ?? "Tracked time" }
    private var comparisonLabel: String {
        guard previous.total > 0 else { return "No earlier \(period.rawValue.lowercased()) to compare" }
        let difference = Int(((report.total - previous.total) / previous.total * 100).rounded())
        return "\(difference > 0 ? "+" : "")\(difference)% vs \(interval.contains(now) ? "same point last" : "previous") \(period.rawValue.lowercased())"
    }
}

private struct HistoryView: View {
    let records: [SessionRecord]
    @State private var search = ""
    @State private var outcome = "All"
    private var filtered: [SessionRecord] {
        records.filter { record in
            (search.isEmpty || record.preset.name.localizedCaseInsensitiveContains(search)) &&
            (outcome == "All" || (outcome == "Completed" ? record.outcome == .completed : record.outcome != .completed && record.isFinished))
        }.sorted { $0.startedAt > $1.startedAt }
    }
    private var days: [Date] { Array(Set(filtered.map { Calendar.current.startOfDay(for: $0.startedAt) })).sorted(by: >) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search sessions", text: $search).autocorrectionDisabled()
                    Menu { Picker("Status", selection: $outcome) { ForEach(["All", "Completed", "Ended early"], id: \.self) { Text($0) } } }
                        label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Filter history, \(outcome)")
                }.padding(.leading, 16).padding(.trailing, 6).modifier(ContentSurface())
                if outcome != "All" { Text(outcome).font(.caption).foregroundStyle(.secondary) }
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty && outcome == "All" ? "No sessions yet" : "No matching sessions", systemImage: "clock.arrow.circlepath", description: Text(search.isEmpty && outcome == "All" ? "Finish a timer to begin your history." : "Try another name or clear the filter."))
                }
                ForEach(days, id: \.self) { day in
                    Text(day.formatted(date: .complete, time: .omitted)).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(filtered.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: day) }) { record in
                            NavigationLink { SessionDetail(record: record) } label: { HistoryRow(record: record) }.buttonStyle(.plain)
                        }
                    }.modifier(ContentSurface())
                }
            }.padding(.horizontal, 20).padding(.bottom, 28)
        }
    }
}
private struct HistoryRow: View {
    let record: SessionRecord
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            RoundedRectangle(cornerRadius: 2).fill(Palette.chartColor(record.preset.color)).frame(width: 4, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.preset.name).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Text("\(record.startedAt.formatted(date: .omitted, time: .shortened)) · \(record.outcome.label)").font(.caption).foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(activityDuration(record.elapsed)).font(.subheadline).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
        }.padding(16).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}
private struct SessionDetail: View {
    let record: SessionRecord
    @ScaledMetric(relativeTo: .largeTitle) private var detailSize = 44.0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.preset.name).font(.title2.weight(.medium))
                    Text(activityDuration(record.elapsed)).font(.system(size: detailSize, weight: .medium)).monospacedDigit()
                    Text(record.outcome.label).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).activityCard()
                VStack(spacing: 18) {
                    LabeledContent("Started", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent(record.isFinished ? "Finished" : "Last updated", value: record.finishedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Planned", value: activityDuration(record.planned))
                    LabeledContent("Active time", value: TimerState.clock(record.elapsed))
                    LabeledContent("Pauses", value: "\(record.pauses)")
                    LabeledContent("Paused time", value: activityDuration(max(0, record.finishedAt.timeIntervalSince(record.startedAt) - record.elapsed)))
                }.font(.subheadline).activityCard()
            }.padding(20)
        }.background { AppBackground() }.navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
    }
}
private extension View {
    func activityCard() -> some View { padding(18).modifier(ContentSurface()) }
}
private extension SessionOutcome {
    var label: String { switch self { case .completed: "Completed"; case .ended: "Ended early"; case .reset: "Reset"; case .switched: "Switched"; case .running: "Running"; case .paused: "Paused" } }
}
private func uniquePresets(_ records: [SessionRecord]) -> [Preset] {
    var seen = Set<SessionKind>()
    return records.sorted { $0.startedAt > $1.startedAt }.compactMap { seen.insert($0.preset.kind).inserted ? $0.preset : nil }
}
func activityDuration(_ seconds: TimeInterval) -> String {
    guard seconds >= 60 else { return seconds > 0 ? "<1 min" : "0 min" }
    let minutes = Int(seconds / 60)
    return minutes >= 60 ? "\(minutes / 60)h" + (minutes % 60 > 0 ? " \(minutes % 60)m" : "") : "\(minutes)m"
}
