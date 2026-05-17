import SwiftUI

extension Color {
    init(_ hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum Sage {
    static let accent = Color(0x6F9866)
    static let accentStrong = Color(0x4F7549)
    static let accentSoft = Color(0x6F9866, alpha: 0.25)
    static let accentTint = Color(0xEEF2E7)
    static let accentGlow = Color(0x8FB282, alpha: 0.35)

    static let bg = Color(0xFAF7F0)
    static let surface = Color.white
    static let surface2 = Color(0xF1ECE2)

    static let text = Color(0x28281F)
    static let textSecondary = Color(0x777267)

    static let cardBorder = Color(0x3C321E, alpha: 0.06)
    static let rowDivider = Color(0x3C321E, alpha: 0.07)
    static let shadow = Color(0x323C28, alpha: 0.06)
    static let warning = Color(0xB16D3F)
    static let segmentedBg = Color(0x3C321E, alpha: 0.06)
    static let iconBg = Color(0xF1ECE2)
    static let tabBarBg = Color(0xFAF7F0, alpha: 0.88)
    static let tabBarBorder = Color(0x3C321E, alpha: 0.08)

    enum Avatar {
        static let terracotta = Color(0xB97047)
        static let sage = Color(0x859E62)
        static let sand = Color(0xB98B59)
        static let slate = Color(0x6B8DA6)
    }

    enum CategoryTone {
        static let food       = Color(0xB97047)
        static let transport  = Color(0x6B8DA6)
        static let lodging    = Color(0x8B6B96)
        static let activities = Color(0xC97A6B)
        static let shopping   = Color(0xB98B59)
        static let other      = Color(0x859E62)
    }

    static let markStart = accentStrong
    static let markCurve = accentStrong
    static let markEnd = Color(0xB97047)
}
