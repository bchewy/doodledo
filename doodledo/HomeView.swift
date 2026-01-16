import SwiftUI
import UIKit

private let girlyAccentLight = Color(red: 0.96, green: 0.35, blue: 0.69)
private let girlyAccentDark = Color(red: 0.98, green: 0.46, blue: 0.78)

private let girlySurfaceColorLight = Color(red: 1.0, green: 0.88, blue: 0.94)
private let girlySurfaceHighlightLight = Color(red: 1.0, green: 0.94, blue: 0.98)
private let girlySurfaceGradientLight = LinearGradient(
    colors: [girlySurfaceHighlightLight, girlySurfaceColorLight],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let girlySurfaceColorDark = Color(red: 0.22, green: 0.1, blue: 0.2)
private let girlySurfaceHighlightDark = Color(red: 0.32, green: 0.15, blue: 0.26)
private let girlySurfaceGradientDark = LinearGradient(
    colors: [girlySurfaceHighlightDark, girlySurfaceColorDark],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let girlyBackgroundGradientLight = LinearGradient(
    colors: [Color(red: 1.0, green: 0.92, blue: 0.97), Color(red: 0.99, green: 0.84, blue: 0.92)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let girlyBackgroundGradientDark = LinearGradient(
    colors: [Color(red: 0.16, green: 0.07, blue: 0.15), Color(red: 0.1, green: 0.04, blue: 0.12)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private func girlyAccentColor(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? girlyAccentDark : girlyAccentLight
}

private func girlySurfaceGradient(for colorScheme: ColorScheme) -> LinearGradient {
    colorScheme == .dark ? girlySurfaceGradientDark : girlySurfaceGradientLight
}

private func girlyBackgroundGradient(for colorScheme: ColorScheme) -> LinearGradient {
    colorScheme == .dark ? girlyBackgroundGradientDark : girlyBackgroundGradientLight
}

private func surfaceFillStyle(girlypopMode: Bool, colorScheme: ColorScheme) -> AnyShapeStyle {
    if girlypopMode {
        return AnyShapeStyle(girlySurfaceGradient(for: colorScheme))
    }
    return AnyShapeStyle(Color(.secondarySystemBackground))
}

struct HomeView: View {
    @EnvironmentObject private var store: DoodleStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var path = NavigationPath()
    @State private var homeMode: HomeMode = .calendar
    @State private var calendarScope: CalendarScope = .month
    @State private var focusDate = Date()
    @State private var dimEmptyDays = false
    @AppStorage("girlypop_mode") private var girlypopMode = false

    private let galleryColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let yearColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                backgroundView

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if shouldShowDailyPrompt {
                            DailyPromptCard(
                                streakCount: currentStreak,
                                girlypopMode: girlypopMode,
                                onStart: startNewEntry
                            )
                        }

                        Picker("View", selection: $homeMode) {
                            ForEach(HomeMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if homeMode == .calendar {
                            calendarSection
                        } else {
                            gallerySection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Doodles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Toggle("Dim empty days", isOn: $dimEmptyDays)
                        Toggle("Girlypop mode", isOn: $girlypopMode)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: startNewEntry) {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { entryID in
                CanvasView(entryID: entryID)
            }
        }
        .tint(girlypopMode ? girlyAccentColor(for: colorScheme) : Color.accentColor)
    }

    private var backgroundView: some View {
        Group {
            if girlypopMode {
                girlyBackgroundGradient(for: colorScheme)
            } else {
                Color(.systemBackground)
            }
        }
        .ignoresSafeArea()
    }

    private var calendarSection: some View {
        let accentColor = girlypopMode ? girlyAccentColor(for: colorScheme) : Color.accentColor
        return VStack(alignment: .leading, spacing: 12) {
            calendarHeader

            Picker("Scope", selection: $calendarScope) {
                ForEach(CalendarScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            if calendarScope != .year {
                WeekdayHeaderRow(symbols: weekdaySymbols)
            }

            if calendarScope == .year {
                LazyVGrid(columns: yearColumns, spacing: 12) {
                    ForEach(monthsInYear(for: focusDate), id: \.self) { monthDate in
                        let monthDays = monthDays(for: monthDate)
                        MonthSummaryCard(
                            monthDate: monthDate,
                            days: monthDays,
                            accentColor: accentColor,
                            girlypopMode: girlypopMode
                        ) {
                            focusDate = monthDate
                            calendarScope = .month
                        }
                    }
                }
            } else {
                LazyVGrid(columns: calendarColumns, spacing: 8) {
                    ForEach(calendarDays) { day in
                        let entry = day.entries.first
                        if let entry {
                            NavigationLink(value: entry.id) {
                                CalendarDayCell(
                                    day: day,
                                    accentColor: accentColor,
                                    dimEmptyDays: dimEmptyDays,
                                    girlypopMode: girlypopMode
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            CalendarDayCell(
                                day: day,
                                accentColor: accentColor,
                                dimEmptyDays: dimEmptyDays,
                                girlypopMode: girlypopMode
                            )
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(surfaceFillStyle(girlypopMode: girlypopMode, colorScheme: colorScheme))
        )
    }

    private var calendarHeader: some View {
        HStack(spacing: 12) {
            Button {
                shiftFocus(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(calendarHeaderTitle)
                .font(.headline)

            Spacer()

            Button {
                shiftFocus(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal, 6)
    }

    private var gallerySection: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No doodles yet",
                    systemImage: "scribble",
                    description: Text("Tap New to start.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: galleryColumns, spacing: 16) {
                    ForEach(store.entries) { entry in
                        NavigationLink(value: entry.id) {
                            EntryCard(entry: entry, girlypopMode: girlypopMode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func startNewEntry() {
        let entry = store.createEntry()
        path.append(entry.id)
    }

    private var shouldShowDailyPrompt: Bool {
        !hasEntryToday
    }

    private var hasEntryToday: Bool {
        let calendar = Calendar.current
        let today = Date()
        return store.entries.contains { calendar.isDate($0.createdAt, inSameDayAs: today) }
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        let daySet = Set(store.entries.map { calendar.startOfDay(for: $0.createdAt) })
        guard !daySet.isEmpty else { return 0 }

        var streak = 0
        var day = calendar.startOfDay(for: Date())
        if !daySet.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }

        while daySet.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        return streak
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var calendarHeaderTitle: String {
        let calendar = Calendar.current
        switch calendarScope {
        case .month:
            return Self.monthFormatter.string(from: focusDate)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: focusDate) else {
                return Self.shortDateFormatter.string(from: focusDate)
            }
            let start = interval.start
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return "\(Self.shortDateFormatter.string(from: start)) - \(Self.shortDateFormatter.string(from: end))"
        case .year:
            return Self.yearFormatter.string(from: focusDate)
        }
    }

    private var calendarDays: [CalendarDay] {
        switch calendarScope {
        case .week:
            return weekDays(for: focusDate)
        case .month:
            return monthDays(for: focusDate)
        case .year:
            return []
        }
    }

    private func shiftFocus(by value: Int) {
        let calendar = Calendar.current
        let component: Calendar.Component
        switch calendarScope {
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .year:
            component = .year
        }

        if let next = calendar.date(byAdding: component, value: value, to: focusDate) {
            focusDate = next
        }
    }

    private var entriesByDay: [Date: [DoodleEntry]] {
        let calendar = Calendar.current
        return Dictionary(grouping: store.entries) { entry in
            calendar.startOfDay(for: entry.createdAt)
        }
    }

    private func entriesForDay(_ date: Date) -> [DoodleEntry] {
        let calendar = Calendar.current
        let dayKey = calendar.startOfDay(for: date)
        return (entriesByDay[dayKey] ?? []).sorted { $0.updatedAt > $1.updatedAt }
    }

    private func weekDays(for date: Date) -> [CalendarDay] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else {
                return nil
            }
            let isCurrentMonth = calendar.isDate(day, equalTo: focusDate, toGranularity: .month)
            return CalendarDay(date: day, isCurrentMonth: isCurrentMonth, entries: entriesForDay(day))
        }
    }

    private func monthDays(for date: Date) -> [CalendarDay] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count else {
            return []
        }

        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [CalendarDay] = []

        if leadingDays > 0 {
            for offset in stride(from: leadingDays, to: 0, by: -1) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: firstOfMonth) else { continue }
                days.append(CalendarDay(date: day, isCurrentMonth: false, entries: entriesForDay(day)))
            }
        }

        for offset in 0..<daysInMonth {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) else { continue }
            days.append(CalendarDay(date: day, isCurrentMonth: true, entries: entriesForDay(day)))
        }

        while days.count % 7 != 0 {
            guard let lastDay = days.last?.date,
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) else { break }
            days.append(CalendarDay(date: nextDay, isCurrentMonth: false, entries: entriesForDay(nextDay)))
        }

        return days
    }

    private func monthsInYear(for date: Date) -> [Date] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private enum HomeMode: String, CaseIterable, Identifiable {
    case calendar = "Calendar"
    case gallery = "Gallery"

    var id: String { rawValue }
}

private enum CalendarScope: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

private struct CalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool
    let entries: [DoodleEntry]

    var id: Date { date }
}

private struct WeekdayHeaderRow: View {
    let symbols: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct CalendarDayCell: View {
    let day: CalendarDay
    let accentColor: Color
    let dimEmptyDays: Bool
    let girlypopMode: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let hasEntry = !day.entries.isEmpty
        let opacity = cellOpacity(hasEntry: hasEntry)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cellBackground(hasEntry: hasEntry))

            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(hasEntry ? 0.85 : 0)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if hasEntry {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 22, height: 22)
                    .offset(x: 6, y: 24)
            }

            Text(dayNumber)
                .font(.caption2)
                .foregroundColor(hasEntry ? .primary : .secondary)
                .padding(6)

            if day.entries.count > 1 {
                Text("+\(day.entries.count - 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            if girlypopMode && hasEntry {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundColor(accentColor)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .opacity(opacity)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isToday ? accentColor : Color.clear, lineWidth: 1)
        )
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: day.date)
    }

    private var thumbnailImage: UIImage? {
        guard let entry = day.entries.first,
              let data = entry.thumbnailData else { return nil }
        return UIImage(data: data)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    private func cellOpacity(hasEntry: Bool) -> Double {
        if !day.isCurrentMonth {
            return 0.25
        }
        if dimEmptyDays && !hasEntry {
            return 0.35
        }
        return 1
    }

    private func cellBackground(hasEntry: Bool) -> AnyShapeStyle {
        if girlypopMode {
            if hasEntry {
                return AnyShapeStyle(girlySurfaceGradient(for: colorScheme))
            }
            let emptyOpacity: Double = colorScheme == .dark ? 0.12 : 0.6
            return AnyShapeStyle(Color.white.opacity(emptyOpacity))
        }
        return AnyShapeStyle(Color(.secondarySystemBackground))
    }
}

private struct MonthSummaryCard: View {
    let monthDate: Date
    let days: [CalendarDay]
    let accentColor: Color
    let girlypopMode: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                Text(monthTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(days) { day in
                        Circle()
                            .fill(dotColor(for: day))
                            .frame(width: 6, height: 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)

                Text("\(doodleCount) doodle day\(doodleCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(surfaceFillStyle(girlypopMode: girlypopMode, colorScheme: colorScheme))
            )
        }
        .buttonStyle(.plain)
    }

    private var doodleCount: Int {
        days.filter { $0.isCurrentMonth && !$0.entries.isEmpty }.count
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: monthDate)
    }

    private func dotColor(for day: CalendarDay) -> Color {
        guard day.isCurrentMonth else { return Color.clear }
        if day.entries.isEmpty {
            return Color.secondary.opacity(0.2)
        }
        return accentColor
    }
}

private struct EntryCard: View {
    let entry: DoodleEntry
    let girlypopMode: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(surfaceFillStyle(girlypopMode: girlypopMode, colorScheme: colorScheme))

                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !trimmedCaption.isEmpty {
                Text(trimmedCaption)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            Text(Self.dateFormatter.string(from: entry.updatedAt))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var thumbnailImage: UIImage? {
        guard let data = entry.thumbnailData else { return nil }
        return UIImage(data: data)
    }

    private var trimmedCaption: String {
        entry.caption.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct DailyPromptCard: View {
    let streakCount: Int
    let girlypopMode: Bool
    let onStart: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily doodle")
                .font(.headline)

            Text(promptText)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if streakCount > 0 {
                Text("Streak: \(streakCount) day\(streakCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onStart) {
                Label("Start today", systemImage: "pencil")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surfaceFillStyle(girlypopMode: girlypopMode, colorScheme: colorScheme))
        )
    }

    private var promptText: String {
        if streakCount > 0 {
            return "Keep the streak going with a quick sketch."
        }
        return "Make a quick sketch today and start a streak."
    }
}
