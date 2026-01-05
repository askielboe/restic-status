import Foundation

struct Profile: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var resticProfileId: String
    var schedules: [String]
    var status: BackupStatus

    init(id: UUID = UUID(), name: String, resticProfileId: String, schedules: [String] = []) {
        self.id = id
        self.name = name
        self.resticProfileId = resticProfileId
        self.schedules = schedules
        status = .initial
    }

    var nextBackupTime: Date? {
        let nextDates = schedules.compactMap { schedule -> Date? in
            guard let cronSchedule = CronParser.parse(schedule) else { return nil }
            return CronParser.nextRunDate(from: cronSchedule)
        }
        return nextDates.min()
    }

    var hasValidSchedules: Bool {
        schedules.isEmpty || schedules.allSatisfy { CronParser.parse($0) != nil }
    }

    func isValidSchedule(_ schedule: String) -> Bool {
        CronParser.parse(schedule) != nil
    }

    var formattedNextBackup: String {
        guard let next = nextBackupTime else { return "-" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: next, relativeTo: Date())
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, resticProfileId, schedules, schedule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        resticProfileId = try container.decode(String.self, forKey: .resticProfileId)
        if let schedulesList = try? container.decode([String].self, forKey: .schedules) {
            schedules = schedulesList
        } else if let singleSchedule = try container.decodeIfPresent(String.self, forKey: .schedule),
                  !singleSchedule.isEmpty
        {
            schedules = [singleSchedule]
        } else {
            schedules = []
        }
        status = .initial
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(resticProfileId, forKey: .resticProfileId)
        try container.encode(schedules, forKey: .schedules)
    }
}
