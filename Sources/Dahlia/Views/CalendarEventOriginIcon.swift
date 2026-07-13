import SwiftUI

struct CalendarEventOriginIcon: View {
    let event: CalendarEventDisplayInfo

    var body: some View {
        Image(systemName: "calendar.badge.checkmark")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help(tooltipText)
            .accessibilityLabel(L10n.calendarEventOrigin(eventTitle))
    }

    private var tooltipText: String {
        [
            L10n.calendarEventOriginTitle,
            eventTitle,
            dateText,
            event.description.nilIfBlank,
        ]
        .compactMap(\.self)
        .joined(separator: "\n")
    }

    private var eventTitle: String {
        event.title.nilIfBlank ?? L10n.newMeeting
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
