import Testing

import VirtualDisplayDemoSupport

struct DemoOptionsTests {
    @Test func defaultsToOneCycleOfTenSeconds() {
        #expect(DemoOptions.parse([]) == DemoOptions(seconds: 10, cycles: 1))
    }

    @Test func parsesSecondsAndCyclesInEitherOrder() {
        #expect(DemoOptions.parse(["--seconds", "3", "--cycles", "5"]) == DemoOptions(seconds: 3, cycles: 5))
        #expect(DemoOptions.parse(["--cycles", "5", "--seconds", "3"]) == DemoOptions(seconds: 3, cycles: 5))
    }

    @Test func parsesCyclesAlone() {
        #expect(DemoOptions.parse(["--cycles", "2"]) == DemoOptions(seconds: 10, cycles: 2))
    }

    @Test(arguments: [
        ["--seconds"], ["--seconds", "0"], ["--seconds", "-1"], ["--seconds", "x"],
        ["--cycles"], ["--cycles", "0"], ["--cycles", "1.5"],
        ["--bogus", "1"], ["--seconds", "1", "--seconds", "2"], ["5"],
    ])
    func rejectsInvalidArguments(args: [String]) {
        #expect(DemoOptions.parse(args) == nil)
    }
}

struct CycleResultTests {
    @Test func passesOnlyForBaselinePlusOneThenBaseline() {
        #expect(CycleResult(before: 2, during: 3, after: 2).isOK)
    }

    @Test(arguments: [
        CycleResult(before: 2, during: 2, after: 2),  // display never appeared
        CycleResult(before: 2, during: 3, after: 3),  // display never went away
        CycleResult(before: 2, during: 4, after: 2),  // extra display
        CycleResult(before: 2, during: 3, after: 1),  // too many removed
    ])
    func failsOtherwise(result: CycleResult) {
        #expect(!result.isOK)
    }
}
