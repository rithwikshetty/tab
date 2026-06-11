import Foundation

enum AvatarTone: CaseIterable, Hashable, Sendable {
    case terracotta, sage, sand, slate

    static func deterministic(for id: UUID) -> AvatarTone {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let sum = bytes.reduce(UInt8(0)) { $0 &+ $1 }
        return Self.allCases[Int(sum) % Self.allCases.count]
    }

    /// Stable tone for a pending, email-only person. Uses the same byte-sum
    /// scheme as the claim-identity tone so a person's colour matches across
    /// the Friends tab and the non-group picker, and survives app relaunch
    /// (unlike a per-process `Hasher`).
    static func deterministic(forEmail email: String) -> AvatarTone {
        let sum = email.utf8.reduce(UInt8(0)) { $0 &+ $1 }
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
