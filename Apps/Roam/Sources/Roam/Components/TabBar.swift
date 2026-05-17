import SwiftUI

enum RootTab: Hashable { case trips, settings }

struct RoamTabBar: View {
    @Binding var selection: RootTab

    var body: some View {
        HStack(spacing: 0) {
            tab(.trips, system: "suitcase", label: "Trips")
            tab(.settings, system: "gearshape", label: "Settings")
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(alignment: .top) {
            Rectangle()
                .fill(Sage.tabBarBorder)
                .frame(height: 1)
        }
        .background {
            Sage.tabBarBg
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tab(_ value: RootTab, system: String, label: String) -> some View {
        let isActive = selection == value
        return Button {
            selection = value
        } label: {
            VStack(spacing: 2) {
                Image(systemName: system)
                    .font(.system(size: 22, weight: .regular))
                    .opacity(isActive ? 1 : 0.85)
                Text(label)
                    .font(.tabLabel)
            }
            .foregroundStyle(isActive ? Sage.accent : Sage.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
