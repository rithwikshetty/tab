public enum SplitType: String, Codable, Sendable, CaseIterable {
    case equal
    case exact
    case percentage
    case shares
    case adjustment
}
