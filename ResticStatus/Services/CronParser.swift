import Foundation

struct CronSchedule {
    let minute: CronField
    let hour: CronField
    let day: CronField
    let month: CronField
    let weekday: CronField

    var isValid: Bool {
        minute.isValid(range: 0 ... 59) &&
            hour.isValid(range: 0 ... 23) &&
            day.isValid(range: 1 ... 31) &&
            month.isValid(range: 1 ... 12) &&
            weekday.isValid(range: 0 ... 7)
    }
}

enum CronField: Equatable {
    case any
    case value(Int)
    case step(Int)
    case list([Int])

    func isValid(range: ClosedRange<Int>) -> Bool {
        switch self {
        case .any:
            return true
        case let .value(v):
            return range.contains(v)
        case let .step(s):
            return s > 0 && s <= range.upperBound
        case let .list(values):
            return values.allSatisfy { range.contains($0) }
        }
    }

    func toLaunchdValue() -> Any? {
        switch self {
        case .any:
            return nil
        case let .value(v):
            return v
        case .step, .list:
            return nil
        }
    }
}

enum CronParser {
    static func parse(_ expression: String) -> CronSchedule? {
        let parts = expression.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count == 5 else { return nil }

        guard let minute = parseField(String(parts[0])),
              let hour = parseField(String(parts[1])),
              let day = parseField(String(parts[2])),
              let month = parseField(String(parts[3])),
              let weekday = parseField(String(parts[4]))
        else {
            return nil
        }

        let schedule = CronSchedule(
            minute: minute,
            hour: hour,
            day: day,
            month: month,
            weekday: weekday
        )

        return schedule.isValid ? schedule : nil
    }

    private static func parseField(_ field: String) -> CronField? {
        if field == "*" {
            return .any
        }

        if field.hasPrefix("*/") {
            let stepStr = String(field.dropFirst(2))
            guard let step = Int(stepStr), step > 0 else { return nil }
            return .step(step)
        }

        if field.contains(",") {
            let values = field.split(separator: ",").compactMap { Int($0) }
            guard values.count == field.split(separator: ",").count else { return nil }
            return .list(values)
        }

        if let value = Int(field) {
            return .value(value)
        }

        return nil
    }

    static func toLaunchdIntervals(_ schedule: CronSchedule) -> [[String: Int]] {
        if case let .step(minuteStep) = schedule.minute {
            return generateIntervals(schedule, values: Array(stride(from: 0, to: 60, by: minuteStep)), key: "Minute")
        } else if case let .step(hourStep) = schedule.hour {
            return generateIntervals(schedule, values: Array(stride(from: 0, to: 24, by: hourStep)), key: "Hour")
        } else if case let .list(minutes) = schedule.minute {
            return generateIntervals(schedule, values: minutes, key: "Minute")
        } else if case let .list(hours) = schedule.hour {
            return generateIntervals(schedule, values: hours, key: "Hour")
        } else {
            return [buildBaseInterval(schedule)]
        }
    }

    private static func generateIntervals(_ schedule: CronSchedule, values: [Int], key: String) -> [[String: Int]] {
        values.map { v in
            var interval = buildBaseInterval(schedule)
            interval[key] = v
            return interval
        }
    }

    private static func buildBaseInterval(_ schedule: CronSchedule) -> [String: Int] {
        var interval: [String: Int] = [:]
        func addIfValue(_ field: CronField, key: String, transform: ((Int) -> Int)? = nil) {
            if case let .value(v) = field {
                interval[key] = transform?(v) ?? v
            }
        }
        addIfValue(schedule.minute, key: "Minute")
        addIfValue(schedule.hour, key: "Hour")
        addIfValue(schedule.day, key: "Day")
        addIfValue(schedule.month, key: "Month")
        addIfValue(schedule.weekday, key: "Weekday") { $0 == 7 ? 0 : $0 }
        return interval
    }

    static func nextRunDate(from schedule: CronSchedule, after date: Date = Date()) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0

        guard var current = calendar.date(from: components) else { return nil }
        current = calendar.date(byAdding: .minute, value: 1, to: current) ?? current

        for _ in 0 ..< (366 * 24 * 60) {
            let comps = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: current)

            if matches(schedule.minute, value: comps.minute ?? 0),
               matches(schedule.hour, value: comps.hour ?? 0),
               matches(schedule.day, value: comps.day ?? 1),
               matches(schedule.month, value: comps.month ?? 1),
               matchesWeekday(schedule.weekday, value: comps.weekday ?? 1)
            {
                return current
            }

            current = calendar.date(byAdding: .minute, value: 1, to: current) ?? current
        }

        return nil
    }

    private static func matches(_ field: CronField, value: Int) -> Bool {
        switch field {
        case .any:
            return true
        case let .value(v):
            return v == value
        case let .step(s):
            return value % s == 0
        case let .list(values):
            return values.contains(value)
        }
    }

    private static func matchesWeekday(_ field: CronField, value: Int) -> Bool {
        let adjusted = value == 1 ? 0 : value - 1
        switch field {
        case .any:
            return true
        case let .value(v):
            let cronValue = v == 7 ? 0 : v
            return cronValue == adjusted
        case let .step(s):
            return adjusted % s == 0
        case let .list(values):
            return values.map { $0 == 7 ? 0 : $0 }.contains(adjusted)
        }
    }
}
