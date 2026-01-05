import Foundation

struct ResticProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let configPath: String

    var displayName: String {
        name.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
