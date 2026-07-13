import SwiftUI

struct CalendarEventOriginIcon: View {
    let event: CalendarEventDisplayInfo

    var body: some View {
        Image(systemName: "calendar.badge.checkmark")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help(tooltipText)
            .accessibilityLabel(L10n.calendarEventOrigin(event.resolvedTitle))
            .accessibilityValue(detailLines.joined(separator: ", "))
    }

    private var tooltipText: String {
        ([
            L10n.calendarEventOriginTitle,
            event.resolvedTitle,
        ] + detailLines)
            .joined(separator: "\n")
    }

    private var detailLines: [String] {
        [dateText, event.description.nilIfBlank]
            .compactMap(\.self)
    }

    private var dateText: String {
        if event.isAllDay {
            return allDayDateText
        }

        let startDate = event.startDate.formatted(date: .abbreviated, time: .shortened)
        let endDate = if Calendar.autoupdatingCurrent.isDate(event.startDate, inSameDayAs: event.endDate) {
            event.endDate.formatted(date: .omitted, time: .shortened)
        } else {
            event.endDate.formatted(date: .abbreviated, time: .shortened)
        }
        return "\(startDate) – \(endDate)"
    }

    private var allDayDateText: String {
        let startDate = event.startDate.formatted(date: .abbreviated, time: .omitted)
        let inclusiveEndDate = if event.endDate > event.startDate {
            event.endDate.addingTimeInterval(-1)
        } else {
            event.endDate
        }
        if Calendar.autoupdatingCurrent.isDate(event.startDate, inSameDayAs: inclusiveEndDate) {
            return "\(startDate) · \(L10n.calendarAllDay)"
        }
        let endDate = inclusiveEndDate.formatted(date: .abbreviated, time: .omitted)
        return "\(startDate) – \(endDate) · \(L10n.calendarAllDay)"
    }
}
