import SwiftUI

enum LaunchScreen: String {
    case tripList, tripDetail, newExpense
    static let demo: LaunchScreen = ProcessInfo.processInfo.environment["DEMO_SCREEN"].flatMap(LaunchScreen.init(rawValue:)) ?? .tripList
}

struct RootView: View {
    @State private var tab: RootTab = .trips
    @State private var path: NavigationPath = {
        var p = NavigationPath()
        switch LaunchScreen.demo {
        case .tripList: break
        case .tripDetail: p.append(Route.trip(SampleData.trips[0]))
        case .newExpense:
            p.append(Route.trip(SampleData.trips[0]))
            p.append(Route.newExpense(SampleData.trips[0]))
        }
        return p
    }()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Group {
                    switch tab {
                    case .trips:
                        TripListView { trip in path.append(Route.trip(trip)) }
                    case .settings:
                        SettingsPlaceholderView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                RoamTabBar(selection: $tab)
            }
            .background(Sage.bg.ignoresSafeArea())
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .trip(let trip):
                    TripDetailView(trip: trip) {
                        path.append(Route.newExpense(trip))
                    }
                case .newExpense(let trip):
                    ExpenseEntryView(trip: trip) { path.removeLast() }
                }
            }
        }
        .tint(Sage.accent)
    }
}

enum Route: Hashable {
    case trip(DemoTrip)
    case newExpense(DemoTrip)
}

struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Sage.textSecondary)
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Sage.text)
            Text("Coming soon")
                .font(.system(size: 14))
                .foregroundStyle(Sage.textSecondary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView()
}
