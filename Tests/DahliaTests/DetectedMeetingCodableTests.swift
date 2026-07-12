import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct DetectedMeetingCodableTests {
        @Test
        func preservesCalendarDetailsUsedByNotificationActions() throws {
            let startDate = Date(timeIntervalSince1970: 1_700_000_000)
            let event = CalendarEvent(
                id: "event-id",
                calendarID: "calendar-id",
                calendarName: "Work",
                calendarColorHex: "3366FF",
                platform: CalendarEventPlatform.macOSCalendar,
                platformId: "platform-id",
                title: "Planning",
                description: "Quarterly planning",
                icalUid: "uid",
                startDate: startDate,
                endDate: startDate.addingTimeInterval(3600),
                isAllDay: false,
                meetingURL: URL(string: "https://meet.example.com/planning")
            )
            let meeting = DetectedMeeting(
                title: event.title,
                appName: "Calendar",
                bundleIdentifier: event.platform,
                calendarEvent: event
            )

            let data = try JSONEncoder().encode(meeting)
            let decoded = try JSONDecoder().decode(DetectedMeeting.self, from: data)

            #expect(decoded.id == meeting.id)
            #expect(decoded.title == meeting.title)
            #expect(decoded.calendarEvent == event)
        }
    }
#endif
