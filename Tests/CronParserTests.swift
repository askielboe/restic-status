import Testing

@testable import ResticStatus

@Suite("CronParser")
struct CronParserTests {
    @Test("parses basic expressions")
    func parseBasic() {
        let schedule = CronParser.parse("0 * * * *")
        #expect(schedule != nil)
        #expect(schedule?.minute == .value(0))
        #expect(schedule?.hour == .any)
        #expect(schedule?.day == .any)
        #expect(schedule?.month == .any)
        #expect(schedule?.weekday == .any)
    }

    @Test("parses all-values expression")
    func parseAllValues() {
        let schedule = CronParser.parse("30 2 15 6 3")
        #expect(schedule != nil)
        #expect(schedule?.minute == .value(30))
        #expect(schedule?.hour == .value(2))
        #expect(schedule?.day == .value(15))
        #expect(schedule?.month == .value(6))
        #expect(schedule?.weekday == .value(3))
    }

    @Test("parses step expression")
    func parseStep() {
        let schedule = CronParser.parse("*/15 * * * *")
        #expect(schedule != nil)
        #expect(schedule?.minute == .step(15))
    }

    @Test("parses list expression")
    func parseList() {
        let schedule = CronParser.parse("0,30 * * * *")
        #expect(schedule != nil)
        #expect(schedule?.minute == .list([0, 30]))
    }

    @Test("rejects invalid expressions")
    func rejectInvalid() {
        #expect(CronParser.parse("") == nil)
        #expect(CronParser.parse("* *") == nil)
        #expect(CronParser.parse("60 * * * *") == nil)
        #expect(CronParser.parse("* 25 * * *") == nil)
        #expect(CronParser.parse("* * 32 * *") == nil)
        #expect(CronParser.parse("* * * 13 *") == nil)
        #expect(CronParser.parse("abc * * * *") == nil)
    }

    @Test("validates schedule")
    func validity() {
        #expect(CronParser.parse("0 0 * * 0")?.isValid == true)
        #expect(CronParser.parse("*/5 * * * *")?.isValid == true)
    }

    @Test("generates launchd intervals for simple schedule")
    func launchdSimple() {
        let schedule = CronParser.parse("30 2 * * *")!
        let intervals = CronParser.toLaunchdIntervals(schedule)
        #expect(intervals.count == 1)
        #expect(intervals[0]["Minute"] == 30)
        #expect(intervals[0]["Hour"] == 2)
    }

    @Test("generates launchd intervals for step schedule")
    func launchdStep() {
        let schedule = CronParser.parse("*/15 * * * *")!
        let intervals = CronParser.toLaunchdIntervals(schedule)
        #expect(intervals.count == 4)
        let minutes = intervals.compactMap { $0["Minute"] }.sorted()
        #expect(minutes == [0, 15, 30, 45])
    }
}
