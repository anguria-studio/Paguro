import Testing
@testable import PaguroCore

struct QuietHoursPolicyTests {
    @Test
    func sameDayWindowIncludesStartAndExcludesEnd() {
        let start = 9 * 60
        let end = 17 * 60

        #expect(QuietHoursPolicy.contains(
            nowMinutes: start, start: start, end: end))
        #expect(QuietHoursPolicy.contains(
            nowMinutes: 10 * 60, start: start, end: end))
        #expect(QuietHoursPolicy.contains(
            nowMinutes: end - 1, start: start, end: end))
        #expect(QuietHoursPolicy.contains(
            nowMinutes: 8 * 60, start: start, end: end) == false)
        #expect(QuietHoursPolicy.contains(
            nowMinutes: end, start: start, end: end) == false)
    }

    @Test
    func windowCanWrapAcrossMidnight() {
        let start = 22 * 60
        let end = 7 * 60

        #expect(QuietHoursPolicy.contains(
            nowMinutes: 23 * 60, start: start, end: end))
        #expect(QuietHoursPolicy.contains(
            nowMinutes: 5 * 60, start: start, end: end))
        #expect(QuietHoursPolicy.contains(
            nowMinutes: end - 1, start: start, end: end))
        #expect(QuietHoursPolicy.contains(
            nowMinutes: end, start: start, end: end) == false)
        #expect(QuietHoursPolicy.contains(
            nowMinutes: 20 * 60, start: start, end: end) == false)
    }

    @Test
    func emptyAndInvalidWindowsFailClosed() {
        #expect(QuietHoursPolicy.contains(
            nowMinutes: 12 * 60, start: 9 * 60, end: 9 * 60) == false)
        #expect(QuietHoursPolicy.contains(
            nowMinutes: -1, start: 9 * 60, end: 17 * 60) == false)
        #expect(QuietHoursPolicy.contains(
            nowMinutes: 12 * 60, start: -1, end: 17 * 60) == false)
        #expect(QuietHoursPolicy.contains(
            nowMinutes: 12 * 60, start: 9 * 60, end: 24 * 60) == false)
    }
}
