import Foundation

enum AvatarTone: CaseIterable, Hashable, Sendable {
    case terracotta, sage, sand, slate

    static func deterministic(for id: UUID) -> AvatarTone {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let sum = bytes.reduce(UInt8(0)) { $0 &+ $1 }
        return Self.allCases[Int(sum) % Self.allCases.count]
    }
}

enum AvatarInitial {
    static func from(_ displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}
