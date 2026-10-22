import Testing
@testable import CropCastCore

@Suite("LatestWinsCoalescer")
struct LatestWinsCoalescerTests {
    @Test func submitBeforeBeginIsIgnored() {
        var c = LatestWinsCoalescer<Int>()
        #expect(c.submit(1) == nil)
        // Nothing was queued either: the first operation completes with no follow-up.
        c.begin()
        #expect(c.complete() == nil)
    }

    @Test func beginCountsAsTheOperationInFlight() {
        var c = LatestWinsCoalescer<Int>()
        c.begin()
        #expect(c.submit(1) == nil)  // queued behind the start
        #expect(c.complete() == 1)   // sent once the start returns
    }

    @Test func submitWhenIdleIsSentImmediately() {
        var c = LatestWinsCoalescer<Int>()
        c.begin()
        #expect(c.complete() == nil)
        #expect(c.submit(7) == 7)
    }

    @Test func atMostOneInFlightAndLatestWins() {
        var c = LatestWinsCoalescer<Int>()
        c.begin()
        _ = c.complete()
        #expect(c.submit(1) == 1)
        #expect(c.submit(2) == nil)
        #expect(c.submit(3) == nil)
        #expect(c.submit(4) == nil)
        #expect(c.complete() == 4)  // 2 and 3 were superseded
        #expect(c.complete() == nil)
    }

    @Test func completedValueIsInFlightAgain() {
        var c = LatestWinsCoalescer<Int>()
        c.begin()
        _ = c.complete()
        _ = c.submit(1)
        _ = c.submit(2)
        #expect(c.complete() == 2)
        #expect(c.submit(3) == nil)  // 2 is still in flight
        #expect(c.complete() == 3)
    }

    @Test func resetDropsPendingAndIgnoresLaterSubmits() {
        var c = LatestWinsCoalescer<Int>()
        c.begin()
        _ = c.submit(1)
        c.reset()
        #expect(c.complete() == nil)
        #expect(c.submit(2) == nil)
    }

    @Test func beginAfterResetStartsAFreshSession() {
        var c = LatestWinsCoalescer<Int>()
        c.begin()
        _ = c.submit(1)
        c.reset()
        c.begin()
        #expect(c.complete() == nil)  // the stale 1 is gone
        #expect(c.submit(9) == 9)
    }
}
