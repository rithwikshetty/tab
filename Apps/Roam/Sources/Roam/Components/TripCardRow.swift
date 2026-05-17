import SwiftUI

struct TripCardRow: View {
    let trip: DemoTrip

    private var statusColor: Color {
        switch trip.status {
        case .owed: Sage.accent
        case .owe: Sage.warning
        case .settled: Sage.textSecondary
        }
    }

    private var statusText: String {
        switch trip.status {
        case .owed(let s), .owe(let s), .settled(let s): s
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name)
                    .font(.tripName)
                    .tracking(-0.15)
                    .foregroundStyle(Sage.text)
                    .lineLimit(1)
                Text(statusText)
                    .font(.tripStatus)
                    .tracking(-0.07)
                    .foregroundStyle(statusColor)
            }
            Spacer(minLength: 8)
            AvatarGroup(members: trip.members, size: 28, borderWidth: 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .opacity(trip.isCompleted ? 0.72 : 1)
        .saturation(trip.isCompleted ? 0.7 : 1)
    }
}
