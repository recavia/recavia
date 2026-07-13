import Foundation

struct CalendarEventDisplayInfo: Equatable {
    let title: String
    let description: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    init(
        title: String,
        description: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool
    ) {
        self.title = title
        self.description = description
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
    }

    init(event: CalendarEvent) {
        self.init(
            title: event.title,
            description: event.description,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay
        )
    }
}
