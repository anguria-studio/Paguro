import Testing
@testable import PaguroCore

struct NotificationIslandClearAllTimingTests {
    @Test
    func staggerStartsAtTheVisiblePartOfAScrolledHistory() {
        let first = NotificationIslandClearAllTiming.firstVisibleIndex(scrollOffset: 760, eventCount: 100)
        #expect(first == 10)
        #expect(NotificationIslandClearAllTiming.delay(for: 10 - first, eventCount: 100, reduceMotion: false) == 0)
        #expect(NotificationIslandClearAllTiming.delay(for: 11 - first, eventCount: 100, reduceMotion: false) == 0.045)
        #expect(NotificationIslandClearAllTiming.firstVisibleIndex(scrollOffset: -.infinity, eventCount: 100) == 0)
        #expect(NotificationIslandClearAllTiming.firstVisibleIndex(scrollOffset: .greatestFiniteMagnitude, eventCount: 100) == 99)
    }

    @Test
    func cardsLeaveInOrderAndFinishBeforeCollapse() {
        for count in [1, 3, 6, 100] {
            var previousDelay = 0.0
            for index in 0..<count {
                let delay = NotificationIslandClearAllTiming.delay(
                    for: index, eventCount: count, reduceMotion: false
                )
                #expect(delay >= previousDelay)
                #expect(.seconds(delay + NotificationIslandClearAllTiming.cardDuration(reduceMotion: false))
                    <= NotificationIslandClearAllTiming.completionDelay(eventCount: count, reduceMotion: false))
                previousDelay = delay
            }
        }
    }

    @Test
    func longHistoryDoesNotExtendTheAnimation() {
        #expect(NotificationIslandClearAllTiming.completionDelay(eventCount: 100_000, reduceMotion: false)
            == .milliseconds(400))
        #expect(NotificationIslandClearAllTiming.completionDelay(eventCount: 0, reduceMotion: false) == .zero)
    }

    @Test
    func reduceMotionFadesEveryCardTogether() {
        #expect(NotificationIslandClearAllTiming.delay(for: 5, eventCount: 20, reduceMotion: true) == 0)
        #expect(NotificationIslandClearAllTiming.completionDelay(eventCount: 20, reduceMotion: true)
            == .milliseconds(160))
    }
}
